import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AddressInfo } from "node:net";
import type { AccountChatInput, AccountRuntime } from "../apps/gateway/src/account-runtime.js";
import { createCompanion } from "../src/server.js";
import { StdioMcpSession } from "../src/stdio-mcp.js";
import { TurnManager } from "../src/turns.js";

const TOKEN = "fixture-pairing-token-only";

class FakeAccount implements AccountRuntime {
  readonly id = "claude";
  readonly providerId = "fixture";
  readonly displayName = "Fixture Claude";
  readonly kind = "anthropic-claude-account" as const;
  tool = "godot_project";
  async status() { return { id: this.id, providerId: this.providerId, displayName: this.displayName, kind: this.kind, available: true, connected: true, loginMode: "browser_code" as const }; }
  async startLogin() { return { verificationUrl: "https://example.test/login", requiresInput: true }; }
  async submitLogin(_code: string) {}
  async logout() {}
  async listModels() { return [{ id: "fixture-model", displayName: "Fixture model" }]; }
  async chat(input: AccountChatInput) {
    await input.onDelta?.("Working ");
    const result = await input.broker.execute(this.tool, {});
    await input.onDelta?.(result.ok ? "complete" : "denied");
    return JSON.stringify(result);
  }
  close() {}
}

const definitions = [
  { name: "godot_project", description: "Inspect", parameters: { type: "object", properties: {}, additionalProperties: false }, risk: "read" },
  { name: "godot_write", description: "Modify", parameters: { type: "object", properties: {}, additionalProperties: false }, risk: "write" },
];
const input = { account: "claude", model: "fixture-model", text: "Inspect", tools: definitions, mode: "agent" };
const pause = () => new Promise(resolve => setTimeout(resolve, 10));

