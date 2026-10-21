import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { Readable, Writable } from "node:stream";
import {
  PROTOCOL_VERSION,
  client,
  methods,
  ndJsonStream,
  type ClientContext,
  type ContentBlock,
} from "@agentclientprotocol/sdk";
import type { ProviderKind } from "../../../packages/protocol/src/index.js";
import {
  accountStatus,
  conversationPrompt,
  type AccountChatInput,
  type AccountLoginStart,
  type AccountModel,
  type AccountRuntime,
  type AccountStatus,
} from "./account-runtime.js";
import { agentInstructions } from "../../../packages/core/src/index.js";
import {
  firstWebUrl,
  InteractiveLoginProcess,
  isolatedEnv,
  runProcess,
} from "./account-process.js";
import { BrokerMcpServer } from "./broker-mcp-server.js";

export const KIMI_ACCOUNT_PROVIDER_ID = "00000000-0000-4000-8000-000000000361";

type KimiProviderConfig = {
  providers?: Record<string, Record<string, unknown>>;
  models?: Record<string, Record<string, unknown>>;
  default_model?: string;
};

export class KimiAccountRuntime implements AccountRuntime {
  readonly id = "kimi";
  readonly providerId = KIMI_ACCOUNT_PROVIDER_ID;
  readonly displayName = "Kimi Code";
  readonly kind: ProviderKind = "kimi-code-account";
  readonly #home: string;
  readonly #workspaceRoot: string;
  readonly #executable: string;
  #login: InteractiveLoginProcess | undefined;

  constructor(options: { accountDataDir: string; executable: string }) {
    this.#home = path.join(options.accountDataDir, "kimi");
    this.#workspaceRoot = path.join(options.accountDataDir, "kimi-workspaces");
    this.#executable = options.executable;
  }

  async status(): Promise<AccountStatus> {
    if (this.#login?.pending) {
      return accountStatus(this, {
        available: true,
        connected: false,
        loginMode: "device_code",
        pendingLogin: true,
      });
    }
    try {
      const config = await this.#providerConfig();
      const connected = hasManagedKimi(config);
      return accountStatus(this, {
        available: true,
        connected,
        loginMode: "device_code",
        ...(connected ? { accountLabel: "Kimi Code OAuth" } : {}),
        ...(connected ? { planType: "membership" } : {}),
        ...(this.#login?.error ? { loginError: this.#login.error } : {}),
        policyNote: "Flux oficial RFC 8628 prin Kimi Code CLI și agent ACP oficial.",
      });
    } catch (error) {
      return accountStatus(this, {
        available: false,
        connected: false,
        loginMode: "device_code",
        loginError: publicError(error),
      });
    }
  }

  async startLogin(): Promise<AccountLoginStart> {
    this.#login?.cancel();
    await mkdir(this.#home, { recursive: true, mode: 0o700 });
    this.#login = await InteractiveLoginProcess.start({
      executable: this.#executable,
      args: ["login"],
      env: this.#env(),
      parse: parseKimiLogin,
      timeoutMs: 30_000,
    });
    const state = this.#login.state;
    if (!state?.userCode) throw new Error("Kimi nu a returnat codul de dispozitiv.");
    return {
      verificationUrl: state.verificationUrl,
      userCode: state.userCode,
      requiresInput: false,
      expiresInSeconds: 900,
    };
  }

