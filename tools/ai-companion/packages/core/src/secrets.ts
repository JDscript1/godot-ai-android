import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from "node:crypto";
import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

export type EncryptedValue = {
  version: 1;
  iv: string;
  authTag: string;
  ciphertext: string;
};

export async function loadOrCreateMasterKey(dataDir: string): Promise<Buffer> {
  const configured = process.env.SECRET_ENCRYPTION_KEY?.trim();
  if (configured) {
    const key = Buffer.from(configured, "base64");
    if (key.length !== 32) {
      throw new Error("SECRET_ENCRYPTION_KEY must decode to exactly 32 bytes");
    }
    return key;
  }

  await mkdir(dataDir, { recursive: true, mode: 0o700 });
  const keyPath = path.join(dataDir, "master.key");
  try {
    const key = await readFile(keyPath);
    if (key.length !== 32) {
      throw new Error("Local master key has an invalid length");
    }
    return key;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      throw error;
    }
  }

  const key = randomBytes(32);
  await writeFile(keyPath, key, { mode: 0o600, flag: "wx" });
  await chmod(keyPath, 0o600);
  return key;
}

export function encryptString(value: string, key: Buffer): EncryptedValue {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(value, "utf8"),
    cipher.final(),
  ]);
  return {
    version: 1,
    iv: iv.toString("base64"),
    authTag: cipher.getAuthTag().toString("base64"),
    ciphertext: ciphertext.toString("base64"),
  };
}

export function decryptString(value: EncryptedValue, key: Buffer): string {
  if (value.version !== 1) {
    throw new Error(`Unsupported encrypted value version: ${value.version}`);
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(value.iv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(value.authTag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(value.ciphertext, "base64")),
    decipher.final(),
  ]).toString("utf8");
}

export function maskSecret(value: string): string {
  const suffix = value.length >= 4 ? value.slice(-4) : "";
  return `••••••••••••${suffix}`;
}
