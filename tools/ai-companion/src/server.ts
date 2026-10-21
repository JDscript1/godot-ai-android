import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { timingSafeEqual } from "node:crypto";
import type { AccountRuntime } from "../apps/gateway/src/account-runtime.js";
import { StdioMcpSession, type StdioServerConfig } from "./stdio-mcp.js";
import { TurnManager, safeError } from "./turns.js";

type Options = { token: string; accounts: AccountRuntime[]; mcpServers?: Record<string, StdioServerConfig>; toolTimeoutMs?: number };

export function createCompanion(options: Options) {
  if (options.token.length < 16) throw new Error("A pairing token of at least 16 characters is required");
  const accounts = new Map(options.accounts.map(account => [account.id, account]));
  const turns = new TurnManager(accounts, options.toolTimeoutMs);
  const mcp = new Map<string, StdioMcpSession>();
  const server = createServer(async (request, response) => {
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    if (request.headers.origin) { reply(response, 403, { error: "Browser origins are not accepted" }); return; }
    if (!authorized(request, options.token)) { reply(response, 401, { error: "Pairing required" }); return; }
    const url = new URL(request.url ?? "/", "http://companion.invalid");
    const parts = url.pathname.split("/").filter(Boolean);
    try {
      if (url.pathname === "/health") { reply(response, 200, { ok: true, version: "0.1.0" }); return; }
      if (url.pathname === "/v1/accounts" && request.method === "GET") {
        reply(response, 200, { ok: true, result: await Promise.all([...accounts.values()].map(account => account.status())) }); return;
      }
      if (parts[0] === "v1" && parts[1] === "accounts" && parts[2]) {
        const account = accounts.get(parts[2]);
        if (!account) { reply(response, 404, { error: "Unknown account" }); return; }
        if (parts[3] === "models" && request.method === "GET") { reply(response, 200, { ok: true, result: await account.listModels() }); return; }
        if (parts[3] === "login" && request.method === "POST") {
          if (parts[4] === "code") {
            const body = await readBody(request);
            if (!account.submitLogin || typeof body.code !== "string" || body.code.length > 8192) throw new Error("Invalid login code");
            await account.submitLogin(body.code);
            reply(response, 200, { ok: true });
          } else reply(response, 200, { ok: true, result: await account.startLogin() });
          return;
        }
        if (parts[3] === "logout" && request.method === "POST") { await account.logout(); reply(response, 200, { ok: true }); return; }
      }
      if (url.pathname === "/v1/turns" && request.method === "POST") { reply(response, 202, { ok: true, result: turns.start(await readBody(request)) }); return; }
      if (parts[0] === "v1" && parts[1] === "turns" && parts[2]) {
        if (parts.length === 3 && request.method === "GET") {
          const after = Number(url.searchParams.get("after") ?? 0);
          if (!Number.isSafeInteger(after) || after < 0) throw new Error("Invalid event cursor");
          const result = turns.poll(parts[2], after);
          reply(response, result ? 200 : 404, result ? { ok: true, result } : { error: "Unknown turn" }); return;
        }
        if (parts[3] === "tools" && parts[4] && request.method === "POST") {
          const body = await readBody(request);
          const accepted = turns.result(parts[2], parts[4], body.result);
          reply(response, accepted ? 200 : 404, { ok: accepted }); return;
        }
        if (parts[3] === "cancel" && request.method === "POST") { reply(response, turns.cancel(parts[2]) ? 200 : 404, { ok: true }); return; }
      }
      if (parts[0] === "mcp" && parts[1] && parts.length === 2) {
        const configured = options.mcpServers?.[parts[1]];
        if (!configured) { reply(response, 404, { error: "MCP server not configured" }); return; }
        if (request.method === "GET") { response.setHeader("Allow", "POST"); reply(response, 405, { error: "SSE listening not provided" }); return; }
        if (request.method !== "POST") { reply(response, 405, { error: "POST required" }); return; }
        let session = mcp.get(parts[1]);
        const message = await readBody(request);
        if (!session || message.method === "initialize") {
          session?.close();
          session = new StdioMcpSession(configured);
          mcp.set(parts[1], session);
        }
        const expected = request.headers["mcp-session-id"];
        if (expected && expected !== session.id) { reply(response, 404, { error: "MCP session expired" }); return; }
        response.setHeader("Mcp-Session-Id", session.id);
        const result = await session.request(message);
        if (result === undefined) { response.writeHead(202).end(); return; }
        reply(response, 200, result); return;
      }
      reply(response, 404, { error: "Unknown endpoint" });
    } catch (error) { reply(response, 400, { ok: false, error: safeError(error) }); }
  });
  const cleanup = setInterval(() => turns.prune(), 60000);
  cleanup.unref();
  server.on("close", () => {
    clearInterval(cleanup);
    turns.close();
    for (const session of mcp.values()) session.close();
    for (const account of accounts.values()) void account.close();
  });
  return { server, turns };
}

function authorized(request: IncomingMessage, token: string): boolean {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ")) return false;
  const actual = Buffer.from(header.slice(7));
  const expected = Buffer.from(token);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function readBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    size += (chunk as Buffer).length;
    if (size > 4 * 1024 * 1024) throw new Error("Request body too large");
    chunks.push(Buffer.from(chunk as Uint8Array));
  }
  const value: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("JSON object required");
  return value as Record<string, unknown>;
}

function reply(response: ServerResponse, status: number, value: unknown): void {
  if (response.writableEnded) return;
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  response.end(`${JSON.stringify(value)}\n`);
}
