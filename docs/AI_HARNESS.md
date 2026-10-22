# Built-in Godot agent harness

The fork owns its agent harness. `modules/ai_assistant/runtime/harness.gd` runs
inside the Godot editor using engine objects and native HTTP adapters. It is
embedded in the editor binary by `runtime_builder.py`, alongside the other
editor services. It does not install or start Termux, Node.js, Python, a shell,
Pi, OpenCode, or a separate agent server on the user's device.

This describes the source implementation added on 2026-10-22. The previously
delivered APK built from `e98ddb7` predates this extraction and has not been
replaced by this change.

## Execution boundaries

```text
Native chat / queued user requests
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
`max_retries`, `retry_delay_ms`, and `deferred_tools`. The supplied messages array receives the
finalized assistant and tool messages. Hooks are:

| Hook | Responsibility |
| --- | --- |
| `complete(context, tools, cancel, delta)` | Call a provider through its native adapter |
| `execute(name, arguments)` | Validate permissions and execute an allowed tool |
| `context()` | Optionally rebuild project context before each model step |
| `redact(text)` | Remove known credentials from stored/output data |
| `checkpoint(snapshot)` | Persist the transcript and run state; `false` stops further execution |

The `event` signal reports state changes, request attempts, streamed text,
finalized messages, tool starts/results, retries, and settlement. Tool-result
events distinguish a dispatched call from a recovered result or blocked call.
Provider-reported usage remains available to the chat.

Outcomes distinguish `completed`, `failed`, `cancelled`, and `limited`.
`completed` means that the model ended its tool loop; it is not independent
proof that the user's whole project works. Step and output limits never report
completion. Request, retry, step, and dispatched-tool counts are separate.

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
- Only tools in the current run's registry can reach the dispatcher. Analysis
  and Plan therefore cannot gain a mutation tool by naming it in a model reply.
  The existing editor permission checks still run before an actual operation.
- A response must have matching assistant/tool-call data, dictionary arguments,
  nonempty unique call IDs, and at most 64 calls. A reused ID with a different
  name or arguments fails before any call from that response is executed.
- A recorded call ID with matching arguments receives its saved result instead
  of executing again. This ledger is reconstructed from the supplied transcript.
  It is deduplication by call ID, not a guarantee that semantically identical
  actions with newly generated IDs run only once.
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

Conversation queues, project guidance, memories, manual `/compact`, native Undo,
file recovery, generation jobs, and MCP discovery remain host services. Automatic
token-budget compaction and autonomous restart of interrupted turns are not
introduced by this change.

## Verification

Local results on 2026-10-22, using the upstream Godot 4.7.2 Linux ARM64 editor.
The first harness extraction passed 122 assertions and 80 checks in each of five
editor configurations. The subsequent tool-use extension has these results:

| Scope | Result |
| --- | --- |
| Runtime compilation, protocols, registry, and harness behavior | 149 assertions, zero failures |
| Editor fixture, including discovery, scene edits, patches, recovery and unsaved-buffer protection | 91 checks in each of desktop, narrow, wide, phone_landscape, and phone_compact; zero failures and normal exits |
| Native diagnostics bridge | Android-configured C++ syntax/type check; execution requires the rebuilt native editor |
| Generated embedding header | All 14 script payloads match their source bytes; registry precedes its consumers and panel remains last |

Rendered reports and editor logs are in
`.ai-qa/tool-use-final/<configuration>/`. The editor fixture loads the
current embedded-service sources in an isolated project; it does not rebuild
the native Android or desktop fork binary.

The runtime suite exercises the real HTTP provider/tool/result loop against a
local protocol fixture, plus retry exhaustion, streaming failures, cancellation,
registry enforcement, replay/conflicting IDs, bounded results, concurrent-turn
rejection, checkpoint failure, and transcript repair. No live API key is used.

The editor fixture drives `panel._start_chat()` through the actual harness with a
deterministic provider. It creates a real scene node, reads the persisted run,
checks the completed transcript, undoes the scene change, and verifies Analysis
blocks a model-requested mutation. These checks run through the normal chat
dispatcher, rather than calling only a mock tool executor.

Use the commands in [AI Assistant verification](AI_ASSISTANT.md#verification).
Desktop editor execution and rendered fixtures do not establish physical Android
suspend/resume behavior, new APK packaging, or live subscription/model support.

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
