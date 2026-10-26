# Agent model selection and automatic tariffs

Implemented in source on 26 October 2026. The APK currently in Android Download
is still `c418f97`; it does not contain this change.

In **Furnizori AI**, select the billing provider and paste its API key. After an
800 ms pause, the native Godot adapter checks the model catalog using the draft
key in memory. Choose a model in the searchable table, then save. A rejected
replacement key cannot overwrite the saved key. Changing providers clears the
draft key, cancels old requests and invalidates pending results. Prefixes identify
only unambiguous providers; a generic `sk-` key requires the provider selection.

Each model row has input and output columns per **one million tokens** in the
provider's currency. Selecting a row shows cached input, cache writes where
published, conditions, source and UTC verification time. The chat model drawer
also shows token prices, preserving provider → model → reasoning navigation.
Local models and subscriptions have their own labels, without cloud API prices.

## Refresh behavior

- Public tariffs have a six-hour cache in `ai_assistant/model-prices.json`.
  Startup, opening a provider's models and an hourly timer check freshness;
  only configured profiles are refreshed. The app must be running. Returning
  after Android suspension rechecks freshness when opening the model drawer.
- **Actualizează tarife** forces a public tariff refresh. The chat drawer's
  **Actualizează** reloads models and prices. These operations preserve the
  current model, reasoning level and drawer search.
- Failed updates retain the last verified tariff with the **anterior** marker.
  Automatic retries back off for five minutes. No matching or verifiable rate
  produces **Tarif nepublicat**, never an invented zero.
- Public reads contain no API keys, account tokens or prompts and submit no
  inference or generation request. Large documentation pages parse on a worker
  thread to keep the editor responsive.

OpenRouter documents prices per token; the adapter converts those fields to
per-million units. Direct provider prices are matched only to that provider's
canonical billing endpoint. A compatible gateway does not inherit a direct
provider's tariff. Exact normalized model IDs or display names are matched;
new, unrecognized aliases remain unpriced.

Standard rates take precedence over batch/priority prices. Long-context and
peak/off-peak tariffs are retained as variants and displayed as a range with
conditions. The app does not guess Chinese public holidays to decide which
DeepSeek tier applies. Ambiguous future price schedules remain unpriced until
an unambiguous rate can be extracted. This is a reference rate card, not an
account invoice or a prediction of total task cost; tool fees, image/audio units,
negotiated discounts, taxes and currency conversion are not included.

## First-party sources and live read-only verification

The Godot transport successfully retrieved and parsed these public sources on
26 October 2026, without a user API key or a paid model call:

| Billing provider | Parsed entries | Source |
| --- | ---: | --- |
| OpenAI | 69 | [Pricing](https://developers.openai.com/api/docs/pricing.md) |
| Anthropic | 21 | [Pricing](https://platform.claude.com/docs/en/about-claude/pricing.md) |
| DeepSeek | 4 including published legacy aliases | [Pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| OpenRouter | 460 | [Models API](https://openrouter.ai/api/v1/models) |
| Gemini | 3 unambiguous standard entries | [Pricing](https://ai.google.dev/gemini-api/docs/pricing) |
| Qwen International | 58 | [Pricing](https://www.alibabacloud.com/help/en/model-studio/model-pricing) |
| Qwen China | 151 | [Pricing](https://help.aliyun.com/zh/model-studio/model-pricing) |
| Mistral | 11 | [Pricing](https://docs.mistral.ai/inference/pricing.md) |
| Groq | 6 | [Models and prices](https://console.groq.com/docs/models.md) |
| xAI | 8 | [Models](https://docs.x.ai/developers/models) |
| Z.AI | 9 | [Pricing](https://docs.z.ai/guides/overview/pricing.md) |
| MiniMax | 2 | [Pricing](https://platform.minimax.io/docs/guides/pricing-paygo.md) |

These are entries parsed from public rate cards, not authenticated account model
availability. They do not guarantee a tariff match for every model returned by a
provider. Kimi's documentation returned no usable prices in this probe;
SiliconFlow's public page did not expose supported price tables. NVIDIA has no
configured verifiable public per-token feed. Their model discovery remains
available; unverified prices are labeled accordingly.

Image/3D pricing remains a separate catalog: Runware already refreshes public
schemas with a 24-hour cache; Meshy, Tripo and OpenAI image presets remain dated
reference data as described in [generation setup](AI_GENERATION.md). The new
six-hour automatic updater applies to **agent token tariffs**.

## Verification evidence

Runtime assertions exercise units, explicit zero versus missing prices,
standard/context variants, cache persistence, offline retention, retry backoff,
credential-free document reads, custom billing endpoints, subscriptions/local
labels, background parsing and draft credential isolation.

Rendered editor checks exercise key paste, selection before saving, distinct
price columns, model/reasoning navigation, live refresh without losing the
search or selection, rejected replacement keys, stale markers, provider changes,
layout and the start screen. Deterministic API fixtures use dummy credentials.

Local evidence: `.ai-qa/agent-pricing-runtime.log`,
`.ai-qa/agent-pricing-ui-narrow/`, `.ai-qa/agent-pricing-ui-tablet/`,
`.ai-qa/agent-pricing-all/`, `.ai-qa/agent-pricing-start/`,
`.ai-qa/agent-pricing-live.log`, `.ai-qa/agent-pricing-public-probe.log`.

No new APK has been compiled or installed for this change. Physical Android
key entry and paid provider behavior remain separate from these checks.
