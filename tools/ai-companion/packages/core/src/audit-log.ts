import { mkdir, appendFile } from "node:fs/promises";
import path from "node:path";

export type AuditEvent = {
  action: string;
  actor: string;
  target?: string;
  outcome: "success" | "failure" | "denied";
  metadata?: Record<string, unknown>;
};

export class AuditLog {
  readonly #filePath: string;

  constructor(dataDir: string) {
    this.#filePath = path.join(dataDir, "audit.jsonl");
  }

  async write(event: AuditEvent): Promise<void> {
    await mkdir(path.dirname(this.#filePath), { recursive: true, mode: 0o700 });
    const entry = {
      timestamp: new Date().toISOString(),
      ...event,
    };
    await appendFile(this.#filePath, `${JSON.stringify(entry)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
  }
}
