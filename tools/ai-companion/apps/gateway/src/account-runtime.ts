import { compactConversationHistory, type ToolBroker } from "../../../packages/core/src/index.js";
import type { ProviderKind, ReasoningEffort } from "../../../packages/protocol/src/index.js";

export type AccountModel = {
  id: string;
  displayName: string;
  description?: string;
  isDefault?: boolean;
  inputModalities?: string[];
  reasoningEfforts?: ReasoningEffort[];
  defaultReasoningEffort?: ReasoningEffort;
  contextWindowTokens?: number;
};

export type AccountContextUsage = {
  usedTokens: number;
  contextWindowTokens?: number;
  estimated?: boolean;
};

export type QuotaWindow = {
  label: string;
  remainingPercent?: number;
  usedPercent?: number;
  remaining?: number;
  limit?: number;
  unit?: "requests" | "tokens" | "credits" | "percent";
  resetAt?: string;
  unlimited?: boolean;
};

export type ProviderQuota = {
  available: boolean;
  source: "live" | "last_response" | "unavailable";
  title: string;
  windows: QuotaWindow[];
  checkedAt: string;
  note?: string;
};

export type AccountStatus = {
  id: string;
  providerId: string;
  displayName: string;
  kind: ProviderKind;
  available: boolean;
  connected: boolean;
  loginMode: "device_code" | "browser_code" | "oauth_app";
  accountLabel?: string;
  planType?: string;
  pendingLogin?: boolean;
  loginError?: string;
  configurationRequired?: string;
  policyNote?: string;
  family?: "openai" | "claude" | "copilot" | "kimi";
  profileLabel?: string;
  isDefaultProfile?: boolean;
  canRemove?: boolean;
};

export type AccountLoginStart = {
  verificationUrl: string;
  userCode?: string;
  requiresInput?: boolean;
  expiresInSeconds?: number;
};

export type AccountChatAttachment = {
  name: string;
  mimeType: string;
  data: string;
};

export type AccountChatInput = {
  sessionId: string;
  model: string;
  mode?: "agent" | "plan";
  text: string;
  history?: Array<{ role: "user" | "assistant"; text: string }>;
  attachments?: AccountChatAttachment[];
  effort?: ReasoningEffort;
  skillInstructions?: string;
  toolNames?: string[];
  broker: ToolBroker;
  signal?: AbortSignal;
  onDelta?: (text: string) => void | Promise<void>;
  onContext?: (usage: AccountContextUsage) => void | Promise<void>;
};

export interface AccountRuntime {
  readonly id: string;
  readonly providerId: string;
  readonly displayName: string;
  readonly kind: ProviderKind;
  status(): Promise<AccountStatus>;
  startLogin(): Promise<AccountLoginStart>;
  submitLogin?(code: string): Promise<void>;
  logout(): Promise<void>;
  listModels(): Promise<AccountModel[]>;
  chat(input: AccountChatInput): Promise<string>;
  quota?(): Promise<ProviderQuota>;
  close(): void | Promise<void>;
}

export function accountStatus(runtime: AccountRuntime, value: Omit<AccountStatus, "id" | "providerId" | "displayName" | "kind">): AccountStatus {
  return {
    id: runtime.id,
    providerId: runtime.providerId,
    displayName: runtime.displayName,
    kind: runtime.kind,
    ...value,
  };
}

export function conversationPrompt(input: Pick<AccountChatInput, "text" | "history">): string {
  const history = compactConversationHistory(input.history);
  if (history.length === 0) return input.text;
  const transcript = history
    .map((message) => `${message.role === "user" ? "UTILIZATOR" : "AGENT"}: ${message.text}`)
    .join("\n\n");
  return `Contextul conversației anterioare:\n\n${transcript}\n\nCEREREA CURENTĂ A UTILIZATORULUI:\n${input.text}`;
}
