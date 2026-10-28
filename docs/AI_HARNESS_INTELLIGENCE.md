# Project knowledge, diagnostics, recovery and acceptance evidence

Source implementation, 28 October 2026. These features extend the native Godot
harness; no external CLI or Linux runtime is required. They are not in the
currently delivered APK `1c7c777`.

## Project facts

`godot_project_map` indexes literal dependencies and top-level GDScript symbols
without loading scripts or instantiating resources. It returns hashes, source
locations, reverse dependents within the indexed scope, missing files and
unresolved UIDs. Project settings include literal main-scene and autoload paths.
Comments and quoted code examples do not become GDScript dependencies.

The private `project-map.json` cache survives restarts and is always marked stale
until refreshed. Content hashes reuse unchanged parse results. At turn start,
and before the next provider request after a project change, the host refreshes
the map. Editor filesystem changes mark it stale. Explicit tool queries refresh
their requested file or directory, allowing large projects to be inspected in
parts instead of repeatedly scanning the same global prefix.

Each scan is bounded to 600 files, 4 MB of text and 4,000 directory entries;
individual text files over 1 MB are metadata-only. Each file retains at most
80 symbols and 100 dependencies; reaching either cap marks coverage partial. Hidden directories,
`node_modules`, recovery folders and symbolic links are skipped. Cancellation
retains the previous cache. Results expose `coverage_scope`, `partial` and
`stale`; dynamic paths, binary contents and dependents outside that scope remain
unknown. The map is not a complete semantic graph or an AST index.

## Unified observations

`godot_diagnostics` combines scoped native parser results, missing literal
references, editor diagnostics and running-game errors. It never starts a game
or executes a project script. Native error-handler buffers retain up to 128
events per process, including shader errors and warnings. Runtime status retains
the old error-string field for compatibility and adds structured diagnostics.

The collector reports parser/runtime availability, scripts checked, source
coverage and truncation. Without the rebuilt native editor bridge it reports
that limitation and can use visible Output as a partial fallback. A paused or
unresponsive game can make runtime collection unavailable; that is not a clean
runtime verdict. Native events retain available file, line, function and message
data. Stack text is retained when actually observed in Output; no stack is
invented for events that lack one.

Private `diagnostics.json` stores bounded source-specific observations. Duplicate
issues are grouped with occurrence counts; missing resources group referring
files. Fresh successful parser checks clear only that source. Edits and restart
make old observations stale. Unobserved sources, dynamic dependencies, native
process crashes and a missing bridge cannot be declared clean.

## Adaptive recovery

Tool results receive recovery guidance for stale handles, schema/type errors,
path errors, patch conflicts, parser failures, refused permissions, uncertain
external jobs and invalid verification evidence. Guidance identifies a next
inspection or correction; it never automatically retries a write or paid job.

After three identical successful inspections without a project change, the
harness supplies an internal change-of-strategy instruction and journals a
recovery event. Six repeated identical inspections settle as `no_progress`.
Changed measurements and actual mutations remain separate from these loops.
Normal progressing work still has no global step ceiling; Stop and existing
permission boundaries remain active.

## Acceptance criteria and evidence

An execution plan can declare up to 24 criteria in `task_update.criteria`:

```json
{
  "tasks": [{"step": "Implement and verify scoring", "status": "in_progress"}],
  "phase": "executing",
  "criteria": [{
    "id": "score",
    "description": "Collecting the objective reaches the target score",
    "kind": "interaction",
    "paths": ["res://scripts/player.gd"],
    "check": {"pointer": "/until_met", "op": "eq", "expected": true}
  }]
}
```

The interaction check must use a real `playtest_act` whose `until` expresses the
required game condition and whose probes measure it. It must not use an
unrelated or trivially true condition. Kinds are `inspection`, `syntax`,
`runtime`, `interaction` and `visual`. Runtime/interaction criteria require a
measured assertion. Assertions use JSON pointers inside the actual tool result
and `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `contains` or `nonempty`.

The executor issues `verification_evidence.id` only for recognized observations.
The model calls `task_check` with the criterion ID and those evidence IDs. A read
does not satisfy a syntax check, input dispatch does not establish interaction,
a valid unsaved draft does not verify different saved code, and a patch preview
does not verify an unapplied change. Partial/stale map coverage cannot establish
absence. Missing diagnostic capabilities cannot establish a clean verdict.

Evidence is bound to the project revision and relevant saved-file hashes.
Project writes, Undo/Redo version changes, changed criteria and restart invalidate
it. Source-read and parser hashes must still match the saved bytes when evidence
is issued, closing the read-to-record race. External file edits are detected when checking the hashes. Paths larger than
4 MB require a narrower verification strategy rather than a metadata-only pass.
Criteria survive Resume, but observations of a previous game process must be
collected again. Checkpoints persist requirements and pending/verified IDs;
evidence bodies remain transient and do not embed image data.

Mutating tasks cannot finish by omitting the final `task_update`: the direct
harness checks the host's completion condition, requests missing verification,
and settles blocked if the model repeatedly claims completion without evidence.
The optional companion continuation path also checks that host condition.
Read-only conversation and proposed plans remain usable without execution proof.

This checks evidence provenance, types, scope, freshness and declared assertions.
It cannot prove that model-written criteria cover every sentence of a user's
request, or that a chosen gameplay assertion is meaningful. Independent scenario
evaluation remains necessary.

## Verification evidence

Runtime: **654 assertions / 0 failures**. Full rendered narrow editor suite:
**697/0**. Dedicated intelligence scenario in phone_compact: **52/0**. Tests
cover persistent/scoped mapping, late UID resolution, corrupted caches, diagnostic
coverage, source-read races, proof freshness, real writes/reads, native Undo/Redo
signals and the complete provider→tool→evidence→completion path.

Runtime and editor reports for this iteration are under
`.ai-qa/intelligence-20261028/`. Native C++ syntax/type checks are separate from
linking the editor, compiling an APK, physical Android input and live API tests.
