import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { AccountSecretStore, loadOrCreateMasterKey } from "../packages/core/src/index.js";
import { ClaudeAccountRuntime } from "../apps/gateway/src/claude-account-runtime.js";
import { CopilotAccountRuntime } from "../apps/gateway/src/copilot-account-runtime.js";
import { KimiAccountRuntime } from "../apps/gateway/src/kimi-account-runtime.js";
import { createCompanion } from "./server.js";
import type { StdioServerConfig } from "./stdio-mcp.js";

const dataDir = path.resolve(process.env.AI_COMPANION_DATA_DIR ?? path.join(os.homedir(), ".config", "godot-ai-companion"));
await mkdir(dataDir, { recursive: true, mode: 0o700 });
const tokenPath = path.join(dataDir, "pairing.token");
let token = process.env.AI_COMPANION_TOKEN?.trim();
if (!token) {
  try { token = (await readFile(tokenPath, "utf8")).trim(); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    token = randomBytes(32).toString("base64url");
    await writeFile(tokenPath, token, { flag: "wx", mode: 0o600 });
  }
}
const masterKey = await loadOrCreateMasterKey(dataDir);
const secrets = await AccountSecretStore.open(dataDir, masterKey);
const accountDataDir = path.join(dataDir, "accounts");
const bin = path.resolve("node_modules", ".bin");
const accounts = [
  new ClaudeAccountRuntime({ accountDataDir, executable: process.env.CLAUDE_BIN ?? path.join(bin, "claude") }),
  new CopilotAccountRuntime({ accountDataDir, executable: process.env.COPILOT_BIN ?? path.join(bin, "copilot"), secrets, ...(process.env.GITHUB_OAUTH_CLIENT_ID ? { githubOAuthClientId: process.env.GITHUB_OAUTH_CLIENT_ID } : {}) }),
  new KimiAccountRuntime({ accountDataDir, executable: process.env.KIMI_BIN ?? path.join(bin, "kimi") }),
];
let mcpServers: Record<string, StdioServerConfig> = {};
try { mcpServers = JSON.parse(await readFile(path.join(dataDir, "mcp-servers.json"), "utf8")) as typeof mcpServers; }
catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
const host = process.env.AI_COMPANION_HOST ?? "127.0.0.1";
const port = Number(process.env.AI_COMPANION_PORT ?? 7341);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid companion port");
const { server } = createCompanion({ token, accounts, mcpServers });
server.listen(port, host, () => {
  console.info(`Godot AI companion listening on ${host}:${port}`);
  console.info(`Pair in Editor Settings > AI Assistant > Accounts. Pairing token file: ${tokenPath}`);
});
const shutdown = () => { server.close(); server.closeIdleConnections(); };
process.once("SIGTERM", shutdown);
process.once("SIGINT", shutdown);
