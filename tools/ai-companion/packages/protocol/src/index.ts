import { z } from "zod";

export const PROTOCOL_VERSION = "1.0.0";

export const providerKindSchema = z.enum([
  "openai-codex-account",
  "anthropic-claude-account",
  "github-copilot-account",
  "kimi-code-account",
  "openai",
  "gemini",
  "anthropic",
  "deepseek",
  "openai-compatible",
  "llama-cpp",
  "ollama",
]);
export type ProviderKind = z.infer<typeof providerKindSchema>;

export const reasoningEffortSchema = z.enum([
  "none",
  "minimal",
  "low",
  "medium",
  "balanced",
  "high",
  "xhigh",
  "max",
]);
export type ReasoningEffort = z.infer<typeof reasoningEffortSchema>;

export const modelReasoningCapabilitySchema = z.object({
  efforts: z.array(reasoningEffortSchema).max(8),
  defaultEffort: reasoningEffortSchema.optional(),
  contextWindowTokens: z.number().int().positive().max(100_000_000).optional(),
});
export type ModelReasoningCapability = z.infer<typeof modelReasoningCapabilitySchema>;

export const providerUpsertSchema = z.object({
  name: z.string().trim().min(1).max(80),
  kind: providerKindSchema,
  apiKey: z.string().max(4096).optional(),
  baseUrl: z.url().optional(),
  defaultModel: z.string().trim().max(160).optional(),
  models: z.array(z.string().trim().min(1).max(160)).max(200).default([]),
  enabled: z.boolean().default(true),
  category: z.enum(["cloud", "local"]).optional(),
});
export type ProviderUpsert = z.infer<typeof providerUpsertSchema>;

export const providerPublicConfigSchema = providerUpsertSchema
  .omit({ apiKey: true })
  .extend({
    id: z.string().uuid(),
    hasApiKey: z.boolean(),
    maskedApiKey: z.string().optional(),
    modelCapabilities: z.record(z.string(), modelReasoningCapabilitySchema).optional(),
    createdAt: z.string(),
    updatedAt: z.string(),
  });
export type ProviderPublicConfig = z.infer<typeof providerPublicConfigSchema>;

export const providerDetectSchema = z.object({
  apiKey: z.string().trim().min(8).max(4096).optional(),
  baseUrl: z.url().optional(),
  providerHint: z.string().trim().regex(/^[a-z0-9-]{1,80}$/).optional(),
  providerId: z.string().uuid().optional(),
}).refine((value) => Boolean(value.apiKey || value.providerId), {
  message: "An API key is required when adding a provider",
});
export type ProviderDetect = z.infer<typeof providerDetectSchema>;

export type ProviderCapabilityProfile = {
  text: boolean;
  vision: boolean;
  streaming: boolean;
  nativeTools: boolean;
  strictTools: boolean;
  parallelTools: boolean;
  structuredOutput: boolean;
  nativeWebSearch: boolean;
  promptCaching: boolean;
  maxContextTokens?: number;
};

export type CanonicalContent =
  | { type: "text"; text: string }
  | { type: "image"; mimeType: string; data?: string; url?: string }
  | { type: "file"; name: string; mimeType: string; data?: string; url?: string }
  | { type: "json"; value: unknown };

export type CanonicalMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content: CanonicalContent[];
  toolCallId?: string;
  toolName?: string;
  toolCalls?: CanonicalToolCall[];
};

export type CanonicalToolDefinition = {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  risk: "read" | "write" | "execute" | "external" | "destructive";
};

export type CanonicalRequest = {
  model: string;
  messages: CanonicalMessage[];
  tools: CanonicalToolDefinition[];
  effort?: ReasoningEffort;
  maxOutputTokens?: number;
  providerState?: Record<string, unknown> | undefined;
};

export type CanonicalToolCall = {
  id: string;
  name: string;
  arguments: unknown;
  providerData?: Record<string, unknown>;
};

export type CanonicalTurnResult = {
  text: string;
  toolCalls: CanonicalToolCall[];
  providerState?: Record<string, unknown> | undefined;
  stopReason: "completed" | "tool_calls" | "length" | "refusal" | "error";
  usage?: {
    inputTokens?: number | undefined;
    outputTokens?: number | undefined;
    cachedTokens?: number | undefined;
  } | undefined;
};

export type ProviderModel = {
  id: string;
  displayName?: string;
  capabilities?: Partial<ProviderCapabilityProfile>;
  reasoningEfforts?: ReasoningEffort[];
  defaultReasoningEffort?: ReasoningEffort;
};

export type BridgeHello = {
  type: "bridge.hello";
  protocolVersion: string;
  deviceId: string;
  projectId: string;
  projectName: string;
  engineVersion: string;
  engineMajor: number;
  platform: string;
  capabilities: string[];
  token?: string | undefined;
};

export type BridgeCommandRequest = {
  type: "command.request";
  requestId: string;
  tool: string;
  arguments: unknown;
};

