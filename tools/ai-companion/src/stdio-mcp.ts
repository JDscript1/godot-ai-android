import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { randomUUID } from "node:crypto";

export type StdioServerConfig = { command: string; args?: string[]; env?: Record<string, string> };

/** Only commands in the owner's local config can be started; HTTP cannot supply executable names. */
export class StdioMcpSession {
  readonly id = randomUUID();
  readonly #child: ChildProcessWithoutNullStreams;
  readonly #pending = new Map<string, { resolve: (value: unknown) => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  #buffer = "";
  #closed = false;

  constructor(config: StdioServerConfig) {
    this.#child = spawn(config.command, config.args ?? [], { shell: false, env: { ...process.env, ...config.env }, stdio: ["pipe", "pipe", "pipe"] });
    this.#child.stdout.setEncoding("utf8");
    this.#child.stdout.on("data", (chunk: string) => this.#consume(chunk));
    this.#child.stderr.resume();
    this.#child.on("error", () => this.close());
    this.#child.on("close", () => this.close());
  }

  async request(message: Record<string, unknown>): Promise<unknown> {
    if (this.#closed) throw new Error("MCP process is closed");
    if (!message.id) {
      this.#child.stdin.write(`${JSON.stringify(message)}\n`);
      return undefined;
    }
    const id = randomUUID();
    const response = new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => { this.#pending.delete(id); reject(new Error("MCP request timed out")); }, 180000);
      this.#pending.set(id, { resolve, reject, timer });
    });
    this.#child.stdin.write(`${JSON.stringify({ ...message, id })}\n`);
    const value = await response as Record<string, unknown>;
    return { ...value, id: message.id };
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.#child.kill("SIGTERM");
    for (const request of this.#pending.values()) {
      clearTimeout(request.timer);
      request.reject(new Error("MCP process ended"));
    }
    this.#pending.clear();
  }

  #consume(chunk: string): void {
    this.#buffer += chunk;
    if (Buffer.byteLength(this.#buffer) > 4 * 1024 * 1024) { this.close(); return; }
    let index: number;
    while ((index = this.#buffer.indexOf("\n")) >= 0) {
      const line = this.#buffer.slice(0, index);
      this.#buffer = this.#buffer.slice(index + 1);
      let message: Record<string, unknown>;
      try { message = JSON.parse(line) as Record<string, unknown>; } catch { continue; }
      const request = this.#pending.get(String(message.id));
      if (!request) {
        // Elicitation/sampling requests need explicit editor support rather than an unanswered wait.
        if (message.method && message.id !== undefined) this.#child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Client capability unavailable" } })}\n`);
        continue;
      }
      clearTimeout(request.timer);
      this.#pending.delete(String(message.id));
      request.resolve(message);
    }
  }
}
