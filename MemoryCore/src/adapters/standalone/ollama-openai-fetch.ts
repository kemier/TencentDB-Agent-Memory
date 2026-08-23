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
}

interface OllamaChatResponse {
  message?: {
    role?: string;
    content?: string;
    thinking?: string;
    tool_calls?: unknown[];
  };
  done?: boolean;
}

/**
 * Wrap fetch so OpenAI-compat calls to Ollama inject native `think` mode.
 * Ollama's /v1/chat/completions ignores `think`; /api/chat honors it.
 */
export function createOllamaThinkFetch(
  baseUrl: string,
  think: OllamaThinkMode,
  innerFetch: FetchFunction = fetch,
): FetchFunction {
  if (!isOllamaBaseUrl(baseUrl)) {
    return innerFetch;
  }

  return async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    if (!url.includes('/chat/completions') || (init?.method ?? 'GET').toUpperCase() !== 'POST') {
      return innerFetch(input, init);
    }

    const rawBody = init?.body;
    if (typeof rawBody !== 'string') {
      return innerFetch(input, init);
    }

    let req: OpenAiChatRequest;
    try {
      req = JSON.parse(rawBody) as OpenAiChatRequest;
    } catch {
      return innerFetch(input, init);
    }

    // Streaming translation is out of scope; fall back to default path.
    if (req.stream) {
      return innerFetch(input, init);
    }

    const maxTokens = req.max_completion_tokens ?? req.max_tokens;
    const nativeBody: Record<string, unknown> = {
      model: req.model,
      messages: req.messages ?? [],
      stream: false,
      think,
    };
    if (req.tools) {
      nativeBody.tools = req.tools;
    }
    if (req.tool_choice !== undefined) {
      nativeBody.tool_choice = req.tool_choice;
    }
    const options: Record<string, unknown> = {};
    if (maxTokens !== undefined) {
      options.num_predict = maxTokens;
    }
    if (req.temperature !== undefined) {
      options.temperature = req.temperature;
    }
    if (req.top_p !== undefined) {
      options.top_p = req.top_p;
    }
    if (Object.keys(options).length > 0) {
      nativeBody.options = options;
    }

    const nativeResp = await innerFetch(toNativeChatUrl(url), {
      ...init,
      body: JSON.stringify(nativeBody),
    });
    if (!nativeResp.ok) {
      return nativeResp;
    }

    const nativeJson = (await nativeResp.json()) as OllamaChatResponse;
    const msg = nativeJson.message ?? {};
    const openAiBody = {
      id: 'chatcmpl-ollama',
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: req.model ?? '',
      choices: [
        {
          index: 0,
          message: {
            role: msg.role ?? 'assistant',
            content: msg.content ?? '',
            ...(msg.tool_calls ? { tool_calls: msg.tool_calls } : {}),
          },
          finish_reason: 'stop',
        },
      ],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
    };

    return new Response(JSON.stringify(openAiBody), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  };
}