export type BridgeCommandResult = {
  type: "command.result";
  requestId: string;
  ok: boolean;
  result?: unknown;
  error?: { code: string; message: string; details?: unknown } | undefined;
};

export type ChatSend = {
  type: "chat.send";
  requestId: string;
  providerId: string;
  model: string;
  mode?: "agent" | "plan" | undefined;
  effort?: ReasoningEffort | undefined;
  text: string;
  attachments?: Array<{
    name: string;
    mimeType: string;
    data: string;
  }> | undefined;
  history?: Array<{
    role: "user" | "assistant";
    text: string;
  }> | undefined;
};

export type ChatCancel = {
  type: "chat.cancel";
  requestId: string;
};

export type ChatStatus = "thinking" | "tool" | "responding" | "completed" | "stopped" | "error";

export type ChatContext = {
  usedTokens: number;
  contextWindowTokens?: number;
  remainingTokens?: number;
  remainingPercent?: number;
  estimated: boolean;
  updatedAt: string;
};

export type ConsoleEvent = {
  type: "console.event";
  level: "debug" | "info" | "warning" | "error";
  message: string;
  timestamp: string;
  source?: string | undefined;
};

export type ClientBridgeMessage =
  | BridgeHello
  | BridgeCommandResult
  | ChatSend
  | ChatCancel
  | ConsoleEvent
  | { type: "bridge.ping"; timestamp: number };

export type ServerBridgeMessage =
  | { type: "bridge.hello.ack"; protocolVersion: string; sessionId: string }
  | BridgeCommandRequest
  | { type: "bridge.pong"; timestamp: number }
  | { type: "chat.delta"; requestId: string; text: string }
  | { type: "chat.status"; requestId: string; status: ChatStatus; detail?: string }
  | { type: "chat.context"; requestId: string; context: ChatContext }
  | { type: "chat.completed"; requestId: string; text: string }
  | { type: "chat.stopped"; requestId: string }
  | { type: "chat.error"; requestId: string; message: string }
  | { type: "providers.updated" };

export type ConnectedGodotSession = {
  sessionId: string;
  deviceId: string;
  projectId: string;
  projectName: string;
  engineVersion: string;
  engineMajor: number;
  platform: string;
  capabilities: string[];
  connectedAt: string;
};

const bridgeHelloSchema = z.object({
  type: z.literal("bridge.hello"),
  protocolVersion: z.string().min(1).max(40),
  deviceId: z.string().min(1).max(200),
  projectId: z.string().min(1).max(200),
  projectName: z.string().min(1).max(300),
  engineVersion: z.string().min(1).max(100),
  engineMajor: z.number().int().min(3).max(99),
  platform: z.string().min(1).max(100),
  capabilities: z.array(z.string().min(1).max(100)).max(200),
  token: z.string().min(1).max(4096).optional(),
});

const bridgeCommandResultSchema = z.object({
  type: z.literal("command.result"),
  requestId: z.string().min(1).max(200),
  ok: z.boolean(),
  result: z.unknown().optional(),
  error: z.object({
    code: z.string().min(1).max(100),
    message: z.string().min(1).max(4000),
    details: z.unknown().optional(),
  }).optional(),
});

const chatSendSchema = z.object({
  type: z.literal("chat.send"),
  requestId: z.string().min(1).max(200),
  providerId: z.string().uuid(),
  model: z.string().trim().min(1).max(200),
  mode: z.enum(["agent", "plan"]).default("agent"),
  effort: reasoningEffortSchema.optional(),
  text: z.string().trim().min(1).max(200_000),
  attachments: z.array(z.object({
    name: z.string().min(1).max(300),
    mimeType: z.string().min(1).max(200),
    data: z.string().max(12_000_000),
  })).max(10).optional(),
  history: z.array(z.object({
    role: z.enum(["user", "assistant"]),
    text: z.string().trim().min(1).max(200_000),
  })).max(40).optional(),
});

const chatCancelSchema = z.object({
  type: z.literal("chat.cancel"),
  requestId: z.string().min(1).max(200),
});

const consoleEventSchema = z.object({
  type: z.literal("console.event"),
  level: z.enum(["debug", "info", "warning", "error"]),
  message: z.string().max(20_000),
  timestamp: z.string().max(100),
  source: z.string().max(200).optional(),
});

export const clientBridgeMessageSchema = z.discriminatedUnion("type", [
  bridgeHelloSchema,
  bridgeCommandResultSchema,
  chatSendSchema,
  chatCancelSchema,
  consoleEventSchema,
  z.object({ type: z.literal("bridge.ping"), timestamp: z.number() }),
]);

export const skillStatusSchema = z.enum([
  "draft",
  "validated",
  "promoted",
  "quarantined",
  "disabled",
]);
export type SkillStatus = z.infer<typeof skillStatusSchema>;

export type SkillSummary = {
  id: string;
  name: string;
  description: string;
  status: SkillStatus;
  scope: "builtin" | "user" | "project";
  version: number;
  enabled: boolean;
  updatedAt: string;
};
