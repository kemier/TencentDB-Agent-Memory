import type { FetchFunction } from '@ai-sdk/provider-utils';

/** Ollama thinking mode for native /api/chat (ignored by plain OpenAI backends). */
export type OllamaThinkMode = boolean | 'low' | 'medium' | 'high';

function isOllamaBaseUrl(baseUrl: string): boolean {
  try {
    const u = new URL(baseUrl);
    return u.port === '11434' || u.hostname === 'ollama';
  } catch {
    return baseUrl.includes(':11434');
  }
}

function toNativeChatUrl(openAiUrl: string): string {
  const u = new URL(openAiUrl);
  u.pathname = u.pathname.replace(/\/v1\/chat\/completions\/?$/, '/api/chat');
  return u.toString();
}

interface OpenAiChatRequest {
  model?: string;
  messages?: Array<{ role: string; content?: unknown; tool_calls?: unknown; tool_call_id?: string; name?: string }>;
  max_tokens?: number;
  max_completion_tokens?: number;
  temperature?: number;
  top_p?: number;
  tools?: unknown;
  tool_choice?: unknown;
  stream?: boolean;
  response_format?: { type?: string; json_schema?: { schema?: unknown } };
}

/**
 * OpenAI chat schema (AI SDK zod) requires `tool_calls[].type === "function"`
 * and `function.arguments` to be a JSON string. Ollama-native returns arguments
 * as an object and omits `type`. Either mismatch becomes
 * `APICallError: Invalid JSON response`, which the skill worker treats as
 * permanent and dead-letters. Rebuild a schema-safe completion instead.
 */
export function normalizeOpenAiChatCompletion(parsed: unknown): Record<string, unknown> | null {
  if (!parsed || typeof parsed !== 'object') return null;
  const root = parsed as Record<string, unknown>;

  if (!Array.isArray(root.choices) && root.message && typeof root.message === 'object') {
    return normalizeOpenAiChatCompletion({
      id: 'chatcmpl-ollama',
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: typeof root.model === 'string' ? root.model : '',
      choices: [{ index: 0, message: root.message, finish_reason: 'stop' }],
      usage: {
        prompt_tokens: root.prompt_eval_count,
        completion_tokens: root.eval_count,
        total_tokens: 0,
      },
    });
  }
  if (!Array.isArray(root.choices)) return null;

  const choices = root.choices.map((ch, i) => {
    const c = ch && typeof ch === 'object' ? (ch as Record<string, unknown>) : {};
    const msg = c.message && typeof c.message === 'object' ? (c.message as Record<string, unknown>) : {};
    const toolCalls = Array.isArray(msg.tool_calls)
      ? msg.tool_calls
          .map((tc, j) => normalizeToolCall(tc, j))
          .filter((tc): tc is NonNullable<typeof tc> => tc != null)
      : [];
    const message: Record<string, unknown> = {
      role: 'assistant',
      content: coerceContent(msg.content),
    };
    if (toolCalls.length > 0) message.tool_calls = toolCalls;
    return {
      index: typeof c.index === 'number' ? c.index : i,
      message,
      finish_reason: typeof c.finish_reason === 'string' ? c.finish_reason : 'stop',
    };
  });

  const usageIn = root.usage && typeof root.usage === 'object' ? (root.usage as Record<string, unknown>) : {};
  const usage: Record<string, number> = {};
  for (const key of ['prompt_tokens', 'completion_tokens', 'total_tokens'] as const) {
    const n = finiteNumber(usageIn[key]);
    if (n !== undefined) usage[key] = n;
  }

  return {
    id: typeof root.id === 'string' ? root.id : 'chatcmpl-normalized',
    object: 'chat.completion',
    created: finiteNumber(root.created) ?? Math.floor(Date.now() / 1000),
    model: typeof root.model === 'string' ? root.model : '',
    choices,
    usage,
  };
}

function finiteNumber(v: unknown): number | undefined {
  return typeof v === 'number' && Number.isFinite(v) ? v : undefined;
}

function coerceContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (content == null) return '';
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part && typeof part === 'object' && typeof (part as { text?: unknown }).text === 'string') {
          return (part as { text: string }).text;
        }
        return '';
      })
      .join('');
  }
  try {
    return JSON.stringify(content);
  } catch {
    return '';
  }
}

function argumentsToString(args: unknown): string {
  if (typeof args === 'string') return args;
  if (args == null) return '{}';
  try {
    return JSON.stringify(args);
  } catch {
    return '{}';
  }
}

