import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

type ProcessResult = {
  code: number;
  stdout: string;
  stderr: string;
};

const MAX_CAPTURE_BYTES = 8 * 1024 * 1024;

export function isolatedEnv(overrides: Record<string, string | undefined>, remove: string[] = []): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env, ...overrides };
  for (const name of remove) delete env[name];
  return env;
}

export async function runProcess(
  executable: string,
  args: string[],
  options: { env?: NodeJS.ProcessEnv; cwd?: string; timeoutMs?: number } = {},
): Promise<ProcessResult> {
  return new Promise<ProcessResult>((resolve, reject) => {
    const child = spawn(executable, args, {
      env: options.env,
      cwd: options.cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      finish(new Error(`Process timed out: ${args[0] ?? "command"}`));
    }, options.timeoutMs ?? 30_000);
    const append = (current: string, chunk: Buffer): string => {
      if (Buffer.byteLength(current) >= MAX_CAPTURE_BYTES) return current;
      return current + chunk.toString("utf8", 0, Math.max(0, MAX_CAPTURE_BYTES - Buffer.byteLength(current)));
    };
    child.stdout.on("data", (chunk: Buffer) => { stdout = append(stdout, chunk); });
    child.stderr.on("data", (chunk: Buffer) => { stderr = append(stderr, chunk); });
    child.once("error", (error) => finish(error));
    child.once("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve({ code: code ?? 1, stdout, stderr });
    });
    function finish(error: Error): void {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    }
  });
}

export type InteractiveLoginState = {
  verificationUrl: string;
  userCode?: string;
  requiresInput: boolean;
};

export class InteractiveLoginProcess {
  readonly #child: ChildProcessWithoutNullStreams;
  readonly #parse: (output: string) => InteractiveLoginState | undefined;
  #output = "";
  #state: InteractiveLoginState | undefined;
  #completed = false;
  #succeeded = false;
  #error: string | undefined;
  #waiters = new Set<() => void>();

  private constructor(child: ChildProcessWithoutNullStreams, parse: (output: string) => InteractiveLoginState | undefined) {
    this.#child = child;
    this.#parse = parse;
    const onData = (chunk: Buffer): void => {
      if (Buffer.byteLength(this.#output) < 128 * 1024) this.#output += chunk.toString("utf8");
      this.#state ??= this.#parse(stripTerminalControls(this.#output));
      this.#notify();
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.once("error", () => {
      this.#completed = true;
      this.#error = "Runtime-ul de autentificare nu a putut fi pornit.";
      this.#notify();
    });
    child.once("close", (code) => {
      this.#completed = true;
      this.#succeeded = code === 0;
      if (!this.#succeeded) this.#error = "Autentificarea nu s-a finalizat. Pornește un flux nou și încearcă din nou.";
      this.#notify();
    });
  }

  static async start(options: {
    executable: string;
    args: string[];
    env?: NodeJS.ProcessEnv;
    cwd?: string;
    parse: (output: string) => InteractiveLoginState | undefined;
    timeoutMs?: number;
  }): Promise<InteractiveLoginProcess> {
    const child = spawn(options.executable, options.args, {
      env: options.env,
      cwd: options.cwd,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const login = new InteractiveLoginProcess(child, options.parse);
    await login.#waitForState(options.timeoutMs ?? 30_000);
    return login;
  }

  get state(): InteractiveLoginState | undefined { return this.#state; }
  get pending(): boolean { return !this.#completed; }
  get succeeded(): boolean { return this.#succeeded; }
  get error(): string | undefined { return this.#error; }

  submit(value: string): void {
    if (this.#completed) throw new Error("Fluxul de autentificare nu mai este activ.");
    this.#child.stdin.write(`${value}\n`);
  }

  cancel(): void {
    if (!this.#completed) this.#child.kill("SIGTERM");
  }

  async #waitForState(timeoutMs: number): Promise<void> {
    const started = Date.now();
    while (!this.#state && !this.#completed) {
      const remaining = timeoutMs - (Date.now() - started);
      if (remaining <= 0) {
        this.cancel();
        throw new Error("Pagina de autentificare nu a fost returnată la timp.");
      }
      await new Promise<void>((resolve) => {
        const timeout = setTimeout(() => {
          this.#waiters.delete(done);
          resolve();
        }, Math.min(remaining, 1000));
        const done = (): void => {
          clearTimeout(timeout);
          this.#waiters.delete(done);
          resolve();
        };
        this.#waiters.add(done);
      });
    }
    if (!this.#state) throw new Error(this.#error ?? "Runtime-ul nu a returnat pagina de autentificare.");
  }

  #notify(): void {
    for (const waiter of this.#waiters) waiter();
  }
}

export function stripTerminalControls(value: string): string {
  return value
    .replace(/\u001B\][^\u0007]*(?:\u0007|\u001B\\)/g, "")
    .replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "");
}

export function firstWebUrl(output: string): string | undefined {
  const match = /https:\/\/[^\s<>"']+/i.exec(output);
  return match?.[0].replace(/[),.;]+$/, "");
}
