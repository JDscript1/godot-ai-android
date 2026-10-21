import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import type { SkillStatus, SkillSummary } from "../../protocol/src/index.js";

const metadataSchema = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1).max(80),
  description: z.string().trim().min(1).max(500),
  status: z.enum(["draft", "validated", "promoted", "quarantined", "disabled"]),
  scope: z.enum(["builtin", "user", "project"]),
  version: z.number().int().positive(),
  enabled: z.boolean(),
  updatedAt: z.string(),
});

export type SkillProposal = {
  name: string;
  description: string;
  instructions: string;
  scope?: "user" | "project";
};

export type RelevantSkillOptions = {
  limit?: number;
  maxChars?: number;
};

type ActiveSkill = {
  id: string;
  name: string;
  description: string;
  instructions: string;
};

export class SkillRegistry {
  constructor(
    readonly builtinDir: string,
    readonly userDir: string,
  ) {}

  async list(): Promise<SkillSummary[]> {
    const skills = [
      ...(await this.#readScope(this.builtinDir, "builtin")),
      ...(await this.#readScope(this.userDir, "user")),
    ];
    return skills.sort((a, b) => a.name.localeCompare(b.name));
  }

  async activeInstructions(): Promise<string[]> {
    const active: string[] = [];
    for (const directory of await this.#skillDirectories(this.builtinDir)) {
      active.push(await readFile(path.join(directory, "SKILL.md"), "utf8"));
    }
    for (const directory of await this.#skillDirectories(this.userDir)) {
      try {
        const metadata = metadataSchema.parse(JSON.parse(await readFile(path.join(directory, "skill.json"), "utf8")));
        if (metadata.enabled && (metadata.status === "promoted" || metadata.status === "validated")) {
          active.push(await readFile(path.join(directory, "SKILL.md"), "utf8"));
        }
      } catch {
        // Invalid or incomplete user skills are quarantined by omission.
      }
    }
    return active;
  }

  async relevantInstructions(query: string, options: RelevantSkillOptions = {}): Promise<string[]> {
    const limit = Math.max(1, Math.min(options.limit ?? 2, 5));
    const maxChars = Math.max(500, Math.min(options.maxChars ?? 6_000, 30_000));
    const queryTerms = searchableTerms(query);
    if (queryTerms.size === 0) return [];
    const ranked = (await this.#activeSkills())
      .map((skill) => ({ skill, score: skillRelevance(skill, query, queryTerms) }))
      .filter((entry) => entry.score > 0)
      .sort((left, right) => right.score - left.score || left.skill.name.localeCompare(right.skill.name));
    const selected: string[] = [];
    let remaining = maxChars;
    for (const { skill } of ranked.slice(0, limit)) {
      if (remaining < 200) break;
      const instructions = compactSkill(skill.instructions, remaining);
      selected.push(instructions);
      remaining -= instructions.length;
    }
    return selected;
  }

  async propose(input: SkillProposal): Promise<SkillSummary> {
    const slug = slugify(input.name);
    if (!slug) throw new Error("Skill name must contain letters or numbers");
    const directory = path.join(this.userDir, `${slug}-${randomUUID().slice(0, 8)}`);
    await mkdir(this.userDir, { recursive: true, mode: 0o700 });
    await mkdir(directory, { recursive: false, mode: 0o700 });
    const metadata: SkillSummary = {
      id: randomUUID(),
      name: input.name.trim(),
      description: input.description.trim(),
      status: "draft",
      scope: input.scope ?? "user",
      version: 1,
      enabled: false,
      updatedAt: new Date().toISOString(),
    };
    await writeFile(path.join(directory, "skill.json"), `${JSON.stringify(metadata, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    await writeFile(
      path.join(directory, "SKILL.md"),
      `---\nname: ${yamlString(metadata.name)}\ndescription: ${yamlString(metadata.description)}\n---\n\n${input.instructions.trim()}\n`,
      { encoding: "utf8", mode: 0o600 },
    );
    return metadata;
  }

  async setEnabled(id: string, enabled: boolean): Promise<SkillSummary> {
    const located = await this.#locateUserSkill(id);
    if (!located) throw new Error(`Skill not found or read-only: ${id}`);
    const metadata: SkillSummary = {
      ...located.metadata,
      enabled,
      status: enabled ? "promoted" : "disabled",
      version: located.metadata.version + 1,
      updatedAt: new Date().toISOString(),
    };
    await writeFile(located.metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    return metadata;
  }

  async delete(id: string): Promise<boolean> {
    const located = await this.#locateUserSkill(id);
    if (!located) return false;
    await rm(located.directory, { recursive: true });
    return true;
  }

  async #readScope(directory: string, fallbackScope: SkillSummary["scope"]): Promise<SkillSummary[]> {
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw error;
    }
    const results: SkillSummary[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const skillDirectory = path.join(directory, entry.name);
      try {
        const parsed = metadataSchema.parse(JSON.parse(await readFile(path.join(skillDirectory, "skill.json"), "utf8")));
        results.push(parsed);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT" && fallbackScope === "builtin") {
          const markdown = await readFile(path.join(skillDirectory, "SKILL.md"), "utf8");
          const title = entry.name.replace(/-/g, " ");
          results.push({
            id: `builtin:${entry.name}`,
            name: title,
            description: markdown.split("\n").find((line) => line.startsWith("description:"))?.slice(12).trim() ?? title,
            status: "promoted",
            scope: "builtin",
            version: 1,
            enabled: true,
            updatedAt: new Date(0).toISOString(),
          });
        }
      }
    }
    return results;
  }

  async #locateUserSkill(id: string): Promise<{ directory: string; metadataPath: string; metadata: SkillSummary } | undefined> {
    const entries = await this.#readScopeEntries(this.userDir);
    for (const directory of entries) {
      const metadataPath = path.join(directory, "skill.json");
      try {
        const metadata = metadataSchema.parse(JSON.parse(await readFile(metadataPath, "utf8")));
        if (metadata.id === id) return { directory, metadataPath, metadata };
      } catch {
        // A malformed skill is isolated instead of blocking all skill management.
      }
    }
    return undefined;
  }

  async #readScopeEntries(directory: string): Promise<string[]> {
    try {
      const entries = await readdir(directory, { withFileTypes: true });
      return entries.filter((entry) => entry.isDirectory()).map((entry) => path.join(directory, entry.name));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw error;
    }
  }

  async #activeSkills(): Promise<ActiveSkill[]> {
    const active: ActiveSkill[] = [];
    for (const directory of await this.#skillDirectories(this.builtinDir)) {
      try {
        const instructions = await readFile(path.join(directory, "SKILL.md"), "utf8");
        const slug = path.basename(directory);
        active.push({
          id: `builtin:${slug}`,
          name: frontmatterValue(instructions, "name") || slug.replace(/-/g, " "),
          description: frontmatterValue(instructions, "description") || slug.replace(/-/g, " "),
          instructions,
        });
      } catch {
        // One invalid built-in skill must not prevent other relevant skills.
      }
    }
    for (const directory of await this.#skillDirectories(this.userDir)) {
      try {
        const metadata = metadataSchema.parse(JSON.parse(await readFile(path.join(directory, "skill.json"), "utf8")));
        if (!metadata.enabled || (metadata.status !== "promoted" && metadata.status !== "validated")) continue;
        active.push({
          id: metadata.id,
          name: metadata.name,
          description: metadata.description,
          instructions: await readFile(path.join(directory, "SKILL.md"), "utf8"),
        });
      } catch {
        // Invalid or incomplete user skills are quarantined by omission.
      }
    }
    return active;
  }

  async #skillDirectories(directory: string): Promise<string[]> {
    return this.#readScopeEntries(directory);
  }
}

function slugify(value: string): string {
  return value.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);
}

function yamlString(value: string): string {
  return JSON.stringify(value);
}

function frontmatterValue(markdown: string, key: string): string {
  const match = new RegExp(`^${key}:\\s*(.+)$`, "m").exec(markdown);
  if (!match?.[1]) return "";
  const value = match[1].trim();
  if (value.startsWith('"') && value.endsWith('"')) {
    try {
      const parsed = JSON.parse(value);
      return typeof parsed === "string" ? parsed : value;
    } catch {
      return value.slice(1, -1);
    }
  }
  return value;
}

function skillRelevance(skill: ActiveSkill, rawQuery: string, queryTerms: Set<string>): number {
  const normalizedQuery = normalizeSearchText(rawQuery);
  const normalizedName = normalizeSearchText(skill.name);
  const explicit = normalizedName.length > 2 && normalizedQuery.includes(normalizedName);
  const nameTerms = searchableTerms(skill.name);
  const descriptionTerms = searchableTerms(skill.description);
  let score = explicit ? 100 : 0;
  for (const term of queryTerms) {
    if (nameTerms.has(term)) score += 4;
    if (descriptionTerms.has(term)) score += 1;
  }
  return score;
}

function searchableTerms(value: string): Set<string> {
  const aliases: Record<string, string[]> = {
    animatie: ["animation"], animatii: ["animation"], animarea: ["animation"],
    schelet: ["skeleton"], schelete: ["skeleton"], rig: ["skeleton"],
    os: ["bone"], oase: ["bone"], mers: ["walk"], alergare: ["run"], atac: ["attack"],
    proiect: ["project"], scena: ["scene"], scene: ["scene"], scripturi: ["script"],
    interfata: ["ui"], buton: ["ui"], eroare: ["error"], erori: ["error"], depanare: ["debug"],
  };
  const ignored = new Set(["the", "and", "for", "with", "from", "this", "that", "godot", "agent", "agentul", "nostru", "vreau", "avem", "este", "sunt", "pentru", "care", "sa", "să", "din", "prin"]);
  const terms = new Set<string>();
  for (const term of normalizeSearchText(value).split(/[^a-z0-9_]+/)) {
    if (term.length < 3 || ignored.has(term)) continue;
    terms.add(term);
    for (const alias of aliases[term] ?? []) terms.add(alias);
  }
  return terms;
}

function normalizeSearchText(value: string): string {
  return value.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
}

function compactSkill(instructions: string, maxChars: number): string {
  const value = instructions.trim();
  if (value.length <= maxChars) return value;
  const marker = "\n\n[Skill trunchiat la bugetul de context]";
  return `${value.slice(0, Math.max(0, maxChars - marker.length))}${marker}`;
}