  async logout(): Promise<void> {
    this.#login?.cancel();
    this.#login = undefined;
    await this.#withAcp(async (context) => {
      await this.#initialize(context);
      await context.request(methods.agent.logout, {});
    });
  }

  async listModels(): Promise<AccountModel[]> {
    const config = await this.#providerConfig();
    if (!hasManagedKimi(config)) throw new Error("Contul Kimi Code nu este conectat.");
    const models = Object.entries(config.models ?? {})
      .filter(([, model]) => String(model.provider ?? "").includes("managed:kimi-code"))
      .map(([id, model]) => {
        const reasoning = kimiReasoning(model);
        const contextWindowTokens = kimiContextWindow(model);
        return {
          id,
          displayName: String(model.display_name ?? model.name ?? id),
          ...(typeof model.description === "string" ? { description: model.description } : {}),
          ...(id === config.default_model ? { isDefault: true } : {}),
          inputModalities: ["text", "image"],
          ...(reasoning.efforts.length ? { reasoningEfforts: reasoning.efforts } : {}),
          ...(reasoning.defaultEffort ? { defaultReasoningEffort: reasoning.defaultEffort } : {}),
          ...(contextWindowTokens ? { contextWindowTokens } : {}),
        };
      });
    if (models.length > 0) return models;
    return officialKimiModels();
  }

  async chat(input: AccountChatInput): Promise<string> {
    const status = await this.status();
    if (!status.connected) throw new Error("Conectează mai întâi contul Kimi Code din Setări.");
    const workspace = path.join(this.#workspaceRoot, safeSegment(input.sessionId));
    await mkdir(workspace, { recursive: true, mode: 0o700 });
    const mcp = new BrokerMcpServer(input.broker, input.toolNames);
    const endpoint = await mcp.start();
    try {
      return await this.#withAcp(async (context) => {
        await this.#initialize(context);
        await context.request(methods.agent.authenticate, { methodId: "login" });
        const session = await context.buildSession({
          cwd: workspace,
          mcpServers: [{
            type: "http",
            name: "godot",
            url: endpoint.url,
            headers: [{ name: "Authorization", value: endpoint.authorization }],
          }],
        }).start();
        try {
          if (input.model) {
            try {
              await context.request(methods.agent.session.setConfigOption, {
                sessionId: session.sessionId,
                configId: "model",
                value: input.model,
              });
            } catch {
              // The account's default remains valid if a stale model alias disappeared.
            }
          }
          if (input.effort) {
            await context.request(methods.agent.session.setConfigOption, {
              sessionId: session.sessionId,
              configId: "thinking",
              value: normalizeKimiEffort(input.effort),
            });
          }
          const onAbort = (): void => {
            void context.notify(methods.agent.session.cancel, { sessionId: session.sessionId });
          };
          input.signal?.addEventListener("abort", onAbort, { once: true });
          if (input.signal?.aborted) {
            onAbort();
            throw abortError(input.signal.reason);
          }
          const promptPromise = session.prompt(kimiPrompt(input));
          let output = "";
          try {
            while (true) {
              if (input.signal?.aborted) throw abortError(input.signal.reason);
              const message = await session.nextUpdate();
              if (message.kind === "stop") break;
              const update = message.update;
              if (update.sessionUpdate === "agent_message_chunk" && update.content.type === "text") {
                output += update.content.text;
                await input.onDelta?.(update.content.text);
              } else if (update.sessionUpdate === "usage_update") {
                await input.onContext?.({
                  usedTokens: update.used,
                  contextWindowTokens: update.size,
                  estimated: false,
                });
              }
            }
            await promptPromise;
            if (input.signal?.aborted) throw abortError(input.signal.reason);
            return output;
          } finally {
            input.signal?.removeEventListener("abort", onAbort);
          }
        } finally {
          session.dispose();
        }
      });
    } finally {
      await mcp.close();
    }
  }

  close(): void {
    this.#login?.cancel();
  }

  async #providerConfig(): Promise<KimiProviderConfig> {
    await mkdir(this.#home, { recursive: true, mode: 0o700 });
    const result = await runProcess(this.#executable, ["provider", "list", "--json"], {
      env: this.#env(),
      timeoutMs: 30_000,
    });
    if (result.code !== 0) throw new Error("Runtime-ul Kimi Code nu este disponibil.");
    const parsed = JSON.parse(result.stdout) as KimiProviderConfig;
    return parsed && typeof parsed === "object" ? parsed : {};
  }

  async #initialize(context: ClientContext): Promise<void> {
    await context.request(methods.agent.initialize, {
      protocolVersion: PROTOCOL_VERSION,
      clientCapabilities: {
        fs: { readTextFile: false, writeTextFile: false },
        terminal: false,
      },
      clientInfo: { name: "Godot Agent", version: "0.13.0" },
    });
  }

  async #withAcp<T>(operation: (context: ClientContext) => Promise<T>): Promise<T> {
    const child = spawn(this.#executable, ["acp"], {
      env: this.#env(),
      stdio: ["pipe", "pipe", "pipe"],
    });
    child.stderr.resume();
    const stream = ndJsonStream(
      Writable.toWeb(child.stdin) as WritableStream<Uint8Array>,
      Readable.toWeb(child.stdout) as ReadableStream<Uint8Array>,
    );
    const rejectPermissions = client({ name: "godot-agent" })
      .onRequest(methods.client.session.requestPermission, ({ params }) => {
        const rejection = params.options.find((option) => option.kind === "reject_once")
          ?? params.options.find((option) => option.kind === "reject_always");
        return rejection
          ? { outcome: { outcome: "selected" as const, optionId: rejection.optionId } }
          : { outcome: { outcome: "cancelled" as const } };
      });
    try {
      return await rejectPermissions.connectWith(stream, operation);
    } finally {
      stopChild(child);
    }
  }

  #env(): NodeJS.ProcessEnv {
    return isolatedEnv({ KIMI_CODE_HOME: this.#home });
  }
}

