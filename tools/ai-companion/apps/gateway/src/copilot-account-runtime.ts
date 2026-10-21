import { createHash } from "node:crypto";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import type { CopilotClient as CopilotClientType } from "@github/copilot-sdk";
import type { AccountSecretStore } from "../../../packages/core/src/index.js";
import type { ProviderKind } from "../../../packages/protocol/src/index.js";
import {
  accountStatus,
  conversationPrompt,
  type AccountChatInput,
  type AccountLoginStart,
  type AccountModel,
  type AccountRuntime,
  type AccountStatus,
  type ProviderQuota,
} from "./account-runtime.js";
import { agentInstructions } from "../../../packages/core/src/index.js";
import { isolatedEnv } from "./account-process.js";
import { toMcpToolResult } from "./tool-result-content.js";

export const COPILOT_ACCOUNT_PROVIDER_ID = "00000000-0000-4000-8000-000000001011";
const DEFAULT_TOKEN_STORE_KEY = "github-copilot-oauth";

type DeviceLogin = {
  deviceCode: string;
  verificationUrl: string;
  userCode: string;
  intervalSeconds: number;
  expiresAt: number;
  pending: boolean;
  error?: string;
};

export class CopilotAccountRuntime implements AccountRuntime {
  readonly id = "copilot";
  readonly providerId = COPILOT_ACCOUNT_PROVIDER_ID;
  readonly displayName = "GitHub Copilot";
  readonly kind: ProviderKind = "github-copilot-account";
  readonly #home: string;
  readonly #workspaceRoot: string;
  readonly #executable: string;
  readonly #clientId: string | undefined;
  readonly #secrets: AccountSecretStore;
  readonly #tokenStoreKey: string;
  #login: DeviceLogin | undefined;
  #client: CopilotClientType | undefined;
  #clientFingerprint: string | undefined;

  constructor(options: {
    accountDataDir: string;
    executable: string;
    githubOAuthClientId?: string;
    secrets: AccountSecretStore;
    tokenStoreKey?: string;
  }) {
    this.#home = path.join(options.accountDataDir, "copilot");
    this.#workspaceRoot = path.join(options.accountDataDir, "copilot-workspaces");
    this.#executable = options.executable;
    this.#clientId = options.githubOAuthClientId;
    this.#secrets = options.secrets;
    this.#tokenStoreKey = options.tokenStoreKey ?? DEFAULT_TOKEN_STORE_KEY;
  }

  async status(): Promise<AccountStatus> {
    if (this.#login?.pending) {
      return accountStatus(this, {
        available: true,
        connected: false,
        loginMode: "oauth_app",
        pendingLogin: true,
        policyNote: "GitHub OAuth Device Flow; consumul este atribuit abonamentului Copilot al utilizatorului.",
      });
    }
    const token = this.#secrets.get(this.#tokenStoreKey);
    if (!token) {
      return accountStatus(this, {
        available: true,
        connected: false,
        loginMode: "oauth_app",
        ...(this.#login?.error ? { loginError: this.#login.error } : {}),
        ...(!this.#clientId ? {
          configurationRequired: "Configurează GITHUB_OAUTH_CLIENT_ID pe Railway și activează Device Flow în aplicația GitHub OAuth.",
        } : {}),
        policyNote: "SDK oficial GitHub Copilot. Nu sunt reutilizate tokenuri din alte aplicații.",
      });
    }
    try {
      const client = await this.#getClient(token);
      const auth = await client.getAuthStatus();
      return accountStatus(this, {
        available: true,
        connected: auth.isAuthenticated,
        loginMode: "oauth_app",
        ...(auth.login ? { accountLabel: auth.login } : {}),
        planType: "Copilot",
        ...(!auth.isAuthenticated && auth.statusMessage ? { loginError: auth.statusMessage } : {}),
        policyNote: "SDK oficial GitHub Copilot; cererile folosesc cota contului conectat.",
      });
    } catch (error) {
      return accountStatus(this, {
        available: true,
        connected: false,
        loginMode: "oauth_app",
        loginError: publicError(error),
      });
    }
  }

