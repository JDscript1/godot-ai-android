import type { ProviderKind } from "../../packages/protocol/src/index.js";
import { AnthropicAdapter } from "./anthropic.js";
import { GeminiAdapter } from "./gemini.js";
import { OpenAIChatAdapter } from "./openai-chat.js";
import { OpenAIResponsesAdapter } from "./openai-responses.js";
import type { ProviderAdapter } from "./types.js";

export * from "./types.js";

export function createProviderAdapter(kind: ProviderKind): ProviderAdapter {
  switch (kind) {
    case "openai-codex-account":
    case "anthropic-claude-account":
    case "github-copilot-account":
    case "kimi-code-account":
      throw new Error("Subscription account providers require their official account runtime");
    case "openai":
      return new OpenAIResponsesAdapter();
    case "gemini":
      return new GeminiAdapter();
    case "anthropic":
      return new AnthropicAdapter();
    case "deepseek":
    case "openai-compatible":
    case "llama-cpp":
    case "ollama":
      return new OpenAIChatAdapter(kind);
  }
}