function kimiReasoning(model: Record<string, unknown>): {
  efforts: Array<"none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max">;
  defaultEffort?: "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
} {
  const nested = model.think_efforts && typeof model.think_efforts === "object"
    ? model.think_efforts as Record<string, unknown>
    : {};
  const raw = Array.isArray(model.support_efforts)
    ? model.support_efforts
    : Array.isArray(nested.valid_efforts) ? nested.valid_efforts : [];
  const efforts = raw.map(normalizeKimiCapability).filter((value): value is "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max" => Boolean(value));
  const defaultEffort = normalizeKimiCapability(model.default_effort ?? nested.default_effort);
  return {
    efforts: [...new Set(efforts)],
    ...(defaultEffort ? { defaultEffort } : {}),
  };
}

function kimiContextWindow(model: Record<string, unknown>): number | undefined {
  for (const key of ["context_window", "context_length", "max_context_tokens", "maxContextWindowTokens"]) {
    const value = model[key];
    if (typeof value === "number" && Number.isFinite(value) && value > 0) return Math.floor(value);
  }
  return undefined;
}

function normalizeKimiCapability(value: unknown): "none" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max" | undefined {
  const effort = String(value ?? "").toLowerCase();
  if (effort === "off" || effort === "none") return "none";
  if (effort === "minimal" || effort === "low" || effort === "medium" || effort === "high" || effort === "xhigh" || effort === "max") return effort;
  return undefined;
}

function normalizeKimiEffort(effort: NonNullable<AccountChatInput["effort"]>): string {
  if (effort === "none") return "off";
  if (effort === "balanced") return "medium";
  return effort;
}

function abortError(reason: unknown): Error {
  if (reason instanceof Error && reason.name === "AbortError") return reason;
  const error = new Error(reason instanceof Error ? reason.message : "Agent stopped");
  error.name = "AbortError";
  return error;
}

function kimiPrompt(input: AccountChatInput): ContentBlock[] {
  const blocks: ContentBlock[] = [{
    type: "text",
    text: `${agentInstructions({ mode: input.mode, skillInstructions: input.skillInstructions })}\n\n${conversationPrompt(input)}`,
  }];
  for (const attachment of input.attachments ?? []) {
    if (attachment.mimeType.startsWith("image/")) {
      blocks.push({ type: "image", data: attachment.data, mimeType: attachment.mimeType });
      continue;
    }
    const bytes = Buffer.from(attachment.data, "base64");
    if (attachment.mimeType.startsWith("text/") || attachment.mimeType.includes("json") || attachment.mimeType.includes("xml")) {
      blocks.push({
        type: "resource",
        resource: {
          uri: `attachment://${encodeURIComponent(attachment.name)}`,
          mimeType: attachment.mimeType,
          text: bytes.subarray(0, 512_000).toString("utf8"),
        },
      });
    } else {
      blocks.push({
        type: "resource",
        resource: {
          uri: `attachment://${encodeURIComponent(attachment.name)}`,
          mimeType: attachment.mimeType,
          blob: attachment.data,
        },
      });
    }
  }
  return blocks;
}

function parseKimiLogin(output: string) {
  const verificationUrl = firstWebUrl(output);
  const labelled = /(?:user\s*code|cod(?:ul)?|code)\s*[:：]?\s*([A-Z0-9]{4,}(?:-[A-Z0-9]{3,})+)/i.exec(output)?.[1];
  const fallback = /\b([A-Z0-9]{4,}-[A-Z0-9]{3,})\b/.exec(output)?.[1];
  const userCode = labelled ?? fallback;
  return verificationUrl && userCode
    ? { verificationUrl, userCode, requiresInput: false }
    : undefined;
}

function hasManagedKimi(config: KimiProviderConfig): boolean {
  return Object.keys(config.providers ?? {}).some((name) => name.includes("managed:kimi-code"))
    || Object.values(config.models ?? {}).some((model) => String(model.provider ?? "").includes("managed:kimi-code"));
}

function officialKimiModels(): AccountModel[] {
  return [
    { id: "k3", displayName: "Kimi K3", description: "Până la 1M context pentru planurile eligibile", inputModalities: ["text", "image"] },
    { id: "k3-256k", displayName: "Kimi K3 256K", description: "Variantă eficientă pentru lucru curent", inputModalities: ["text", "image"] },
    { id: "kimi-for-coding", displayName: "Kimi K2.7 Code", isDefault: true, inputModalities: ["text", "image"] },
    { id: "kimi-for-coding-highspeed", displayName: "Kimi K2.7 Code HighSpeed", inputModalities: ["text", "image"] },
  ];
}

function stopChild(child: ChildProcessWithoutNullStreams): void {
  if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120) || "session";
}

function publicError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 400) : "Runtime Kimi indisponibil";
}
