import { mkdir } from "node:fs/promises";
import path from "node:path";
import {
  createSdkMcpServer,
  query,
  tool,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
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
  type QuotaWindow,
} from "./account-runtime.js";
import {
  firstWebUrl,
  InteractiveLoginProcess,
  isolatedEnv,
  runProcess,
} from "./account-process.js";
import { agentInstructions } from "../../../packages/core/src/index.js";
import { toMcpToolResult } from "./tool-result-content.js";

type ClaudeAuthJson = {
  loggedIn?: boolean;
  authMethod?: string;
  apiProvider?: string;
  email?: string;
  orgName?: string;
  subscriptionType?: string | null;
};

export const CLAUDE_ACCOUNT_PROVIDER_ID = "00000000-0000-4000-8000-000000000233";

export class ClaudeAccountRuntime implements AccountRuntime {
  readonly id = "claude";
  readonly providerId = CLAUDE_ACCOUNT_PROVIDER_ID;
  readonly displayName = "Claude";
  readonly kind: ProviderKind = "anthropic-claude-account";
  readonly #configDir: string;
  readonly #workspaceRoot: string;
  readonly #executable: string;
  #login: InteractiveLoginProcess | undefined;

  constructor(options: { accountDataDir: string; executable: string }) {
    this.#configDir = path.join(options.accountDataDir, "claude");
    this.#workspaceRoot = path.join(options.accountDataDir, "claude-workspaces");
    this.#executable = options.executable;
  }

  async status(): Promise<AccountStatus> {
    if (this.#login?.pending) {
      return accountStatus(this, {
        available: true,
        connected: false,
        loginMode: "browser_code",
        pendingLogin: true,
      });
    }
    try {
      await mkdir(this.#configDir, { recursive: true, mode: 0o700 });
      const result = await runProcess(this.#executable, ["auth", "status"], {
        env: this.#env(),
        timeoutMs: 20_000,
      });
      const parsed = parseAuthJson(result.stdout || result.stderr);
      const connected = Boolean(parsed.loggedIn)
        && !["api_key", "apiKey", "console"].includes(parsed.authMethod ?? "")
        && parsed.apiProvider !== "bedrock"
        && parsed.apiProvider !== "vertex"
        && parsed.apiProvider !== "foundry";
      return accountStatus(this, {
        available: true,
        connected,
        loginMode: "browser_code",
        ...(parsed.email || parsed.orgName ? { accountLabel: parsed.email ?? parsed.orgName } : {}),
        ...(parsed.subscriptionType ? { planType: parsed.subscriptionType } : {}),
        ...(this.#login?.error ? { loginError: this.#login.error } : {}),
        policyNote: "Agent SDK oficial; variabilele de cheie Anthropic sunt eliminate din runtime pentru a evita facturarea API accidentală.",
      });
    } catch (error) {
      return accountStatus(this, {
        available: false,
        connected: false,
        loginMode: "browser_code",
        loginError: publicError(error),
      });
    }
  }

  async startLogin(): Promise<AccountLoginStart> {
    this.#login?.cancel();
    await mkdir(this.#configDir, { recursive: true, mode: 0o700 });
    this.#login = await InteractiveLoginProcess.start({
      executable: this.#executable,
      args: ["auth", "login"],
      env: this.#env({ BROWSER: "echo" }),
      parse: (output) => {
        const verificationUrl = firstWebUrl(output);
        return verificationUrl ? { verificationUrl, requiresInput: true } : undefined;
      },
      timeoutMs: 40_000,
    });
    const state = this.#login.state;
    if (!state) throw new Error("Claude nu a returnat pagina de autentificare.");
    return { verificationUrl: state.verificationUrl, requiresInput: true };
  }

