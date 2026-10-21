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

export class GeminiAdapter implements ProviderAdapter {
  readonly kind = "gemini" as const;
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
    const response = await fetch(`${baseUrl(connection)}/models`, {
      headers: { "x-goog-api-key": requireApiKey(connection) },
    });
    const result = (await parseProviderResponse(response)) as {
      models?: Array<{ name?: string; displayName?: string; supportedGenerationMethods?: string[]; inputTokenLimit?: number }>;
    };
    return (result.models ?? [])
      .filter((model) => model.name && model.supportedGenerationMethods?.includes("generateContent"))
      .map((model) => ({
        id: model.name!.replace(/^models\//, ""),
        ...(model.displayName ? { displayName: model.displayName } : {}),
        ...(model.inputTokenLimit ? { capabilities: { maxContextTokens: model.inputTokenLimit } } : {}),
      }));
  }

  async complete(
    connection: ProviderConnection,
    request: CanonicalRequest,
    signal?: AbortSignal,
  ): Promise<CanonicalTurnResult> {
    const body: Record<string, unknown> = {
      contents: request.messages.filter((message) => message.role !== "system").map(toGeminiContent),
      tools: request.tools.length
        ? [{ functionDeclarations: request.tools.map((tool) => ({
            name: tool.name,
            description: tool.description,
            parametersJsonSchema: tool.inputSchema,
          })) }]
        : [],
      generationConfig: {
        ...(request.maxOutputTokens ? { maxOutputTokens: request.maxOutputTokens } : {}),
        ...(request.effort ? { thinkingConfig: { thinkingLevel: mapThinkingLevel(request.effort) } } : {}),
      },
    };
    const system = textFromCanonical(request, "system");
    if (system) body.systemInstruction = { parts: [{ text: system }] };

    const response = await fetch(
      `${baseUrl(connection)}/models/${encodeURIComponent(request.model)}:generateContent`,
      {
        method: "POST",
        headers: {
          "x-goog-api-key": requireApiKey(connection),
          "Content-Type": "application/json",
          "x-goog-api-client": "godot-agent/0.1.0",
        },
        body: JSON.stringify(body),
        ...(signal ? { signal } : {}),
      },
    );
    const result = (await parseProviderResponse(response)) as {
      candidates?: Array<{
        finishReason?: string;
        content?: { parts?: Array<{ text?: string; thoughtSignature?: string; functionCall?: { id?: string; name?: string; args?: unknown } }> };
      }>;
      usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; cachedContentTokenCount?: number };
    };
    const candidate = result.candidates?.[0];
    const parts = candidate?.content?.parts ?? [];
    const toolCalls = parts
      .filter((part) => part.functionCall?.name)
      .map((part) => ({
        id: part.functionCall!.id ?? crypto.randomUUID(),
        name: part.functionCall!.name!,
        arguments: part.functionCall!.args ?? {},
        ...(part.thoughtSignature ? { providerData: { thoughtSignature: part.thoughtSignature } } : {}),
      }));
    return {
      text: parts.map((part) => part.text ?? "").join(""),
      toolCalls,
      stopReason: toolCalls.length ? "tool_calls" : mapFinishReason(candidate?.finishReason),
      usage: result.usageMetadata
        ? {
            inputTokens: result.usageMetadata.promptTokenCount,
            outputTokens: result.usageMetadata.candidatesTokenCount,
            cachedTokens: result.usageMetadata.cachedContentTokenCount,
          }
        : undefined,
    };
  }
}

function toGeminiContent(message: CanonicalMessage): Record<string, unknown> {
  if (message.role === "tool") {
    return {
      role: "user",
      parts: [{
        functionResponse: {
          id: message.toolCallId,
          name: message.toolName,
          response: { result: contentText(message) },
        },
      }],
    };
  }
  const parts: Array<Record<string, unknown>> = message.content.map((content) => {
    if (content.type === "text") return { text: content.text };
    if (content.type === "image" && content.data) {
      return { inlineData: { mimeType: content.mimeType, data: content.data } };
    }
    if (content.type === "file" && content.data) {
      return { inlineData: { mimeType: content.mimeType, data: content.data } };
    }
    return { text: JSON.stringify(content) };
  });
  for (const call of message.toolCalls ?? []) {
    parts.push({
      functionCall: { id: call.id, name: call.name, args: call.arguments },
      ...(typeof call.providerData?.thoughtSignature === "string"
        ? { thoughtSignature: call.providerData.thoughtSignature }
        : {}),
    });
  }
  return { role: message.role === "assistant" ? "model" : "user", parts };
}

function contentText(message: CanonicalMessage): string {
  return message.content.map((content) => content.type === "text" ? content.text : JSON.stringify(content)).join("\n");
}

function baseUrl(connection: ProviderConnection): string {
  return (connection.baseUrl ?? "https://generativelanguage.googleapis.com/v1beta").replace(/\/+$/, "");
}

function mapThinkingLevel(effort: NonNullable<CanonicalRequest["effort"]>): string {
  if (effort === "minimal") return "MINIMAL";
  if (effort === "balanced") return "MEDIUM";
  if (effort === "max") return "HIGH";
  return effort.toUpperCase();
}

function mapFinishReason(reason: string | undefined): CanonicalTurnResult["stopReason"] {
  if (reason === "MAX_TOKENS") return "length";
  if (reason === "SAFETY" || reason === "BLOCKLIST" || reason === "PROHIBITED_CONTENT") return "refusal";
  return "completed";
}
