export type ConversationHistoryEntry = {
  role: "user" | "assistant";
  text: string;
};

export type HistoryBudget = {
  maxMessages?: number;
  maxChars?: number;
  maxCharsPerMessage?: number;
};

export const DEFAULT_HISTORY_BUDGET = {
  maxMessages: 12,
  maxChars: 12_000,
  maxCharsPerMessage: 4_000,
} as const;

export function compactConversationHistory(
  history: ConversationHistoryEntry[] | undefined,
  budget: HistoryBudget = {},
): ConversationHistoryEntry[] {
  if (!history?.length) return [];
  const maxMessages = clampInteger(budget.maxMessages, DEFAULT_HISTORY_BUDGET.maxMessages, 1, 40);
  const maxChars = clampInteger(budget.maxChars, DEFAULT_HISTORY_BUDGET.maxChars, 500, 100_000);
  const maxCharsPerMessage = clampInteger(
    budget.maxCharsPerMessage,
    DEFAULT_HISTORY_BUDGET.maxCharsPerMessage,
    200,
    maxChars,
  );
  const selected: ConversationHistoryEntry[] = [];
  let remaining = maxChars;
  for (const message of history.slice(-maxMessages).reverse()) {
    if (remaining < 80) break;
    const text = message.text.trim();
    if (!text) continue;
    const allowance = Math.min(maxCharsPerMessage, remaining);
    const compacted = compactText(text, allowance);
    selected.push({ role: message.role, text: compacted });
    remaining -= compacted.length;
  }
  return selected.reverse();
}

export function compactText(value: string, maxChars: number): string {
  const text = value.trim();
  if (text.length <= maxChars) return text;
  if (maxChars < 80) return text.slice(0, maxChars);
  const marker = "\n[…context omis…]\n";
  const available = maxChars - marker.length;
  const head = Math.ceil(available * 0.6);
  return `${text.slice(0, head)}${marker}${text.slice(-(available - head))}`;
}

export function compactJsonForContext(value: unknown, maxChars = 24_000): unknown {
  const serialized = safeJson(value);
  if (serialized.length <= maxChars) return value;
  const pruned = pruneJson(value, 0);
  if (safeJson(pruned).length <= maxChars) {
    return {
      contextTruncated: true,
      originalChars: serialized.length,
      value: pruned,
    };
  }
  const prefix = JSON.stringify({
    contextTruncated: true,
    originalChars: serialized.length,
    hint: "Reapelează unealta cu o cale, limită sau selecție mai restrânsă dacă lipsesc detalii.",
    preview: "",
  });
  return {
    contextTruncated: true,
    originalChars: serialized.length,
    hint: "Reapelează unealta cu o cale, limită sau selecție mai restrânsă dacă lipsesc detalii.",
    preview: compactText(serialized, Math.max(200, maxChars - prefix.length - 16)),
  };
}

function clampInteger(value: number | undefined, fallback: number, minimum: number, maximum: number): number {
  if (value === undefined || !Number.isFinite(value)) return fallback;
  return Math.max(minimum, Math.min(maximum, Math.round(value)));
}

function pruneJson(value: unknown, depth: number): unknown {
  if (typeof value === "string") return compactText(value, depth < 2 ? 8_000 : 2_000);
  if (value === null || typeof value !== "object") return value;
  if (depth >= 8) return "[…adâncime omisă…]";
  if (Array.isArray(value)) {
    const kept = value.slice(0, 60).map((entry) => pruneJson(entry, depth + 1));
    if (value.length > kept.length) kept.push({ omittedItems: value.length - kept.length });
    return kept;
  }
  const entries = Object.entries(value as Record<string, unknown>);
  const kept = Object.fromEntries(entries.slice(0, 100).map(([key, entry]) => [key, pruneJson(entry, depth + 1)]));
  if (entries.length > 100) kept.contextOmittedKeys = entries.length - 100;
  return kept;
}

function safeJson(value: unknown): string {
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}