  async submitLogin(code: string): Promise<void> {
    const value = code.trim();
    if (value.length < 4 || value.length > 4096) throw new Error("Codul Claude nu este valid.");
    if (!this.#login?.pending) throw new Error("Pornește mai întâi conectarea contului Claude.");
    this.#login.submit(value);
  }

  async logout(): Promise<void> {
    this.#login?.cancel();
    this.#login = undefined;
    const result = await runProcess(this.#executable, ["auth", "logout"], {
      env: this.#env(),
      timeoutMs: 30_000,
    });
    if (result.code !== 0) throw new Error("Claude nu a putut deconecta acest cont.");
  }

  async listModels(): Promise<AccountModel[]> {
    const status = await this.status();
    if (!status.connected) throw new Error("Contul Claude cu abonament nu este conectat.");
    return [
      { id: "sonnet", displayName: "Claude Sonnet", description: "Aliasul stabil Sonnet disponibil contului", isDefault: true, inputModalities: ["text", "image"], reasoningEfforts: ["low", "medium", "high", "max"], defaultReasoningEffort: "high" },
      { id: "opus", displayName: "Claude Opus", description: "Aliasul stabil Opus, dacă planul îl include", inputModalities: ["text", "image"], reasoningEfforts: ["low", "medium", "high", "max"], defaultReasoningEffort: "high" },
      { id: "haiku", displayName: "Claude Haiku", description: "Aliasul stabil Haiku, dacă planul îl include", inputModalities: ["text", "image"] },
    ];
  }

