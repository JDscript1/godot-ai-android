import { randomUUID } from "node:crypto";
import { z } from "zod";
import { PolicyEngine, ToolBroker } from "../packages/core/src/index.js";
import type { AccountRuntime } from "../apps/gateway/src/account-runtime.js";
import { reasoningEffortSchema } from "../packages/protocol/src/index.js";

const definitionSchema = z.object({
  name: z.string().regex(/^[A-Za-z0-9_-]{1,64}$/),
  description: z.string().max(12000),
  parameters: z.record(z.string(), z.unknown()),
  risk: z.enum(["read", "write", "execute", "external", "destructive"]),
});

export const turnSchema = z.object({
  account: z.enum(["claude", "copilot", "kimi"]),
  model: z.string().min(1).max(200),
  text: z.string().min(1).max(100000),
  history: z.array(z.object({ role: z.enum(["user", "assistant"]), text: z.string().max(100000) })).max(100).default([]),
  instructions: z.string().max(100000).default(""),
  tools: z.array(definitionSchema).max(500),
  mode: z.enum(["plan", "agent"]),
  child: z.boolean().default(false),
  attachments: z.array(z.object({ name: z.string().max(240), mimeType: z.enum(["image/png", "image/jpeg", "image/webp"]), data: z.string().min(1).max(2800000).regex(/^[A-Za-z0-9+/]*={0,2}$/) })).max(4).default([]),
  effort: z.union([reasoningEffortSchema, z.literal("")]).optional(),
});

type Event = { sequence: number; kind: string; [key: string]: unknown };
type PendingTool = { resolve: (value: unknown) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> };
type Turn = {
  id: string;
  account: string;
  child: boolean;
  status: "running" | "completed" | "failed" | "cancelled";
  controller: AbortController;
  events: Event[];
  text: string;
  error: string;
  createdAt: number;
  pending: Map<string, PendingTool>;
  completedTools: Set<string>;
};

export class TurnManager {
  readonly #turns = new Map<string, Turn>();

  constructor(readonly accounts: Map<string, AccountRuntime>, readonly toolTimeoutMs = 300000, readonly createRuntime?: (id: string) => AccountRuntime) {}

  start(raw: unknown): { id: string } {
    const input = turnSchema.parse(raw);
    const parent = this.accounts.get(input.account);
    if (input.child && !this.createRuntime) throw new Error("Independent child sessions unavailable");
    const account = input.child ? this.createRuntime!(input.account) : parent;
    if (!account) throw new Error("Account runtime unavailable");
    this.prune();
    if ([...this.#turns.values()].some(turn => turn.status === "running" && turn.account === input.account && turn.child === input.child)) {
      throw new Error("This account already has an active turn");
    }
    if ([...this.#turns.values()].filter(turn => turn.status === "running").length >= 4) throw new Error("Too many active turns");
    const turn: Turn = { id: randomUUID(), account: input.account, child: input.child, status: "running", controller: new AbortController(), events: [], text: "", error: "", createdAt: Date.now(), pending: new Map(), completedTools: new Set() };
    const policy = new PolicyEngine({ allowProjectWrites: true, allowExecution: true, allowExternalReads: true, allowExternalWrites: true, allowDestructive: true });
    const broker = new ToolBroker(policy, input.mode === "plan" ? ["read"] : undefined);
    for (const definition of input.tools) {
      broker.register({
        name: definition.name,
        description: definition.description,
        risk: definition.risk,
        schema: z.fromJSONSchema(definition.parameters as Parameters<typeof z.fromJSONSchema>[0]),
        execute: async (argumentsValue) => this.#requestTool(turn, definition.name, argumentsValue),
      });
    }
    this.#turns.set(turn.id, turn);
    // SDK runtimes only see the broker. Actual project access and user approvals stay in the APK.
    void account.chat({
      sessionId: turn.id,
      model: input.model,
      mode: input.mode,
      text: input.text,
      history: input.history,
      attachments: input.attachments,
      onContext: usage => { this.#event(turn, { kind: "usage", ...usage }); },
      skillInstructions: input.instructions,
      broker,
      signal: turn.controller.signal,
      ...(input.effort ? { effort: input.effort } : {}),
      onDelta: text => { this.#event(turn, { kind: "delta", text }); },
    }).then(text => {
      if (turn.controller.signal.aborted) return;
      turn.text = text;
      turn.status = "completed";
    }).catch(error => {
      turn.status = turn.controller.signal.aborted ? "cancelled" : "failed";
      turn.error = safeError(error);
    }).finally(() => {
      for (const pending of turn.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error("Turn ended"));
      }
      turn.pending.clear();
      if (input.child) void account.close();
    });
    return { id: turn.id };
  }

  poll(id: string, after: number): Record<string, unknown> | undefined {
    const turn = this.#turns.get(id);
    if (!turn) return undefined;
    return { id, status: turn.status, text: turn.text, error: turn.error, events: turn.events.filter(event => event.sequence > after).slice(0, 100) };
  }

  result(id: string, callId: string, result: unknown): boolean {
    const turn = this.#turns.get(id);
    if (!turn) return false;
    if (turn.completedTools.has(callId)) return true;
    const pending = turn.pending.get(callId);
    if (!pending) return false;
    clearTimeout(pending.timer);
    turn.pending.delete(callId);
    turn.completedTools.add(callId);
    pending.resolve(result);
    return true;
  }

  cancel(id: string): boolean {
    const turn = this.#turns.get(id);
    if (!turn) return false;
    if (turn.status !== "running") return true;
    turn.status = "cancelled";
    turn.controller.abort();
    for (const pending of turn.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("Cancelled"));
    }
    turn.pending.clear();
    return true;
  }

  close(): void { for (const id of this.#turns.keys()) this.cancel(id); }

  prune(): void {
    for (const [id, turn] of this.#turns) {
      if (Date.now() - turn.createdAt > 30 * 60 * 1000) {
        this.cancel(id);
        this.#turns.delete(id);
      }
    }
  }

  #event(turn: Turn, event: Omit<Event, "sequence">): void {
    if (turn.controller.signal.aborted) return;
    if (turn.events.length >= 20000) {
      this.cancel(turn.id);
      throw new Error("Turn event limit exceeded");
    }
    turn.events.push({ ...event, sequence: turn.events.length + 1 } as Event);
  }

  #requestTool(turn: Turn, name: string, args: unknown): Promise<unknown> {
    if (turn.controller.signal.aborted) return Promise.reject(new Error("Cancelled"));
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { turn.pending.delete(id); reject(new Error("Editor tool timed out")); }, this.toolTimeoutMs);
      turn.pending.set(id, { resolve, reject, timer });
      this.#event(turn, { kind: "tool", id, name, arguments: args });
    });
  }
}

export function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Companion request failed";
  return message.replace(/(?:Bearer\s+|sk-[A-Za-z0-9_-]+|gh[opus]_[A-Za-z0-9_-]+)\S*/gi, "[secret]").slice(0, 800);
}
