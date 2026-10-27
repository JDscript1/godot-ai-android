# Built-in Godot agent harness

The fork owns its agent harness. `modules/ai_assistant/runtime/harness.gd` runs
inside the Godot editor using engine objects and native HTTP adapters. It is
embedded in the editor binary by `runtime_builder.py`, alongside the other
editor services. It does not install or start Termux, Node.js, Python, a shell,
Pi, OpenCode, or a separate agent server on the user's device.

The original harness shipped in APK `12794c4`. The latest delivered and installed
APK verified on 2026-10-27 is `74887a1`, including unlimited normal execution.
The result-compaction, reflection-pagination and interrupted-context fixes
described below are a subsequent source iteration. Delivery evidence is tracked in
[the project progress record](../PROGRES_SI_PLAN.md).

## Stability iteration, 2026-10-27 (source)

Large tool responses retain their root success/error contract and compact artifact
identity when the model-facing JSON is shortened. The complete sanitized journal
is separate. The serialized summary, including escaped text, stays within 24,000
characters; omitted fields are not evidence that a class or artifact is absent.
`godot_describe` returns stable alphabetical pages, 16 entries per category by
default (maximum 50), with totals and `next_offset`. Literal case-insensitive
filters support alternatives separated by `|`.

Local interruption notices, incomplete streamed drafts and generated-file cards
carry application provenance. Provider requests send their useful context as
application state in system messages, preserving the chat UI and confirmed model
messages. Older interruption records and file cards are recognized as well. This
avoids presenting a local notice as a DeepSeek thinking response with missing
`reasoning_content`; no reasoning is invented. Confirmed reasoning survives
conversation save/load and forking, while switching provider/model still strips
foreign protocol internals. The current DeepSeek contract is documented in its
[official thinking-mode guide](https://api-docs.deepseek.com/guides/thinking_mode/).

See the [device stability report and next acceptance gates](AI_AGENT_STABILITY_20261027.md)
for actual Android results and remaining work. Fixture success does not establish
live provider acceptance or readiness for large game production.

The follow-up source guidance asks the model to update task milestones before
moving on, use three concise result points by default, batch independent known
actions, and summarize test failures instead of flooding Output with successful
assertions. These are model instructions, not enforced proof of progress or
latency improvements. Live Resume with the corrected temporary provider adapter
passed; permanent APK acceptance and the default behavior under the new guidance
remain separate checks.

## Execution boundaries

```text
Native chat / latest user request
             |
       Built-in harness
       /             \
Provider adapters    Editor tool dispatcher
       |             /       |       \
Model HTTP API     Godot    Assets    MCP HTTP
```

`panel.gd` supplies the current project context, selected model, permissions,
conversation storage, stream rendering, and tool dispatcher. `agent_jobs.gd`
uses an independent instance of the same harness for each direct-provider
Explore, General, or Playtest child. Children retain their existing restricted
tool sets and concurrency limits.

The model remains a separate service. Cloud APIs need their normal connection
and credentials. Ollama, LM Studio, and llama.cpp profiles connect to an already
running model endpoint. This harness does not add an inference engine or install
model weights in the APK.

Local profiles accept an IP or full API URL. **Conectează** saves the endpoint,
tests its catalog and selects a loaded chat model where the server reports one.
LM Studio metadata and Ollama's native tags/process endpoints provide loaded
state and actual loaded context; unavailable metadata does not block the catalog.
Embedding models are excluded when LM Studio reports their type.

Catalog checks have a short connection deadline. Inference uses independent
connection, first-response, stream-inactivity and total deadlines: local profiles
allow 8, 300, 180 and 1,800 seconds respectively. Received bytes refresh the
inactivity deadline without removing the total cap. Stop remains cancellable.
A response/body timeout is reported as `inference_timeout`, without an automatic
retry that could queue another expensive request on a busy local server.

Existing subscription providers that use the companion remain optional
integrations. They do not back direct API sessions. This change does not turn
CLI subscription authentication into native Android authentication. MCP
Streamable HTTP runs directly; arbitrary MCP stdio programs still need a host
for those programs. Native HTTP generation adapters remain available for image
and GLB generation.

## Runtime contract

`Harness.run(options, hooks)` takes one turn and returns a structured outcome.
Each harness instance accepts one active turn. Different instances have separate
messages, cancellation tokens, statistics, and tool-result ledgers.

Options include `id`, `messages`, `tools`, `cancel`, `metadata`, `max_steps`,
`max_retries`, `retry_delay_ms`, `deferred_tools`, and `deduplicate_tools`.
The supplied messages array receives the
finalized assistant and tool messages. Hooks are:

| Hook | Responsibility |
| --- | --- |
| `complete(context, tools, cancel, delta)` | Call a provider through its native adapter |
| `execute(name, arguments)` | Validate permissions and execute an allowed tool |
| `context()` | Optionally rebuild project context before each model step |
| `redact(text)` | Remove known credentials from stored/output data |
| `checkpoint(snapshot)` | Persist the transcript and run state; `false` stops further execution |
| `needs_continuation()` | Continue after a tool-free answer while the host has unfinished execution steps, retaining cancellation and no-progress checks |
| `blocked_reason()` | Return the host's unresolved blocker so a tool-free answer settles as blocked rather than completed |

The `event` signal reports state changes, request attempts, streamed text,
finalized messages, tool starts/results, retries, and settlement. Tool-result
events distinguish a dispatched call from a recovered result or blocked call.
Provider-reported usage remains available to the chat.

Outcomes distinguish `completed`, `blocked`, `failed`, `cancelled`, and `limited`.
`completed` means that the model ended its tool loop; it is not independent
proof that the user's whole project works. Step and output limits never report
completion. Request, retry, step, and dispatched-tool counts are separate.
Response, tool and total durations are reported without exposing reasoning.
The panel journals call IDs, arguments, executed/replayed state and errors, as
well as model requests, retries, usage and settlement. An explicitly blocked
plan preserves that state in checkpoints and chat, leaving Resume available.

## Auto, Default and Plan

The chat offers three modes: Auto, Default and Plan. Default is initially selected
for new configurations. Auto proactively plans implementation and generation;
the host rejects modifying/external calls until an executing plan exists. Default
can perform small tasks directly and plans complex work. Plan inspects and
publishes a proposal without project mutations. General controls automatic permissions through YOLO; with YOLO off, each
mutation/external operation requests confirmation. The mode menu contains only
Auto, Default and Plan. Applying a plan retains the YOLO preference. Existing low-level permission IDs remain internal.
The active turn freezes its mode. A new message retains its provider/model/mode
selection, cancels outdated work at the next cancellation boundary, and starts
after the previous turn settles. Explicit Stop pauses the queue instead.

`planner.gd` owns a per-turn state machine and upgrades the existing `task_update`
tool without adding another tool name. Steps accept legacy strings or structured
`{step, status}` objects; statuses are pending, in_progress or completed, with at
most one active step. Phases are planning, executing, verifying, completed and
blocked. Stopping unfinished execution preserves a paused snapshot. Invalid
updates leave the previous state unchanged. A completed execution requires all
steps completed; a completed proposal retains its implementation steps pending.

In Default, the model decides whether complexity, uncertainty or dependencies
justify a plan. Auto requires a short plan before each task that changes the
project or calls an external operation. Both modes continue unfinished execution
plans. Greetings, identity questions and simple factual answers are instructed
to use one or two sentences without plans or tools. Planning and proposal phases reject mutations
at the host dispatcher. Plan mode also filters the tool catalog and enforces
read-only permissions independently. A model cannot grant itself write permission
through `task_update`. Auto and Default continue after an intermediate tool-free answer when
an execution plan is unfinished; blocked plans and proposals do not force another
request. Normal editor runs have no step ceiling. The optional companion path
also continues progressing plans without the previous five-turn ceiling and
stops after three continuations with no successful tool or meaningful plan
change. Live subscription continuation has not been tested; an external SDK or
service may impose its own limits.

Snapshots are stored in run checkpoints and conversation history. The chat
restores one collapsible card per turn, rather than repeating task-update logs.
Displayed steps are concise task progress, not internal reasoning. Completion
states are model-reported and must be checked against real tool results; the
harness cannot independently prove arbitrary project correctness.

## Unlimited normal execution (source, 2026-10-26)

Direct-provider chat and child runs continue until a final answer, an actual
blocker, cancellation, provider failure or a no-progress outcome. There is no
default 30-step ceiling, no hidden 100-step clamp, and no replacement large
number. Explore/General children no longer stop after 12 requests; Playtest no
longer has a task-wide step/time cutoff. Old `agent_step_limit`, `play_steps`
and `play_seconds` preferences are removed on load and never passed to a run.
Child concurrency limits and operation-specific timeouts remain independent.

`max_steps` is retained solely as an explicitly supplied evaluation option:
omitted, zero or negative means unlimited, and a positive value bounds that
isolated evaluation without a 100-step clamp. Production callers omit it.
`request_started.maximum = 0` therefore means unlimited. The standalone API
evaluator enforces its separate request/time budget through cancellation.

Stop, owner removal, interrupted streams, checkpoint failures, declined
permissions and paid-operation deduplication still apply. Three identical
failed/replayed operations, or three tool-free continuations of an unfinished
plan, stop as `no_progress`; productive work does not consume a total step
budget. Each iteration yields to the editor even when callbacks are synchronous.
Provider context/output quotas and individual request timeouts remain real
constraints; unlimited steps do not imply an unlimited context window or prove
task completion.

Automated regression evidence is recorded in `PROGRES_SI_PLAN.md`. This change
does not by itself fix the separate Runware HTTP 500/success recovery failure
observed in the installed APK's forest-scene workflow.

## Tools, retries, and recovery

- Direct chat and child runs enable deferred discovery. `tool_registry.gd`
  initially declares a small inspection set plus `tool_search` and
  `tool_describe`. Discovery loads matching tool schemas for the next model
  request. Tools excluded from the permitted catalog cannot be discovered.
  Guessing an unloaded name returns `tool_not_loaded` without dispatch.
- Tool arguments are validated before dispatch using an explicit JSON Schema
  subset: objects, arrays, primitive types, required/additional properties,
  integral JSON numbers, bounds, enums, patterns, local references, and basic
  combinators. Unsupported constraints or external references fail explicitly.
  `format` is annotation-only; this is not a complete JSON Schema implementation.
- Only tools in the current run's registry can reach the dispatcher. Plan cannot gain a mutation tool by naming it in a model reply. Auto with YOLO
  off still requires explicit approval before dispatching modifying/external tools.
  The existing editor permission checks still run before an actual operation.
- A response must have matching assistant/tool-call data, dictionary arguments,
  nonempty unique call IDs, and at most 64 calls. A reused ID with a different
  name or arguments fails before any call from that response is executed.
- A recorded call ID with matching arguments receives its saved result instead
  of executing again. Recoverable plan/discovery preflight failures can be
  retried after their requirements are fixed. Conflicting IDs still fail.
- The main chat additionally deduplicates `asset_generate` and
  `github_create_issue` by tool name and exact argument signature within the
  same user turn, including a resumed turn. A new provider call ID cannot
  resubmit the same operation. Generation's optional `variant` distinguishes
  additional outputs explicitly requested by the user. New user turns can
  request another output. This does not equate differently worded prompts.
- A declined operation is remembered for the current turn even if the model
  changes call IDs, avoiding repeated permission dialogs for the same arguments.
- Three consecutive tool-free continuations of an unfinished plan, or three
  repetitions of the same failed/replayed/unchanged-plan operation, stop with
  `no_progress`. Remaining calls are closed before settlement. This is a bounded
  recovery mechanism, not an assessment of model intelligence.
- Model requests may retry HTTP 408/429/500/502/503/504 or transient transport
  failures, up to two retries by default. Backoff is cancellable and bounded;
  numeric Retry-After is considered. A visible partial answer is not silently
  regenerated. Tools themselves are never automatically retried.
- Stop propagates the cancellation token into native HTTP and tool callbacks.
  Remaining calls in an interrupted batch receive cancellation results so that
  the next model request has a valid transcript. An already completed operation
  retains its actual result. A synchronous engine operation must finish before
  control returns to the event loop.
- The main chat checkpoints the transcript before dispatch and after each tool
  result, with run snapshots in private `projects/<project-hash>/runs/<id>.json`.
  Storage failure blocks subsequent operations and reports failure. It cannot
  roll back an operation that already happened before a later storage failure.
- On transcript loading, unanswered calls are closed with an explicit
  interruption result. They are not automatically repeated. After a crash
  between an operation and result persistence, the project needs inspection
  before a new operation is proposed. Run snapshots are evidence, not an
  automatic background-resume queue.
- Resume keeps the original user turn, restores its paused plan and confirmed
  tool results, and preserves the current draft. It does not insert a synthetic
  user message. Completed tasks cannot be replayed with Resume; older turns
  require branching. An unknown interrupted generation is not blindly resubmitted.
- Generation jobs are checkpointed before submission. Missing responses and
  interrupted `submitting` records become `submission_unknown`; Runware retains
  its locally assigned task UUID. Jobs without a provider ID require checking
  provider history. A local Stop does not claim remote cancellation or a refund.

Conversation queues, project guidance, memories, manual `/compact`, native Undo,
file recovery, generation jobs, and MCP discovery remain host services. Automatic
token-budget compaction and autonomous restart of interrupted turns are not
introduced by this change.

See [behavioral evaluation](AI_BEHAVIOR_TESTS.md) for current tests and limitations,
and [live API evaluation](AI_API_EVALUATION.md) for measured DeepSeek tool use,
and [control, integrations and project skills](AI_INTEGRATIONS.md) for settings.

## Verification of delivered APK `9a019f6`

Results on 2026-10-22. The runtime and upstream-editor rows used the upstream
Godot 4.7.2 Linux ARM64 editor locally; the native bridge row used the fork's
desktop editor compiled in CI. The first harness extraction passed 122
assertions and 80 checks in each of five editor configurations. The current
Auto/Plan source and delivered native build have these results:

| Scope | Result |
| --- | --- |
| Runtime compilation, protocols, registry, and harness behavior | 167 assertions, zero failures locally and in CI |
| Editor fixture, including discovery, scene edits, patches, recovery and unsaved-buffer protection | 142 checks in each of desktop, narrow, wide, phone_landscape, and phone_compact on upstream Godot; zero failures and normal exits |
| Native diagnostics bridge | 152 checks in each of the same five configurations with the fork compiled from `9a019f6` in CI, including Auto/Plan flow, restoration, real scene mutation/verification and native diagnostics |
| Generated embedding header | All 17 script payloads match their source bytes (including embedded icons); registry precedes its consumers and panel remains last |

Rendered reports and editor logs are in
`.ai-qa/auto-plan-final/<configuration>/`; the earlier tool-use
extraction reports remain in `.ai-qa/tool-use-final/<configuration>/`. The
editor fixture loads the current embedded-service sources in an isolated
project; the separate CI-native job rebuilds the fork's desktop editor and
runs the same fixture against it. The latest native reports are in
`.ai-qa/auto-plan-native-ci/.ai-qa/native-rendered/<configuration>/`. The delivered
APK passed package, ABI, signature and all 17 embedded-source comparisons; see
`.ai-qa/delivery-9a019f6.json`. The companion passed 9 tests and its TypeScript
build locally and in CI. Those tests use deterministic account runtimes.

The runtime suite exercises the real HTTP provider/tool/result loop against a
local protocol fixture, plus retry exhaustion, streaming failures, cancellation,
registry enforcement, replay/conflicting IDs, bounded results, concurrent-turn
rejection, checkpoint failure, and transcript repair. No live API key is used.

The editor fixture also checks structured planning, rejection of writes during
planning, tool-free intermediate answers, real execution, scene verification,
completed-plan restoration and strict Plan permissions. It drives
`panel._start_chat()` through the actual harness with a
deterministic provider. It creates a real scene node, reads the persisted run,
checks the completed transcript, undoes the scene change, and verifies Plan
blocks a model-requested mutation. These checks run through the normal chat
dispatcher, rather than calling only a mock tool executor.

Use the commands in [AI Assistant verification](AI_ASSISTANT.md#verification).
Desktop editor execution and rendered fixtures do not establish physical Android
suspend/resume behavior, device touch/keyboard input, or live subscription/model
support.

## Native coding tools

`godot_read_range` returns one-based line excerpts and a hash of the exact file
bytes read. `godot_search_code` performs bounded literal project searches with
file, line, column, and excerpt data. Hidden folders, symlinks and private project
paths retain the existing restrictions.

`godot_apply_patch` takes a project path, `expected_sha256`, and up to twenty
sequential `{old_text, new_text}` edits. Each anchor must occur exactly once,
including overlapping occurrences. No edit is written until all edits succeed.
The default is `dry_run: true`; applying requires modification permission.
Applying checks the version, refuses an unsaved open script, persists a recovery
copy, writes and verifies a temporary file, rechecks the original hash, and
renames the replacement into place. A stale/conflicting patch changes no source
bytes. Recovery continues to reject subsequent manual-file conflicts.

File changes request coalesced rescans after an active scan rather than starting
repeated scans during a batch. The editor fixture also saves its deliberately
edited test buffer before shutdown; completing assertions alone is not a passed
render run if the editor cannot exit normally.

`godot_script_diagnostics` reads a saved `.gd` file or validates an optional draft
through the new C++ `script_diagnostics` bridge. The bridge calls Godot's parser
and analyzer and returns validity, error locations, warnings and function names.
The tool adds the source hash. It does not save the draft or instantiate it.
An upstream editor without the bridge reports `native_bridge_unavailable`; it
does not substitute a guessed validation result. Native execution tests for valid
and invalid drafts are included in the fixture for a rebuilt fork.

MCP tool results now preserve text and `structuredContent`, validate supported
output schemas, and propagate `isError` as `mcp_tool_error`. Up to four bounded
PNG/JPEG/WebP images are decoded and passed as model attachments, separate from
the JSON text transcript. Resource links and embedded text resources retain
their data; audio and unsupported binary resources report an explicit unsupported
content error. No remote operation is automatically retried on such an error.