  async startLogin(): Promise<AccountLoginStart> {
    if (!this.#clientId) {
      throw new Error("Copilot necesită GITHUB_OAUTH_CLIENT_ID configurat pe Railway și Device Flow activat în GitHub OAuth App.");
    }
    const response = await fetch("https://github.com/login/device/code", {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
        "User-Agent": "Godot-Agent/0.13.0",
      },
      body: new URLSearchParams({ client_id: this.#clientId, scope: "read:user" }),
    });
    const value = await response.json() as Record<string, unknown>;
    if (!response.ok || typeof value.device_code !== "string" || typeof value.user_code !== "string") {
      throw new Error("GitHub nu a pornit fluxul OAuth Device Flow. Verifică aplicația OAuth și opțiunea Device Flow.");
    }
    const intervalSeconds = typeof value.interval === "number" ? Math.max(5, value.interval) : 5;
    const expiresIn = typeof value.expires_in === "number" ? value.expires_in : 900;
    const verificationUrl = String(value.verification_uri ?? value.verification_uri_complete ?? "https://github.com/login/device");
    const login: DeviceLogin = {
      deviceCode: value.device_code,
      verificationUrl,
      userCode: value.user_code,
      intervalSeconds,
      expiresAt: Date.now() + expiresIn * 1000,
      pending: true,
    };
    this.#login = login;
    void this.#pollDeviceFlow(login);
    return { verificationUrl, userCode: login.userCode, requiresInput: false, expiresInSeconds: expiresIn };
  }

  async logout(): Promise<void> {
    this.#login && (this.#login.pending = false);
    this.#login = undefined;
    await this.#secrets.delete(this.#tokenStoreKey);
    await this.#stopClient();
  }

  async listModels(): Promise<AccountModel[]> {
    const token = this.#secrets.get(this.#tokenStoreKey);
    if (!token) throw new Error("Contul GitHub Copilot nu este conectat.");
    const client = await this.#getClient(token);
    return (await client.listModels()).map((model, index) => ({
      id: model.id,
      displayName: model.name,
      ...(index === 0 ? { isDefault: true } : {}),
      inputModalities: model.capabilities.supports.vision ? ["text", "image"] : ["text"],
      ...(model.capabilities.supports.reasoningEffort && model.supportedReasoningEfforts?.length
        ? { reasoningEfforts: [...model.supportedReasoningEfforts] }
        : {}),
      ...(model.defaultReasoningEffort ? { defaultReasoningEffort: model.defaultReasoningEffort } : {}),
      ...(model.capabilities.limits.max_context_window_tokens
        ? { contextWindowTokens: model.capabilities.limits.max_context_window_tokens }
        : {}),
    }));
  }

  async quota(): Promise<ProviderQuota> {
    const token = this.#secrets.get(this.#tokenStoreKey);
    if (!token) throw new Error("Conectează mai întâi contul GitHub Copilot din Setări.");
    const client = await this.#getClient(token);
    const result = await client.rpc.account.getQuota({});
    const windows = Object.entries(result.quotaSnapshots).flatMap(([id, snapshot]) => {
      if (!snapshot) return [];
      const remaining = snapshot.isUnlimitedEntitlement ? undefined : Math.max(0, snapshot.entitlementRequests - snapshot.usedRequests);
      const limit = snapshot.isUnlimitedEntitlement ? undefined : snapshot.entitlementRequests;
      return [{
        label: copilotQuotaLabel(id),
        remainingPercent: snapshot.isUnlimitedEntitlement ? 100 : snapshot.remainingPercentage,
        usedPercent: snapshot.isUnlimitedEntitlement ? 0 : Math.max(0, 100 - snapshot.remainingPercentage),
        ...(remaining !== undefined ? { remaining } : {}),
        ...(limit !== undefined ? { limit } : {}),
        unit: "requests" as const,
        unlimited: snapshot.isUnlimitedEntitlement,
        ...(snapshot.resetDate ? { resetAt: snapshot.resetDate } : {}),
      }];
    });
    return {
      available: windows.length > 0,
      source: "live",
      title: "Cotă GitHub Copilot",
      windows,
      checkedAt: new Date().toISOString(),
      note: windows.length
        ? "Cota contului conectat, raportată live de SDK-ul GitHub Copilot."
        : "Contul Copilot nu a publicat momentan valori de cotă.",
    };
  }

  async chat(input: AccountChatInput): Promise<string> {
    const token = this.#secrets.get(this.#tokenStoreKey);
    if (!token) throw new Error("Conectează mai întâi contul GitHub Copilot din Setări.");
    const client = await this.#getClient(token);
    const workspace = path.join(this.#workspaceRoot, safeSegment(input.sessionId));
    await mkdir(workspace, { recursive: true, mode: 0o700 });
    const sdk = await import("@github/copilot-sdk");
    const definitions = input.broker.definitions(input.toolNames);
    const tools = definitions.map((definition) => sdk.defineTool(definition.name, {
      description: definition.description,
      parameters: definition.inputSchema,
      skipPermission: true,
      defer: "auto",
      handler: async (argumentsValue) => {
        const result = await input.broker.execute(definition.name, argumentsValue);
        return sdk.convertMcpCallToolResult(toMcpToolResult(result));
      },
    }));
    const session = await client.createSession({
      clientName: "godot-agent",
      model: input.model,
      ...(input.effort ? { reasoningEffort: normalizeCopilotEffort(input.effort) } : {}),
      workingDirectory: workspace,
      tools,
      availableTools: definitions.map((definition) => `custom:${definition.name}`),
      streaming: true,
      skipCustomInstructions: true,
      customAgentsLocalOnly: true,
      coauthorEnabled: false,
      enableSessionTelemetry: false,
      systemMessage: { mode: "replace", content: agentInstructions({ mode: input.mode, skillInstructions: input.skillInstructions }) },
      onPermissionRequest: () => ({ kind: "reject", feedback: "Godot Agent permits only registered Godot tools." }),
    });
    let output = "";
    const unsubscribe = session.on("assistant.message_delta", (event) => {
      if (event.agentId) return;
      output += event.data.deltaContent;
      void input.onDelta?.(event.data.deltaContent);
    });
    const unsubscribeUsage = session.on("session.usage_info", (event) => {
      if (event.agentId) return;
      void input.onContext?.({
        usedTokens: event.data.currentTokens,
        contextWindowTokens: event.data.tokenLimit,
        estimated: false,
      });
    });
    const onAbort = (): void => { void session.abort(); };
    input.signal?.addEventListener("abort", onAbort, { once: true });
    try {
      if (input.signal?.aborted) {
        await session.abort();
        throw abortError(input.signal.reason);
      }
      const response = await session.sendAndWait({
        prompt: conversationPrompt(input),
        ...(input.attachments?.length ? {
          attachments: input.attachments.map((attachment) => ({
            type: "blob" as const,
            data: attachment.data,
            mimeType: attachment.mimeType,
            displayName: attachment.name,
          })),
        } : {}),
      }, 15 * 60_000);
      if (input.signal?.aborted) throw abortError(input.signal.reason);
      if (!output && response?.data.content) output = response.data.content;
      return output;
    } finally {
      input.signal?.removeEventListener("abort", onAbort);
      unsubscribe();
      unsubscribeUsage();
      await session.disconnect();
    }
  }

  async close(): Promise<void> {
    if (this.#login) this.#login.pending = false;
    await this.#stopClient();
  }

  async #pollDeviceFlow(login: DeviceLogin): Promise<void> {
    if (!this.#clientId) return;
    let interval = login.intervalSeconds;
    while (login.pending && Date.now() < login.expiresAt) {
      await delay(interval * 1000);
      if (!login.pending || this.#login !== login) return;
      try {
        const response = await fetch("https://github.com/login/oauth/access_token", {
          method: "POST",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "Godot-Agent/0.13.0",
          },
          body: new URLSearchParams({
            client_id: this.#clientId,
            device_code: login.deviceCode,
            grant_type: "urn:ietf:params:oauth:grant-type:device_code",
          }),
        });
        const value = await response.json() as Record<string, unknown>;
        if (typeof value.access_token === "string") {
          await this.#secrets.set(this.#tokenStoreKey, value.access_token);
          login.pending = false;
          await this.#stopClient();
          return;
        }
        const error = String(value.error ?? "");
        if (error === "authorization_pending") continue;
        if (error === "slow_down") {
          interval += 5;
          continue;
        }
        login.pending = false;
        login.error = error === "access_denied"
          ? "Autorizarea GitHub a fost refuzată."
          : "Fluxul GitHub a expirat sau nu a putut fi finalizat.";
        return;
      } catch {
        // A transient network failure is retried until the official expiry time.
      }
    }
    if (login.pending) {
      login.pending = false;
      login.error = "Codul GitHub a expirat. Pornește un flux nou.";
    }
  }

  async #getClient(token: string): Promise<CopilotClientType> {
    const fingerprint = createHash("sha256").update(token).digest("hex");
    if (this.#client && this.#clientFingerprint === fingerprint) return this.#client;
    await this.#stopClient();
    await mkdir(this.#home, { recursive: true, mode: 0o700 });
    await mkdir(this.#workspaceRoot, { recursive: true, mode: 0o700 });
    const sdk = await import("@github/copilot-sdk");
    const env = stringEnvironment(isolatedEnv({}, ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"]));
    const client = new sdk.CopilotClient({
      mode: "empty",
      connection: sdk.RuntimeConnection.forStdio({ path: this.#executable, env }),
      baseDirectory: this.#home,
      workingDirectory: this.#workspaceRoot,
      gitHubToken: token,
      useLoggedInUser: false,
      logLevel: "error",
      sessionIdleTimeoutSeconds: 300,
    });
    await client.start();
    this.#client = client;
    this.#clientFingerprint = fingerprint;
    return client;
  }

  async #stopClient(): Promise<void> {
    const client = this.#client;
    this.#client = undefined;
    this.#clientFingerprint = undefined;
    if (!client) return;
    try { await client.stop(); } catch { await client.forceStop(); }
  }
}

function normalizeCopilotEffort(effort: NonNullable<AccountChatInput["effort"]>): "low" | "medium" | "high" | "xhigh" | "max" {
  if (effort === "low" || effort === "medium" || effort === "high" || effort === "xhigh" || effort === "max") return effort;
  return effort === "minimal" || effort === "none" ? "low" : "medium";
}

function abortError(reason: unknown): Error {
  if (reason instanceof Error && reason.name === "AbortError") return reason;
  const error = new Error(reason instanceof Error ? reason.message : "Agent stopped");
  error.name = "AbortError";
  return error;
}

function stringEnvironment(env: NodeJS.ProcessEnv): Record<string, string> {
  return Object.fromEntries(Object.entries(env).filter((entry): entry is [string, string] => typeof entry[1] === "string"));
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120) || "session";
}

function publicError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 400) : "Runtime Copilot indisponibil";
}

function copilotQuotaLabel(id: string): string {
  if (id === "premium_interactions") return "Interacțiuni premium";
  if (id === "chat") return "Chat";
  if (id === "completions") return "Completări";
  return id.replaceAll("_", " ").replace(/^./, (value) => value.toUpperCase());
}
