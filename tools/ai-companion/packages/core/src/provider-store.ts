import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  providerUpsertSchema,
  type ProviderKind,
  type ProviderPublicConfig,
  type ProviderUpsert,
} from "../../protocol/src/index.js";
import {
  decryptString,
  encryptString,
  type EncryptedValue,
} from "./secrets.js";

type StoredProvider = {
  id: string;
  name: string;
  kind: ProviderKind;
  encryptedApiKey?: EncryptedValue;
  keySuffix?: string;
  baseUrl?: string;
  defaultModel?: string;
  models: string[];
  enabled: boolean;
  category?: "cloud" | "local";
  createdAt: string;
  updatedAt: string;
};

export type ResolvedProvider = Omit<StoredProvider, "encryptedApiKey" | "keySuffix"> & {
  apiKey?: string;
};

export class ProviderStore {
  readonly #filePath: string;
  readonly #masterKey: Buffer;
  #providers = new Map<string, StoredProvider>();

  private constructor(filePath: string, masterKey: Buffer) {
    this.#filePath = filePath;
    this.#masterKey = masterKey;
  }

  static async open(dataDir: string, masterKey: Buffer): Promise<ProviderStore> {
    await mkdir(dataDir, { recursive: true, mode: 0o700 });
    const store = new ProviderStore(path.join(dataDir, "providers.json"), masterKey);
    await store.#load();
    return store;
  }

  list(): ProviderPublicConfig[] {
    return [...this.#providers.values()]
      .map((provider) => this.#toPublic(provider))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  async getResolved(id: string): Promise<ResolvedProvider | undefined> {
    const provider = this.#providers.get(id);
    if (!provider) return undefined;
    const resolved: ResolvedProvider = {
      id: provider.id,
      name: provider.name,
      kind: provider.kind,
      models: [...provider.models],
      enabled: provider.enabled,
      category: provider.category ?? "cloud",
      createdAt: provider.createdAt,
      updatedAt: provider.updatedAt,
    };
    if (provider.baseUrl !== undefined) resolved.baseUrl = provider.baseUrl;
    if (provider.defaultModel !== undefined) {
      resolved.defaultModel = provider.defaultModel;
    }
    if (provider.encryptedApiKey) {
      resolved.apiKey = decryptString(provider.encryptedApiKey, this.#masterKey);
    }
    return resolved;
  }

  async upsert(input: ProviderUpsert, id?: string): Promise<ProviderPublicConfig> {
    const parsed = providerUpsertSchema.parse(input);
    const now = new Date().toISOString();
    const existing = id ? this.#providers.get(id) : undefined;
    if (id && !existing) {
      throw new Error(`Provider not found: ${id}`);
    }

    const provider: StoredProvider = {
      id: existing?.id ?? randomUUID(),
      name: parsed.name,
      kind: parsed.kind,
      models: [...parsed.models],
      enabled: parsed.enabled,
      category: parsed.category ?? existing?.category ?? "cloud",
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    if (parsed.baseUrl !== undefined) provider.baseUrl = parsed.baseUrl;
    if (parsed.defaultModel !== undefined) {
      provider.defaultModel = parsed.defaultModel;
    }
    if (parsed.apiKey !== undefined && parsed.apiKey.length > 0) {
      provider.encryptedApiKey = encryptString(parsed.apiKey, this.#masterKey);
      provider.keySuffix = parsed.apiKey.slice(-4);
    } else if (existing?.encryptedApiKey) {
      provider.encryptedApiKey = existing.encryptedApiKey;
      if (existing.keySuffix !== undefined) provider.keySuffix = existing.keySuffix;
    }

    this.#providers.set(provider.id, provider);
    await this.#save();
    return this.#toPublic(provider);
  }

  async delete(id: string): Promise<boolean> {
    const deleted = this.#providers.delete(id);
    if (deleted) await this.#save();
    return deleted;
  }

  async #load(): Promise<void> {
    try {
      const raw = JSON.parse(await readFile(this.#filePath, "utf8")) as {
        providers?: StoredProvider[];
      };
      for (const provider of raw.providers ?? []) {
        this.#providers.set(provider.id, provider);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  async #save(): Promise<void> {
    const temporary = `${this.#filePath}.${process.pid}.tmp`;
    await writeFile(
      temporary,
      `${JSON.stringify({ version: 1, providers: [...this.#providers.values()] }, null, 2)}\n`,
      { encoding: "utf8", mode: 0o600 },
    );
    await rename(temporary, this.#filePath);
  }

  #toPublic(provider: StoredProvider): ProviderPublicConfig {
    const publicProvider: ProviderPublicConfig = {
      id: provider.id,
      name: provider.name,
      kind: provider.kind,
      models: [...provider.models],
      enabled: provider.enabled,
      category: provider.category ?? "cloud",
      hasApiKey: Boolean(provider.encryptedApiKey),
      createdAt: provider.createdAt,
      updatedAt: provider.updatedAt,
    };
    if (provider.baseUrl !== undefined) publicProvider.baseUrl = provider.baseUrl;
    if (provider.defaultModel !== undefined) {
      publicProvider.defaultModel = provider.defaultModel;
    }
    if (provider.encryptedApiKey) {
      publicProvider.maskedApiKey = `••••••••••••${provider.keySuffix ?? ""}`;
    }
    return publicProvider;
  }
}
