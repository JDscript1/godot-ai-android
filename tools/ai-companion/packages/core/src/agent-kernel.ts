import type {
  CanonicalContent,
  CanonicalMessage,
  CanonicalTurnResult,
  ReasoningEffort,
} from "../../protocol/src/index.js";
import type { ProviderAdapter, ProviderConnection } from "../../../providers/src/types.js";
import { agentInstructions } from "./agent-instructions.js";
import { compactConversationHistory, compactJsonForContext } from "./context-budget.js";
import { splitToolExecutionResult, ToolBroker } from "./tool-broker.js";

export type AgentRunInput = {
  connection: ProviderConnection;
  adapter: ProviderAdapter;
  model: string;
  mode?: "agent" | "plan";
  text: string;
  history?: Array<{ role: "user" | "assistant"; text: string }>;
  attachments?: CanonicalContent[];
  maxTurns?: number;
  skillInstructions?: string[];
  toolNames?: string[];
  effort?: ReasoningEffort;
  signal?: AbortSignal;
  onProgress?: (event: AgentProgressEvent) => void | Promise<void>;
};

export type AgentProgressEvent =
  | { type: "assistant_text"; text: string; turn: number }
  | { type: "usage"; usage: NonNullable<CanonicalTurnResult["usage"]>; turn: number }
  | { type: "tool_started"; name: string; arguments: unknown; turn: number }
  | { type: "tool_completed"; name: string; ok: boolean; turn: number };

export type AgentRunResult = {
  text: string;
  messages: CanonicalMessage[];
  turns: number;
  stopReason: CanonicalTurnResult["stopReason"] | "max_turns";
  usage?: CanonicalTurnResult["usage"];
};

export class AgentKernel {
  constructor(readonly tools: ToolBroker) {}

  async run(input: AgentRunInput): Promise<AgentRunResult> {
    const maxTurns = Math.max(1, Math.min(input.maxTurns ?? 12, 30));
    const userContent: CanonicalContent[] = [
      { type: "text", text: input.text },
      ...(input.attachments ?? []),
    ];
    const messages: CanonicalMessage[] = [
      {
        role: "system",
        content: [{
          type: "text",
          text: agentInstructions({
            mode: input.mode,
            skillInstructions: input.skillInstructions?.join("\n\n---\n\n"),
          }),
        }],
      },
      ...compactConversationHistory(input.history).map((message): CanonicalMessage => ({
        role: message.role,
        content: [{ type: "text", text: message.text }],
      })),
      { role: "user", content: userContent },
    ];
    let accumulatedText = "";
    let providerState: Record<string, unknown> | undefined;
    let lastUsage: CanonicalTurnResult["usage"];

    for (let turn = 1; turn <= maxTurns; turn += 1) {
      input.signal?.throwIfAborted();
      const request = {
        model: input.model,
        messages,
        tools: this.tools.definitions(input.toolNames),
        ...(input.effort ? { effort: input.effort } : {}),
        maxOutputTokens: 8192,
        ...(providerState ? { providerState } : {}),
      };
      const result = await input.adapter.complete(input.connection, request, input.signal);
      if (result.providerState) providerState = result.providerState;
      if (result.usage) {
        lastUsage = result.usage;
        await input.onProgress?.({ type: "usage", usage: result.usage, turn });
      }
      if (result.text) {
        accumulatedText = result.text;
        await input.onProgress?.({ type: "assistant_text", text: result.text, turn });
      }

      messages.push({
        role: "assistant",
        content: result.text ? [{ type: "text", text: result.text }] : [],
        ...(result.toolCalls.length ? { toolCalls: result.toolCalls } : {}),
      });

      if (!result.toolCalls.length) {
        return {
          text: accumulatedText,
          messages,
          turns: turn,
          stopReason: result.stopReason,
          ...(lastUsage ? { usage: lastUsage } : {}),
        };
      }

      for (const call of result.toolCalls) {
        input.signal?.throwIfAborted();
        await input.onProgress?.({
          type: "tool_started",
          name: call.name,
          arguments: call.arguments,
          turn,
        });
        const execution = await this.tools.execute(call.name, call.arguments);
        input.signal?.throwIfAborted();
        const visualResult = splitToolExecutionResult(execution);
        await input.onProgress?.({
          type: "tool_completed",
          name: call.name,
          ok: execution.ok,
          turn,
        });
        messages.push({
          role: "tool",
          toolCallId: call.id,
          toolName: call.name,
          content: [{
            type: "json",
            value: visualResult.summary.ok
              ? { ok: true, result: compactJsonForContext(visualResult.summary.result) }
              : visualResult.summary,
          }],
        });
        if (visualResult.images.length > 0) {
          messages.push({
            role: "user",
            content: [
              { type: "text", text: `Visual result from ${call.name}. Inspect the attached editor capture before deciding the next action.` },
              ...visualResult.images.map((image) => ({
                type: "image" as const,
                mimeType: image.mimeType,
                data: image.data,
              })),
            ],
          });
        }
      }
    }

    return {
      text: accumulatedText || "Agentul a atins limita de pași fără un răspuns final.",
      messages,
      turns: maxTurns,
      stopReason: "max_turns",
      ...(lastUsage ? { usage: lastUsage } : {}),
    };
  }
}
