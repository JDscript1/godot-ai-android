import {
  compactJsonForContext,
  splitToolExecutionResult,
  type ToolExecutionResult,
} from "../../../packages/core/src/index.js";

export type McpToolResult = {
  isError: boolean;
  content: Array<
    | { type: "text"; text: string }
    | { type: "image"; data: string; mimeType: string }
  >;
};

export function toMcpToolResult(execution: ToolExecutionResult): McpToolResult {
  const { summary, images } = splitToolExecutionResult(execution);
  const payload = summary.ok ? compactJsonForContext(summary.result) : summary.error;
  return {
    isError: !execution.ok,
    content: [
      { type: "text", text: JSON.stringify(payload) },
      ...images.map((image) => ({ type: "image" as const, data: image.data, mimeType: image.mimeType })),
    ],
  };
}

export function toCodexToolContent(execution: ToolExecutionResult): Array<Record<string, unknown>> {
  const { summary, images } = splitToolExecutionResult(execution);
  const payload = summary.ok ? compactJsonForContext(summary.result) : { error: summary.error };
  return [
    { type: "inputText", text: JSON.stringify(payload) },
    ...images.map((image) => ({
      type: "inputImage",
      imageUrl: `data:${image.mimeType};base64,${image.data}`,
    })),
  ];
}