function normalizeToolCall(
  tc: unknown,
  index: number,
): { id: string; type: 'function'; function: { name: string; arguments: string } } | null {
  if (!tc || typeof tc !== 'object') return null;
  const o = tc as Record<string, unknown>;
  const fn = o.function && typeof o.function === 'object' ? (o.function as Record<string, unknown>) : null;
  const nameRaw = fn?.name ?? o.name;
  const name = typeof nameRaw === 'string' ? nameRaw : '';
  const args = fn ? fn.arguments : o.arguments;
  if (!name && args == null) return null;
  const id = typeof o.id === 'string' && o.id.length > 0 ? o.id : `call_${index}`;
  return {
    id,
    type: 'function',
    function: { name, arguments: argumentsToString(args) },
  };
}

/** Ollama-native /api/chat wants function.arguments as an object, not a string. */
function messagesForNativeChat(messages: OpenAiChatRequest['messages']): unknown[] {
  return (messages ?? []).map((msg) => {
    if (!Array.isArray(msg.tool_calls)) return msg;
    return {
      ...msg,
      tool_calls: msg.tool_calls.map((tc) => {
        if (!tc || typeof tc !== 'object') return tc;
        const o = tc as Record<string, unknown>;
        const fn = o.function && typeof o.function === 'object' ? (o.function as Record<string, unknown>) : null;
        if (!fn || typeof fn.arguments !== 'string') return tc;
        try {
          const parsed = JSON.parse(fn.arguments) as unknown;
          if (parsed && typeof parsed === 'object') {
            return { ...o, function: { ...fn, arguments: parsed } };
          }
        } catch {
          /* leave the original string */
        }
        return tc;
      }),
    };
  });
}

function responseWithJson(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Wrap fetch so chat completions the AI SDK validates are OpenAI-shaped.
 *
 * Direct Ollama (:11434) is rewritten to native /api/chat so `think` is honored
 * (`/v1/chat/completions` ignores it). Proxy routes (the Mac gateway uses
 * :8317) are passed through, then the response is normalized the same way —
 * the proxy's own normalizer is not always enough, and a schema miss dead-letters
 * skill extraction.
 */
export function createOllamaThinkFetch(
  baseUrl: string,
  think: OllamaThinkMode,
  innerFetch: FetchFunction = fetch,
): FetchFunction {
  const native = isOllamaBaseUrl(baseUrl);

  return async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const method = (init?.method ?? 'GET').toUpperCase();
    if (!url.includes('/chat/completions') || method !== 'POST') {
      return innerFetch(input, init);
    }

    const rawBody = init?.body;
    let req: OpenAiChatRequest | null = null;
    if (typeof rawBody === 'string') {
      try {
        req = JSON.parse(rawBody) as OpenAiChatRequest;
      } catch {
        req = null;
      }
    }

    if (req?.stream) {
      return innerFetch(input, init);
    }

    let nextInput: Parameters<FetchFunction>[0] = input;
    let nextInit = init;
    if (native && req) {
      const maxTokens = req.max_completion_tokens ?? req.max_tokens;
      const nativeBody: Record<string, unknown> = {
        model: req.model,
        messages: messagesForNativeChat(req.messages),
        stream: false,
        think,
      };
      if (req.tools) nativeBody.tools = req.tools;
      if (req.tool_choice !== undefined) nativeBody.tool_choice = req.tool_choice;
      if (req.response_format?.type === 'json_object') {
        nativeBody.format = 'json';
      } else if (req.response_format?.type === 'json_schema' && req.response_format.json_schema?.schema) {
        nativeBody.format = req.response_format.json_schema.schema;
      }
      const options: Record<string, unknown> = {};
      if (maxTokens !== undefined) options.num_predict = maxTokens;
      if (req.temperature !== undefined) options.temperature = req.temperature;
      if (req.top_p !== undefined) options.top_p = req.top_p;
      if (Object.keys(options).length > 0) nativeBody.options = options;
      nextInput = toNativeChatUrl(url);
      nextInit = { ...init, body: JSON.stringify(nativeBody) };
    }

    const resp = await innerFetch(nextInput, nextInit);
    if (!resp.ok) return resp;
    const contentType = resp.headers.get('content-type') ?? '';
    if (contentType.includes('text/event-stream')) return resp;

    const text = await resp.text();
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      return new Response(text, { status: resp.status, headers: { 'Content-Type': contentType || 'text/plain' } });
    }
    const normalized = normalizeOpenAiChatCompletion(parsed);
    if (!normalized) {
      return new Response(text, { status: resp.status, headers: { 'Content-Type': 'application/json' } });
    }
    return responseWithJson(normalized, resp.status);
  };
}
