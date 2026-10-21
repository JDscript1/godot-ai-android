import type { CanonicalToolDefinition } from "../../protocol/src/index.js";

export type PolicyDecision =
  | { outcome: "allow" }
  | { outcome: "approval_required"; reason: string }
  | { outcome: "deny"; reason: string };

export type AutonomyPolicy = {
  allowProjectWrites: boolean;
  allowExecution: boolean;
  allowExternalReads: boolean;
  allowExternalWrites: boolean;
  allowDestructive: boolean;
};

export const DEFAULT_AUTONOMY_POLICY: AutonomyPolicy = {
  allowProjectWrites: true,
  allowExecution: true,
  allowExternalReads: true,
  allowExternalWrites: false,
  allowDestructive: false,
};

export class PolicyEngine {
  constructor(readonly policy: AutonomyPolicy = DEFAULT_AUTONOMY_POLICY) {}

  authorize(tool: CanonicalToolDefinition): PolicyDecision {
    switch (tool.risk) {
      case "read":
        return { outcome: "allow" };
      case "write":
        return this.policy.allowProjectWrites
          ? { outcome: "allow" }
          : { outcome: "approval_required", reason: "Project writes require approval" };
      case "execute":
        return this.policy.allowExecution
          ? { outcome: "allow" }
          : { outcome: "approval_required", reason: "Execution requires approval" };
      case "external":
        return this.policy.allowExternalWrites
          ? { outcome: "allow" }
          : { outcome: "approval_required", reason: "External writes require approval" };
      case "destructive":
        return this.policy.allowDestructive
          ? { outcome: "allow" }
          : { outcome: "approval_required", reason: "Destructive action requires approval" };
    }
  }
}
