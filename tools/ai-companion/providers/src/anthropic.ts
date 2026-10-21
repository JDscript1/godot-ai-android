import type {
  CanonicalMessage,
  CanonicalRequest,
  CanonicalTurnResult,
  ProviderModel,
} from "../../packages/protocol/src/index.js";
import {
  parseProviderResponse,
  requireApiKey,
  textFromCanonical,
  type ProviderAdapter,
  type ProviderConnection,
} from "./types.js";

export class AnthropicAdapter implements ProviderAdapter {
  readonly kind = "anthropic" as const;
  readonly capabilities = {
    text: true,
    vision: true,
    streaming: true,
    nativeTools: true,
    strictTools: false,
    parallelTools: true,
    structuredOutput: true,
    nativeWebSearch: false,
    promptCaching: false,
  };

  async listModels(connection: ProviderConnection): Promise<ProviderModel[]> {
    const response = await fetch(`${baseUrl(connection)}/models`, { headers: headers(connection) });
    const result = (await parseProviderResponse(response)) as { data?: Array<{ id?: string; display_name?: string }> };
    return (result.data ?? [])
      .filter((model): model is { id: string; display_name?: string } => Boolean(model.id))
      .map((model) => ({ id: model.id, ...(model.display_name ? { displayName: model.display_name } : {}) }));
  }

  async complete(
    connection: ProviderConnection,
    request: CanonicalRequest,
    signal?: AbortSignal,
  ): Promise<CanonicalTurnResult> {
    const response = await fetch(`${baseUrl(connection)}/messages`, {
      method: "POST",
      headers: { ...headers(connection), "Content-Type": "application/json" },
      body: JSON.stringify({
        model: request.model,
        max_tokens: request.maxOutputTokens ?? 8192,
        system: textFromCanonical(request, "system"),
        messages: coalesceAnthropicMessages(request.messages.filter((message) => message.role !== "system")),
        tools: request.tools.map((tool) => ({
          name: tool.name,
          description: tool.description,
          input_schema: tool.inputSchema,
        })),
        ...(request.effort ? { output_config: { effort: mapEffort(request.effort) } } : {}),
      }),
      ...(signal ? { signal } : {}),
    });
    const result = (await parseProviderResponse(response)) as {
      id?: string;
      stop_reason?: string;
      content?: Array<{ type?: string; text?: string; id?: string; name?: string; input?: unknown }>;
      usage?: { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number };
    };
    const content = result.content ?? [];
    const toolCalls = content
      .filter((item) => item.type === "tool_use" && item.name)
      .map((item) => ({ id: item.id ?? crypto.randomUUID(), name: item.name!, arguments: item.input ?? {} }));
    return {
      text: content.filter((item) => item.type === "text").map((item) => item.text ?? "").join(""),
      toolCalls,
      stopReason: toolCalls.length ? "tool_calls" : mapStopReason(result.stop_reason),
      providerState: result.id ? { responseId: result.id } : undefined,
      usage: result.usage
        ? {
            inputTokens: result.usage.input_tokens,
            outputTokens: result.usage.output_tokens,
            cachedTokens: result.usage.cache_read_input_tokens,
          }
        : undefined,
    };
  }
}

function mapEffort(effort: NonNullable<CanonicalRequest["effort"]>): string {
  if (effort === "none" || effort === "minimal") return "low";
  return effort === "balanced" ? "medium" : effort;
}

function coalesceAnthropicMessages(messages: CanonicalMessage[]): Array<Record<string, unknown>> {
  const result: Array<{ role: "user" | "assistant"; content: Array<Record<string, unknown>> }> = [];
  for (const message of messages) {
    const role = message.role === "assistant" ? "assistant" : "user";
    const content: Array<Record<string, unknown>> = [];
    if (message.role === "tool") {
      content.push({
        type: "tool_result",
        tool_use_id: message.toolCallId,
        content: contentText(message),
      });
    } else {
      for (const item of message.content) {
        if (item.type === "text") content.push({ type: "text", text: item.text });
        else if (item.type === "image" && item.data) {
          content.push({ type: "image", source: { type: "base64", media_type: item.mimeType, data: item.data } });
        } else content.push({ type: "text", text: JSON.stringify(item) });
      }
      for (const call of message.toolCalls ?? []) {
        content.push({ type: "tool_use", id: call.id, name: call.name, input: call.arguments });
      }
    }
    const previous = result.at(-1);
    if (previous?.role === role) previous.content.push(...content);
    else result.push({ role, content });
  }
  return result;
}

function contentText(message: CanonicalMessage): string {
  return message.content.map((content) => content.type === "text" ? content.text : JSON.stringify(content)).join("\n");
}

function baseUrl(connection: ProviderConnection): string {
  return (connection.baseUrl ?? "https://api.anthropic.com/v1").replace(/\/+$/, "");
}

function headers(connection: ProviderConnection): Record<string, string> {
  return {
    "x-api-key": requireApiKey(connection),
    "anthropic-version": "2023-06-01",
  };
}

function mapStopReason(reason: string | undefined): CanonicalTurnResult["stopReason"] {
  if (reason === "max_tokens") return "length";
  if (reason === "refusal") return "refusal";
  return "completed";
}
