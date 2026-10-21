import type {
  CanonicalContent,
  CanonicalMessage,
  CanonicalRequest,
  CanonicalToolCall,
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

type OpenAIOutputItem = {
  type?: string;
  id?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  content?: Array<{ type?: string; text?: string }>;
};

export class OpenAIResponsesAdapter implements ProviderAdapter {
  readonly kind = "openai" as const;
  readonly capabilities = {
    text: true,
    vision: true,
    streaming: true,
    nativeTools: true,
    strictTools: true,
    parallelTools: true,
    structuredOutput: true,
    nativeWebSearch: true,
    promptCaching: true,
  };

  async listModels(connection: ProviderConnection): Promise<ProviderModel[]> {
    const baseUrl = normalizeBaseUrl(connection.baseUrl ?? "https://api.openai.com/v1");
    const response = await fetch(`${baseUrl}/models`, {
      headers: { Authorization: `Bearer ${requireApiKey(connection)}` },
    });
    const body = (await parseProviderResponse(response)) as { data?: Array<{ id?: string }> };
    return (body.data ?? [])
      .filter((model): model is { id: string } => Boolean(model.id))
      .map((model) => ({ id: model.id }));
  }

  async complete(
    connection: ProviderConnection,
    request: CanonicalRequest,
    signal?: AbortSignal,
  ): Promise<CanonicalTurnResult> {
    const baseUrl = normalizeBaseUrl(connection.baseUrl ?? "https://api.openai.com/v1");
    const previousResponseId = stringField(request.providerState, "previousResponseId");
    const input = previousResponseId
      ? request.messages.filter((message) => message.role === "tool").slice(-16).map(toOpenAIInput)
      : request.messages.filter((message) => message.role !== "system").map(toOpenAIInput);
    const body: Record<string, unknown> = {
      model: request.model,
      input,
      tools: request.tools.map((tool) => ({
        type: "function",
        name: tool.name,
        description: tool.description,
        parameters: tool.inputSchema,
        strict: true,
      })),
    };
    const instructions = textFromCanonical(request, "system");
    if (instructions) body.instructions = instructions;
    if (previousResponseId) body.previous_response_id = previousResponseId;
    if (request.maxOutputTokens) body.max_output_tokens = request.maxOutputTokens;
    if (request.effort) body.reasoning = { effort: mapReasoningEffort(request.effort) };

    const response = await fetch(`${baseUrl}/responses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requireApiKey(connection)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      ...(signal ? { signal } : {}),
    });
    const result = (await parseProviderResponse(response)) as {
      id?: string;
      status?: string;
      output_text?: string;
      output?: OpenAIOutputItem[];
      usage?: { input_tokens?: number; output_tokens?: number; input_tokens_details?: { cached_tokens?: number } };
    };
    const output = result.output ?? [];
    const text = result.output_text ?? output
      .flatMap((item) => item.content ?? [])
      .filter((item) => item.type === "output_text" && typeof item.text === "string")
      .map((item) => item.text)
      .join("");
    const toolCalls: CanonicalToolCall[] = output
      .filter((item) => item.type === "function_call" && item.name)
      .map((item) => ({
        id: item.call_id ?? item.id ?? crypto.randomUUID(),
        name: item.name!,
        arguments: parseJsonArguments(item.arguments),
      }));
    return {
      text,
      toolCalls,
      stopReason: toolCalls.length ? "tool_calls" : result.status === "completed" ? "completed" : "error",
      providerState: result.id ? { previousResponseId: result.id } : undefined,
      usage: result.usage
        ? {
            inputTokens: result.usage.input_tokens,
            outputTokens: result.usage.output_tokens,
            cachedTokens: result.usage.input_tokens_details?.cached_tokens,
          }
        : undefined,
    };
  }
}

function toOpenAIInput(message: CanonicalMessage): unknown {
  if (message.role === "tool") {
    return {
      type: "function_call_output",
      call_id: message.toolCallId,
      output: contentAsText(message.content),
    };
  }
  const content = message.content.map((item) => {
    if (item.type === "text") {
      return { type: message.role === "assistant" ? "output_text" : "input_text", text: item.text };
    }
    if (item.type === "image") {
      return { type: "input_image", image_url: item.url ?? `data:${item.mimeType};base64,${item.data ?? ""}` };
    }
    if (item.type === "file") {
      return { type: "input_file", filename: item.name, file_data: item.data };
    }
    return { type: "input_text", text: JSON.stringify(item.value) };
  });
  return { role: message.role, content };
}

function contentAsText(content: CanonicalContent[]): string {
  return content.map((item) => item.type === "text" ? item.text : JSON.stringify(item)).join("\n");
}

function normalizeBaseUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

function stringField(value: Record<string, unknown> | undefined, field: string): string | undefined {
  const candidate = value?.[field];
  return typeof candidate === "string" ? candidate : undefined;
}

function parseJsonArguments(value: string | undefined): unknown {
  if (!value) return {};
  try {
    return JSON.parse(value);
  } catch {
    return { _invalidJson: value };
  }
}

function mapReasoningEffort(effort: NonNullable<CanonicalRequest["effort"]>): string {
  return effort === "balanced" ? "medium" : effort;
}
