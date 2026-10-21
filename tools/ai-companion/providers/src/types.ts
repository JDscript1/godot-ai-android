import type {
  CanonicalRequest,
  CanonicalTurnResult,
  ProviderCapabilityProfile,
  ProviderKind,
  ProviderModel,
} from "../../packages/protocol/src/index.js";

export type ProviderConnection = {
  id: string;
  name: string;
  kind: ProviderKind;
  apiKey?: string;
  baseUrl?: string;
  defaultModel?: string;
  models: string[];
  enabled: boolean;
};

export interface ProviderAdapter {
  readonly kind: ProviderKind;
  readonly capabilities: ProviderCapabilityProfile;
  listModels(connection: ProviderConnection): Promise<ProviderModel[]>;
  complete(
    connection: ProviderConnection,
    request: CanonicalRequest,
    signal?: AbortSignal,
  ): Promise<CanonicalTurnResult>;
}

export class ProviderHttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly retryable: boolean,
    readonly body?: unknown,
  ) {
    super(message);
    this.name = "ProviderHttpError";
  }
}

export async function parseProviderResponse(response: Response): Promise<unknown> {
  const text = await response.text();
  let body: unknown = text;
  try {
    body = text.length ? JSON.parse(text) : undefined;
  } catch {
    // Preserve the provider's text error without logging credentials or headers.
  }
  if (!response.ok) {
    throw new ProviderHttpError(
      `Provider request failed with HTTP ${response.status}`,
      response.status,
      response.status === 408 || response.status === 409 || response.status === 429 || response.status >= 500,
      body,
    );
  }
  return body;
}

export function requireApiKey(connection: ProviderConnection): string {
  if (!connection.apiKey) {
    throw new Error(`Provider ${connection.name} does not have an API key`);
  }
  return connection.apiKey;
}

export function textFromCanonical(request: CanonicalRequest, role: "system" | "user"): string {
  return request.messages
    .filter((message) => message.role === role)
    .flatMap((message) => message.content)
    .filter((content): content is { type: "text"; text: string } => content.type === "text")
    .map((content) => content.text)
    .join("\n\n");
}