describe("companion HTTP and tool relay", () => {
  let companion: ReturnType<typeof createCompanion>;
  let account: FakeAccount;
  let base: string;
  beforeEach(async () => {
    account = new FakeAccount();
    companion = createCompanion({ token: TOKEN, accounts: [account], toolTimeoutMs: 500 });
    await new Promise<void>(resolve => companion.server.listen(0, "127.0.0.1", resolve));
    base = `http://127.0.0.1:${(companion.server.address() as AddressInfo).port}`;
  });
  afterEach(async () => {
    companion.turns.close();
    await new Promise<void>((resolve, reject) => companion.server.close(error => error ? reject(error) : resolve()));
  });
  async function request(path: string, body?: unknown) {
    return fetch(base + path, { headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" }, ...(body === undefined ? {} : { method: "POST", body: JSON.stringify(body) }) });
  }

  it("requires pairing even for health and rejects browser-origin requests", async () => {
    expect((await fetch(base + "/health")).status).toBe(401);
    expect((await fetch(base + "/health", { headers: { Authorization: `Bearer ${TOKEN}`, Origin: "https://untrusted.test" } })).status).toBe(403);
    expect((await request("/health")).status).toBe(200);
  });

  it("discovers official-runtime status and models through the account contract", async () => {
    const status = await (await request("/v1/accounts")).json();
    expect(status.result[0].connected).toBe(true);
    const models = await (await request("/v1/accounts/claude/models")).json();
    expect(models.result[0].id).toBe("fixture-model");
    expect((await request("/v1/accounts/missing/models")).status).toBe(404);
  });

  it("relays an SDK tool call to the editor and resumes with the real result", async () => {
    const started = await (await request("/v1/turns", input)).json();
    const id = started.result.id;
    await pause();
    const state = await (await request(`/v1/turns/${id}?after=0`)).json();
    const tool = state.result.events.find((event: { kind: string }) => event.kind === "tool");
    expect(tool.name).toBe("godot_project");
    expect((await request(`/v1/turns/${id}/tools/${tool.id}`, { result: { scene: "verified" } })).status).toBe(200);
    await pause();
    const complete = await (await request(`/v1/turns/${id}`)).json();
    expect(complete.result.status).toBe("completed");
    expect(complete.result.text).toContain("verified");
    expect((await request(`/v1/turns/${id}/tools/${tool.id}`, { result: { scene: "verified" } })).status).toBe(200);
  });

  it("enforces analysis mode at the companion boundary", async () => {
    account.tool = "godot_write";
    const started = await (await request("/v1/turns", { ...input, mode: "plan" })).json();
    await pause();
    const state = await (await request(`/v1/turns/${started.result.id}`)).json();
    expect(state.result.status).toBe("completed");
    expect(state.result.text).toContain("MODE_DENIED");
    expect(state.result.events.some((event: { kind: string }) => event.kind === "tool")).toBe(false);
  });

  it("cancels pending tools and does not report the turn completed", async () => {
    const started = await (await request("/v1/turns", input)).json();
    await request(`/v1/turns/${started.result.id}/cancel`, {});
    await pause();
    const state = await (await request(`/v1/turns/${started.result.id}`)).json();
    expect(state.result.status).toBe("cancelled");
  });

  it("rejects invalid schemas without leaving a stuck active turn", () => {
    const manager = new TurnManager(new Map([["claude", account]]));
    expect(() => manager.start({ ...input, tools: [{ ...definitions[0], parameters: { type: "not-a-json-schema-type" } }] })).toThrow();
    const valid = manager.start(input);
    expect(valid.id).toBeTruthy();
    manager.close();
  });
});

it("relays stdio MCP messages without a shell and preserves caller request IDs", async () => {
  const code = `const readline = require('node:readline'); readline.createInterface({input:process.stdin}).on('line', l => { const m=JSON.parse(l); if(m.id) console.log(JSON.stringify({jsonrpc:'2.0',id:m.id,result:{tools:[{name:'fixture'}]}})); });`;
  const session = new StdioMcpSession({ command: process.execPath, args: ["-e", code] });
  try {
    const response = await session.request({ jsonrpc: "2.0", id: "native-request", method: "tools/list", params: {} }) as { id: string; result: { tools: { name: string }[] } };
    expect(response.id).toBe("native-request");
    expect(response.result.tools[0]?.name).toBe("fixture");
    await session.request({ jsonrpc: "2.0", method: "notifications/initialized" });
  } finally { session.close(); }
});

it("runs isolated children while a parent awaits tools, relays attachments and context, and closes children", async () => {
  const parent = new FakeAccount();
  let childInput: AccountChatInput | undefined;
  let closed = false;
  const manager = new TurnManager(new Map([["claude", parent]]), 1000, () => ({
    ...parent, id: parent.id, providerId: parent.providerId, displayName: parent.displayName, kind: parent.kind,
    status: parent.status.bind(parent), startLogin: parent.startLogin.bind(parent), logout: parent.logout.bind(parent), listModels: parent.listModels.bind(parent),
    async chat(value) { childInput = value; await value.onContext?.({ usedTokens: 321, contextWindowTokens: 8192 }); return "child findings"; },
    close() { closed = true; },
  }));
  const main = manager.start(input);
  await pause();
  expect(manager.poll(main.id, 0)?.status).toBe("running");
  const child = manager.start({ ...input, child: true, attachments: [{ name: "frame.png", mimeType: "image/png", data: "aW1hZ2U=" }] });
  await pause();
  expect(childInput?.sessionId).not.toBe(main.id);
  expect(childInput?.attachments?.[0]?.data).toBe("aW1hZ2U=");
  expect(manager.poll(child.id, 0)?.status).toBe("completed");
  expect(manager.poll(child.id, 0)?.events).toEqual([expect.objectContaining({ kind: "usage", usedTokens: 321 })]);
  expect(closed).toBe(true);
  expect(manager.poll(main.id, 0)?.status).toBe("running");
  manager.cancel(main.id);
});

it("rejects oversized images and child sessions without an isolation factory", () => {
  const manager = new TurnManager(new Map([["claude", new FakeAccount()]]));
  expect(() => manager.start({ ...input, child: true })).toThrow("Independent child");
  expect(() => manager.start({ ...input, attachments: [{ name: "bad", mimeType: "text/plain", data: "AAAA" }] })).toThrow();
  manager.close();
});
