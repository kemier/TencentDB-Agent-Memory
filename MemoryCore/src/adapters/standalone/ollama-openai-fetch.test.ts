import { describe, expect, it } from "vitest";
import { createOllamaThinkFetch, normalizeOpenAiChatCompletion } from "./ollama-openai-fetch.js";

describe("normalizeOpenAiChatCompletion", () => {
  it("stringifies Ollama object arguments and fills type", () => {
    const out = normalizeOpenAiChatCompletion({
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: "",
            tool_calls: [
              {
                id: "call_1",
                function: { name: "skill_list", arguments: { query: "hi" } },
              },
            ],
          },
        },
      ],
    });
    const call = (out?.choices as Array<{ message: { tool_calls: Array<{ type: string; function: { arguments: string } }> } }>)[0]
      .message.tool_calls[0];
    expect(call.type).toBe("function");
    expect(call.function.arguments).toBe('{"query":"hi"}');
  });

  it("coerces array content to a string", () => {
    const out = normalizeOpenAiChatCompletion({
      choices: [{ message: { content: [{ type: "text", text: "CUDA" }, " build"] } }],
    });
    const content = (out?.choices as Array<{ message: { content: string } }>)[0].message.content;
    expect(content).toBe("CUDA build");
  });

  it("accepts a raw Ollama /api/chat body", () => {
    const out = normalizeOpenAiChatCompletion({
      model: "qwen3.6:35b",
      message: {
        role: "assistant",
        content: null,
        tool_calls: [{ function: { name: "skill_create", arguments: null } }],
      },
    });
    const msg = (out?.choices as Array<{ message: { content: string; tool_calls: Array<{ type: string; function: { arguments: string; name: string } }> } }>)[0]
      .message;
    expect(msg.content).toBe("");
    expect(msg.tool_calls[0].type).toBe("function");
    expect(msg.tool_calls[0].function.name).toBe("skill_create");
    expect(msg.tool_calls[0].function.arguments).toBe("{}");
  });
});

describe("createOllamaThinkFetch", () => {
  it("normalizes a proxy chat completion without rewriting the URL", async () => {
    let seenUrl = "";
    const fetchFn = createOllamaThinkFetch("http://127.0.0.1:8317/v1", false, async (input) => {
      seenUrl = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
      return new Response(
        JSON.stringify({
          choices: [
            {
              message: {
                content: "",
                tool_calls: [{ function: { name: "skill_list", arguments: { query: "" } } }],
              },
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/octet-stream" } },
      );
    });
    const res = await fetchFn("http://127.0.0.1:8317/v1/chat/completions", {
      method: "POST",
      body: JSON.stringify({ model: "qwen36-35b", messages: [{ role: "user", content: "hi" }] }),
    });
    expect(seenUrl).toContain("/v1/chat/completions");
    const body = await res.json() as { choices: Array<{ message: { tool_calls: Array<{ type: string; function: { arguments: string } }> } }> };
    expect(body.choices[0].message.tool_calls[0].type).toBe("function");
    expect(body.choices[0].message.tool_calls[0].function.arguments).toBe('{"query":""}');
    expect(res.headers.get("content-type")).toContain("application/json");
  });

  it("rewrites direct Ollama calls to /api/chat and parses object arguments in history", async () => {
    let seenUrl = "";
    let seenBody: { think?: boolean; messages?: Array<{ tool_calls?: Array<{ function: { arguments: unknown } }> }> } = {};
    const fetchFn = createOllamaThinkFetch("http://127.0.0.1:11434/v1", false, async (input, init) => {
      seenUrl = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
      seenBody = JSON.parse(String(init?.body));
      return new Response(
        JSON.stringify({
          message: { role: "assistant", content: "ok" },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    });
    const res = await fetchFn("http://127.0.0.1:11434/v1/chat/completions", {
      method: "POST",
      body: JSON.stringify({
        model: "qwen3.6:35b",
        messages: [
          {
            role: "assistant",
            tool_calls: [{ function: { name: "skill_list", arguments: '{"query":"hi"}' } }],
          },
        ],
      }),
    });
    expect(seenUrl).toBe("http://127.0.0.1:11434/api/chat");
    expect(seenBody.think).toBe(false);
    expect(seenBody.messages?.[0].tool_calls?.[0].function.arguments).toEqual({ query: "hi" });
    const body = await res.json() as { choices: Array<{ message: { content: string } }> };
    expect(body.choices[0].message.content).toBe("ok");
  });
});
