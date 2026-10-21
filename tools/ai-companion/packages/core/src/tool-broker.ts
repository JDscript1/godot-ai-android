import { z } from "zod";
import type { CanonicalToolDefinition } from "../../protocol/src/index.js";
import { PolicyEngine } from "./policy.js";

type ToolRegistration<T extends z.ZodType> = {
  name: string;
  description: string;
  risk: CanonicalToolDefinition["risk"];
  schema: T;
  execute: (input: z.infer<T>) => Promise<unknown>;
};

type StoredTool = ToolRegistration<z.ZodType> & {
  definition: CanonicalToolDefinition;
};

export type RuntimeToolDefinition = {
  definition: CanonicalToolDefinition;
  schema: z.ZodType;
};

export type ToolExecutionResult =
  | { ok: true; result: unknown }
  | { ok: false; error: { code: string; message: string; details?: unknown } };

export type ToolImagePayload = {
  mimeType: string;
  data: string;
  width?: number;
  height?: number;
  description?: string;
};

export type SplitToolExecutionResult = {
  summary: ToolExecutionResult;
  images: ToolImagePayload[];
};

export function splitToolExecutionResult(execution: ToolExecutionResult): SplitToolExecutionResult {
  if (!execution.ok || !isRecord(execution.result)) return { summary: execution, images: [] };
  const result = execution.result;
  const candidates = [result.image, ...(Array.isArray(result.images) ? result.images : [])];
  const images = candidates.filter(isToolImagePayload).slice(0, 4);
  if (images.length === 0) return { summary: execution, images: [] };
  const sanitized: Record<string, unknown> = { ...result };
  if (isToolImagePayload(result.image)) sanitized.image = summarizeImage(result.image);
  if (Array.isArray(result.images)) {
    sanitized.images = result.images.map((image) => isToolImagePayload(image) ? summarizeImage(image) : image);
  }
  return { summary: { ok: true, result: sanitized }, images };
}

export class ToolBroker {
  readonly #tools = new Map<string, StoredTool>();

  constructor(
    readonly policy: PolicyEngine,
    readonly allowedRisks?: readonly CanonicalToolDefinition["risk"][],
  ) {}

  register<T extends z.ZodType>(registration: ToolRegistration<T>): void {
    if (this.#tools.has(registration.name)) {
      throw new Error(`Tool already registered: ${registration.name}`);
    }
    this.#tools.set(registration.name, {
      ...registration,
      definition: {
        name: registration.name,
        description: registration.description,
        risk: registration.risk,
        inputSchema: z.toJSONSchema(registration.schema) as Record<string, unknown>,
      },
    } as StoredTool);
  }

  definitions(names?: string[]): CanonicalToolDefinition[] {
    const selected = names
      ? names.map((name) => this.#tools.get(name)).filter((tool): tool is StoredTool => Boolean(tool))
      : [...this.#tools.values()];
    return selected.filter((tool) => this.#isVisible(tool)).map((tool) => tool.definition);
  }

  runtimeDefinitions(names?: string[]): RuntimeToolDefinition[] {
    const selected = names
      ? names.map((name) => this.#tools.get(name)).filter((tool): tool is StoredTool => Boolean(tool))
      : [...this.#tools.values()];
    return selected.filter((tool) => this.#isVisible(tool)).map((tool) => ({
      definition: tool.definition,
      schema: tool.schema,
    }));
  }

  async execute(name: string, input: unknown): Promise<ToolExecutionResult> {
    const tool = this.#tools.get(name);
    if (!tool) {
      return { ok: false, error: { code: "TOOL_NOT_FOUND", message: `Unknown tool: ${name}` } };
    }
    if (!this.#isVisible(tool)) {
      return { ok: false, error: { code: "MODE_DENIED", message: `Tool ${name} is not available in the selected mode` } };
    }
    const decision = this.policy.authorize(tool.definition);
    if (decision.outcome !== "allow") {
      return {
        ok: false,
        error: {
          code: decision.outcome === "deny" ? "POLICY_DENIED" : "APPROVAL_REQUIRED",
          message: decision.reason,
        },
      };
    }
    const parsed = tool.schema.safeParse(input);
    if (!parsed.success) {
      return {
        ok: false,
        error: {
          code: "INVALID_TOOL_ARGUMENTS",
          message: `Invalid arguments for ${name}`,
          details: parsed.error.issues,
        },
      };
    }
    try {
      return { ok: true, result: await tool.execute(parsed.data) };
    } catch (error) {
      return {
        ok: false,
        error: {
          code: "TOOL_EXECUTION_FAILED",
          message: error instanceof Error ? error.message : "Unknown tool execution error",
        },
      };
    }
  }

  #isVisible(tool: StoredTool): boolean {
    return !this.allowedRisks || this.allowedRisks.includes(tool.definition.risk);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isToolImagePayload(value: unknown): value is ToolImagePayload {
  return isRecord(value)
    && typeof value.mimeType === "string"
    && value.mimeType.startsWith("image/")
    && typeof value.data === "string"
    && value.data.length > 0;
}

function summarizeImage(image: ToolImagePayload): Record<string, unknown> {
  const { data, ...summary } = image;
  return { ...summary, encodedBytes: Math.floor(data.length * 0.75) };
}
