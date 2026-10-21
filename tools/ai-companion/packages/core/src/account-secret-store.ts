import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { decryptString, encryptString, type EncryptedValue } from "./secrets.js";

type StoredSecrets = {
  version: 1;
  secrets: Record<string, EncryptedValue>;
};

/** Small encrypted store for OAuth access tokens managed by the gateway itself. */
export class AccountSecretStore {
  readonly #filePath: string;
  readonly #masterKey: Buffer;
  #secrets: Record<string, EncryptedValue> = {};

  private constructor(filePath: string, masterKey: Buffer) {
    this.#filePath = filePath;
    this.#masterKey = masterKey;
  }

  static async open(dataDir: string, masterKey: Buffer): Promise<AccountSecretStore> {
    const accountDir = path.join(dataDir, "accounts");
    await mkdir(accountDir, { recursive: true, mode: 0o700 });
    const store = new AccountSecretStore(path.join(accountDir, "secrets.json"), masterKey);
    await store.#load();
    return store;
  }

  get(name: string): string | undefined {
    const value = this.#secrets[name];
    return value ? decryptString(value, this.#masterKey) : undefined;
  }

  async set(name: string, secret: string): Promise<void> {
    this.#secrets[name] = encryptString(secret, this.#masterKey);
    await this.#save();
  }

  async delete(name: string): Promise<boolean> {
    if (!this.#secrets[name]) return false;
    delete this.#secrets[name];
    await this.#save();
    return true;
  }

  async #load(): Promise<void> {
    try {
      const parsed = JSON.parse(await readFile(this.#filePath, "utf8")) as Partial<StoredSecrets>;
      this.#secrets = parsed.secrets ?? {};
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  async #save(): Promise<void> {
    const temporary = `${this.#filePath}.${process.pid}.tmp`;
    const value: StoredSecrets = { version: 1, secrets: this.#secrets };
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    await rename(temporary, this.#filePath);
  }
}
