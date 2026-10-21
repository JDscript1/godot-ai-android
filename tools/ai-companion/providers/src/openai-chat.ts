import type {
  CanonicalMessage,
  CanonicalRequest,
  CanonicalTurnResult,
  ProviderKind,
  ProviderModel,
} from "../../packages/protocol/src/index.js";
import {
  parseProviderResponse,
  type ProviderAdapter,
  type ProviderConnection,
} from "./types.js";

type ChatChoice = {
  finish_reason?: string;
  message?: {
    content?: string | null;
    tool_calls?: Array<{
      id?: string;
      function?: { name?: string; arguments?: string | Record<string, unknown> };
    }>;
  };
};

const DEFAULT_BASE_URLS: Partial<Record<ProviderKind, string>> = {
  deepseek: "https://api.deepseek.com",
  "llama-cpp": "http://127.0.0.1:8080/v1",
  ollama: "http://127.0.0.1:11434/v1",
};

export class OpenAIChatAdapter implements ProviderAdapter {
  readonly capabilities = {
    text: true,
    vision: false,
    streaming: true,
    nativeTools: true,
    strictTools: false,
    parallelTools: true,
    structuredOutput: true,
    nativeWebSearch: false,
    promptCaching: false,
  };

  constructor(readonly kind: Exclude<ProviderKind, "openai" | "gemini" | "anthropic">) {}

  async listModels(connection: ProviderConnection): Promise<ProviderModel[]> {
    const response = await fetch(`${this.#baseUrl(connection)}/models`, {
      headers: this.#headers(connection),
    });
    const body = (await parseProviderResponse(response)) as { data?: Array<{ id?: string }> };
    return (body.data ?? []).filter((item): item is { id: string } => Boolean(item.id)).map((item) => ({ id: item.id }));
  }

  async complete(
    connection: ProviderConnection,
    request: CanonicalRequest,
    signal?: AbortSignal,
  ): Promise<CanonicalTurnResult> {
    const body: Record<string, unknown> = {
      model: request.model,
      messages: request.messages.map(toChatMessage),
      tools: request.tools.map((tool) => ({
        type: "function",
        function: {
          name: tool.name,
          description: tool.description,
          parameters: tool.inputSchema,
          ...(this.kind === "deepseek" ? { strict: true } : {}),
        },
      })),
      tool_choice: "auto",
    };
    if (request.maxOutputTokens) body.max_tokens = request.maxOutputTokens;
    if (this.kind === "deepseek" && request.effort) {
      body.reasoning_effort = request.effort === "max" ? "max" : request.effort === "minimal" || request.effort === "low" ? "low" : "high";
    }
    const response = await fetch(`${this.#baseUrl(connection)}/chat/completions`, {
      method: "POST",
      headers: { ...this.#headers(connection), "Content-Type": "application/json" },
      body: JSON.stringify(body),
      ...(signal ? { signal } : {}),
    });
    const result = (await parseProviderResponse(response)) as {
      choices?: ChatChoice[];
      usage?: { prompt_tokens?: number; completion_tokens?: number; prompt_cache_hit_tokens?: number };
    };
    const choice = result.choices?.[0];
    const toolCalls = (choice?.message?.tool_calls ?? [])
      .filter((call) => call.function?.name)
      .map((call) => ({
        id: call.id ?? crypto.randomUUID(),
        name: call.function!.name!,
        arguments: parseArguments(call.function!.arguments),
      }));
    return {
      text: choice?.message?.content ?? "",
      toolCalls,
      stopReason: toolCalls.length ? "tool_calls" : mapStopReason(choice?.finish_reason),
      usage: result.usage
        ? {
            inputTokens: result.usage.prompt_tokens,
            outputTokens: result.usage.completion_tokens,
            cachedTokens: result.usage.prompt_cache_hit_tokens,
          }
        : undefined,
    };
  }

  #baseUrl(connection: ProviderConnection): string {
    const configured = connection.baseUrl ?? DEFAULT_BASE_URLS[this.kind];
    if (!configured) throw new Error(`Provider ${connection.name} requires a base URL`);
    return configured.replace(/\/+$/, "");
  }

  #headers(connection: ProviderConnection): Record<string, string> {
    if (!connection.apiKey && this.kind !== "llama-cpp" && this.kind !== "ollama") {
      throw new Error(`Provider ${connection.name} does not have an API key`);
    }
    return connection.apiKey ? { Authorization: `Bearer ${connection.apiKey}` } : {};
  }
}

function toChatMessage(message: CanonicalMessage): Record<string, unknown> {
  const text = message.content.map((content) => content.type === "text" ? content.text : JSON.stringify(content)).join("\n");
  if (message.role === "assistant" && message.toolCalls?.length) {
    return {
      role: "assistant",
      content: text || null,
      tool_calls: message.toolCalls.map((call) => ({
        id: call.id,
        type: "function",
        function: { name: call.name, arguments: JSON.stringify(call.arguments) },
      })),
    };
  }
  if (message.role === "tool") {
    return { role: "tool", tool_call_id: message.toolCallId, content: text };
  }
  if (message.role === "user" && message.content.some((content) => content.type === "image")) {
    return {
      role: "user",
      content: message.content.map((content) => {
        if (content.type === "text") return { type: "text", text: content.text };
        if (content.type === "image") {
          return { type: "image_url", image_url: { url: content.url ?? `data:${content.mimeType};base64,${content.data ?? ""}` } };
        }
        return { type: "text", text: JSON.stringify(content) };
      }),
    };
  }
  return { role: message.role, content: text };
}

function parseArguments(value: string | Record<string, unknown> | undefined): unknown {
  if (value === undefined) return {};
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch {
    return { _invalidJson: value };
  }
}

function mapStopReason(value: string | undefined): CanonicalTurnResult["stopReason"] {
  if (value === "length") return "length";
  if (value === "content_filter") return "refusal";
  return "completed";
}