  async quota(): Promise<ProviderQuota> {
    const status = await this.status();
    if (!status.connected) throw new Error("Conectează mai întâi contul Claude din Setări.");
    await mkdir(this.#workspaceRoot, { recursive: true, mode: 0o700 });
    const stream = query({
      prompt: "",
      options: {
        cwd: this.#workspaceRoot,
        env: this.#env({ CLAUDE_AGENT_SDK_CLIENT_APP: "godot-agent/0.13.0" }),
        pathToClaudeCodeExecutable: this.#executable,
        tools: [],
        settingSources: [],
        persistSession: false,
        permissionMode: "dontAsk",
        maxTurns: 1,
      },
    });
    try {
      const usage = await stream.usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET();
      return claudeQuota(usage as unknown as Record<string, unknown>);
    } finally {
      stream.close();
    }
  }

  async chat(input: AccountChatInput): Promise<string> {
    const status = await this.status();
    if (!status.connected) throw new Error("Conectează mai întâi contul Claude din Setări.");
    const workspace = path.join(this.#workspaceRoot, safeSegment(input.sessionId));
    await mkdir(workspace, { recursive: true, mode: 0o700 });
    const definitions = input.broker.runtimeDefinitions(input.toolNames);
    const tools = definitions.map(({ definition, schema }) => {
      const directArguments = schema instanceof z.ZodObject;
      const inputShape: z.ZodRawShape = directArguments
        ? schema.shape
        : { arguments: z.record(z.string(), z.unknown()).default({}) };
      return tool(
        definition.name,
        definition.description,
        inputShape,
        async (toolArguments) => {
          const result = await input.broker.execute(
            definition.name,
            directArguments ? toolArguments : toolArguments.arguments,
          );
          return toMcpToolResult(result);
        },
        { alwaysLoad: true },
      );
    });
    const mcp = createSdkMcpServer({
      name: "godot",
      version: "0.13.0",
      instructions: "Acestea sunt singurele unelte de control ale editorului Godot pentru această sesiune.",
      tools,
      alwaysLoad: true,
    });
    let output = "";
    let resultUsage: Record<string, unknown> = {};
    let resultContextWindow: number | undefined;
    const prompt = buildClaudePrompt(input);
    const stream = query({
      prompt,
      options: {
        cwd: workspace,
        model: input.model || "sonnet",
        env: this.#env({ CLAUDE_AGENT_SDK_CLIENT_APP: "godot-agent/0.13.0" }),
        pathToClaudeCodeExecutable: this.#executable,
        tools: [],
        allowedTools: definitions.map(({ definition }) => `mcp__godot__${definition.name}`),
        mcpServers: { godot: mcp },
        strictMcpConfig: true,
        settingSources: [],
        persistSession: false,
        permissionMode: "dontAsk",
        maxTurns: 40,
        ...(input.effort ? { effort: normalizeClaudeEffort(input.effort) } : {}),
        includePartialMessages: true,
        systemPrompt: agentInstructions({ mode: input.mode, skillInstructions: input.skillInstructions }),
      },
    });
    const onAbort = (): void => { void stream.interrupt(); };
    input.signal?.addEventListener("abort", onAbort, { once: true });
    try {
      if (input.signal?.aborted) {
        await stream.interrupt();
        throw abortError(input.signal.reason);
      }
      for await (const message of stream) {
        if (input.signal?.aborted) throw abortError(input.signal.reason);
        const delta = partialText(message);
        if (delta) {
          output += delta;
          await input.onDelta?.(delta);
        }
        if (message.type === "result") {
          resultUsage = message.usage as unknown as Record<string, unknown>;
          const modelUsage = message.modelUsage as unknown as Record<string, Record<string, unknown>>;
          resultContextWindow = Object.values(modelUsage)
            .map((usage) => finiteNumber(usage.contextWindow))
            .filter((value): value is number => value !== undefined)
            .sort((a, b) => b - a)[0];
          if (message.subtype === "success") {
            if (!output && message.result) output = message.result;
          } else {
            throw new Error(resultError(message));
          }
        }
      }
      try {
        const context = await stream.getContextUsage();
        await input.onContext?.({
          usedTokens: context.totalTokens,
          contextWindowTokens: context.maxTokens,
          estimated: false,
        });
      } catch {
        const usedTokens = claudeUsedTokens(resultUsage);
        if (usedTokens > 0) await input.onContext?.({
          usedTokens,
          ...(resultContextWindow ? { contextWindowTokens: resultContextWindow } : {}),
          estimated: true,
        });
      }
      return output;
    } finally {
      input.signal?.removeEventListener("abort", onAbort);
    }
  }

  close(): void {
    this.#login?.cancel();
  }

  #env(overrides: Record<string, string | undefined> = {}): NodeJS.ProcessEnv {
    return isolatedEnv({
      CLAUDE_CONFIG_DIR: this.#configDir,
      ...overrides,
    }, [
      "ANTHROPIC_API_KEY",
      "CLAUDE_API_KEY",
      "CLAUDE_CODE_OAUTH_TOKEN",
      "CLAUDE_CODE_USE_BEDROCK",
      "CLAUDE_CODE_USE_VERTEX",
      "CLAUDE_CODE_USE_FOUNDRY",
    ]);
  }
}

function claudeQuota(value: Record<string, unknown>): ProviderQuota {
  const limits = value.rate_limits && typeof value.rate_limits === "object"
    ? value.rate_limits as Record<string, unknown>
    : {};
  const windows: QuotaWindow[] = [];
  const labels: Record<string, string> = {
    five_hour: "5 ore",
    seven_day: "7 zile",
    seven_day_oauth_apps: "7 zile · aplicații OAuth",
    seven_day_opus: "7 zile · Opus",
    seven_day_sonnet: "7 zile · Sonnet",
  };
  for (const [key, label] of Object.entries(labels)) addClaudeWindow(windows, label, limits[key]);
  if (Array.isArray(limits.model_scoped)) {
    for (const raw of limits.model_scoped) {
      if (!raw || typeof raw !== "object") continue;
      const model = raw as Record<string, unknown>;
      addClaudeWindow(windows, String(model.display_name ?? "Model"), model);
    }
  }
  const extra = limits.extra_usage && typeof limits.extra_usage === "object"
    ? limits.extra_usage as Record<string, unknown>
    : {};
  const monthlyLimit = finiteNumber(extra.monthly_limit);
  const usedCredits = finiteNumber(extra.used_credits);
  if (extra.is_enabled === true && (monthlyLimit !== undefined || usedCredits !== undefined)) {
    windows.push({
      label: "Utilizare suplimentară",
      ...(monthlyLimit !== undefined ? { limit: monthlyLimit } : {}),
      ...(monthlyLimit !== undefined && usedCredits !== undefined ? { remaining: Math.max(0, monthlyLimit - usedCredits) } : {}),
      unit: "credits",
    });
  }
  const available = value.rate_limits_available === true && windows.length > 0;
  return {
    available,
    source: "live",
    title: `Cotă Claude${typeof value.subscription_type === "string" ? ` · ${value.subscription_type}` : ""}`,
    windows,
    checkedAt: new Date().toISOString(),
    note: available
      ? "Ferestrele abonamentului Claude raportate live de Agent SDK."
      : "Claude nu oferă limite de abonament pentru această sesiune (de exemplu, la utilizarea unei chei API).",
  };
}

function addClaudeWindow(target: QuotaWindow[], label: string, raw: unknown): void {
  if (!raw || typeof raw !== "object") return;
  const value = raw as Record<string, unknown>;
  const usedPercent = finiteNumber(value.utilization);
  if (usedPercent === undefined) return;
  target.push({
    label,
    usedPercent,
    remainingPercent: Math.max(0, Math.min(100, 100 - usedPercent)),
    unit: "percent",
    ...(typeof value.resets_at === "string" ? { resetAt: value.resets_at } : {}),
  });
}

function claudeUsedTokens(usage: Record<string, unknown>): number {
  return ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
    .reduce((sum, key) => sum + (finiteNumber(usage[key]) ?? 0), 0);
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function normalizeClaudeEffort(effort: AccountChatInput["effort"]): "low" | "medium" | "high" | "xhigh" | "max" {
  if (effort === "low" || effort === "medium" || effort === "high" || effort === "xhigh" || effort === "max") return effort;
  return effort === "minimal" || effort === "none" ? "low" : "medium";
}

function abortError(reason: unknown): Error {
  if (reason instanceof Error && reason.name === "AbortError") return reason;
  const error = new Error(reason instanceof Error ? reason.message : "Agent stopped");
  error.name = "AbortError";
  return error;
}

function parseAuthJson(output: string): ClaudeAuthJson {
  try {
    const parsed = JSON.parse(output.trim()) as ClaudeAuthJson;
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    const object = /\{[\s\S]*\}/.exec(output)?.[0];
    if (!object) return {};
    try { return JSON.parse(object) as ClaudeAuthJson; } catch { return {}; }
  }
}

function buildClaudePrompt(input: AccountChatInput): string | AsyncIterable<SDKUserMessage> {
  const text = conversationPrompt(input);
  if (!input.attachments?.length) return text;
  const content: unknown[] = [{ type: "text", text }];
  for (const attachment of input.attachments) {
    if (attachment.mimeType.startsWith("image/")) {
      content.push({
        type: "image",
        source: { type: "base64", media_type: attachment.mimeType, data: attachment.data },
      });
      continue;
    }
    const bytes = Buffer.from(attachment.data, "base64");
    const excerpt = bytes.subarray(0, 512_000).toString("utf8");
    content.push({ type: "text", text: `<fisier nume=${JSON.stringify(attachment.name)} tip=${JSON.stringify(attachment.mimeType)}>\n${excerpt}\n</fisier>` });
  }
  return (async function* (): AsyncIterable<SDKUserMessage> {
    yield {
      type: "user",
      message: { role: "user", content },
      parent_tool_use_id: null,
    } as unknown as SDKUserMessage;
  })();
}

function partialText(message: SDKMessage): string {
  if (message.type !== "stream_event") return "";
  const event = message.event as unknown as { type?: string; delta?: { type?: string; text?: string } };
  return event.type === "content_block_delta" && event.delta?.type === "text_delta"
    ? event.delta.text ?? ""
    : "";
}

function resultError(message: Extract<SDKMessage, { type: "result" }>): string {
  const value = message as unknown as { errors?: string[]; subtype?: string };
  return value.errors?.join("; ") || `Claude a încheiat cererea cu starea ${value.subtype ?? "error"}.`;
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 120) || "session";
}

function publicError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 400) : "Runtime Claude indisponibil";
}
