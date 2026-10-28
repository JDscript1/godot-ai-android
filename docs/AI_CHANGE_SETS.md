# Coordinated file changes and recovery

Source implementation, 28 October 2026. Runs within Godot's direct-provider
harness, without an external CLI or Termux dependency. The currently delivered
APK `1c7c777` does not include these source changes.

The agent can prepare dependent edits together using `godot_changes_prepare`,
inspect the returned diffs, then call `godot_changes_apply`. Existing files
require the SHA-256 obtained by reading them; new files require `missing`.
`godot_changes_status` inspects a set, or lists up to 64 recent manifests.
`godot_changes_rollback` explicitly restores verified recovery copies.

Each set accepts 1–16 UTF-8 text files, at most 1 MB per file and 4 MB combined
original/draft bytes. These are per-operation bounds, not an agent step limit;
larger tasks can use successive reviewed sets. Writes and deletions are supported.
Duplicate/overlapping paths, symbolic links, traversal, binary files, protected
editor files and direct `project.godot` changes are rejected. Settings continue
through their dedicated tool.

## Preparation and approval

Preparation reads and checks all originals before saving a manifest, original
copies and drafts under the project's private recovery directory. It does not
write project files or invalidate previously collected acceptance evidence.
Diffs are bounded to 4,000 characters per file and 24,000 per result, with
truncation and diff precision exposed. Large diff computations also obey the
existing diff engine's limits. Full staged bytes remain in private storage.

The existing permission dialog displays the actual diffs when applying or
rolling back. A dependent set is approved together; single-file hunk selection
continues to work through the existing write/patch tools. Plan mode may prepare
and inspect a set, but cannot apply or roll it back. Read-only child agents can
prepare/inspect; their existing write prohibition remains in effect.

Open script buffers are checked for unsaved edits at preparation, preflight and
each commit. Open scenes use a new native `scene_is_unsaved` bridge; on a stock
editor without this bridge, open scene files are conservatively blocked. Native
draft syntax observations are advisory against the current on-disk project;
references to other staged files may not resolve yet. They are not saved-project
verification. Parser diagnostics do not execute staged scripts.

## Commit and compensation

Before the first write, every original hash and staged blob is checked again.
Each write has a durable intent in the private manifest before its temporary
file is renamed into place. The executor yields between files so Stop and user
input can be processed. It rechecks the target at each commit.

Stop, I/O failure or a journal error triggers compensating rollback. A file is
restored only when its actual content still matches the set's output. Later
user edits, unsaved buffers and changed recovery copies become explicit
conflicts; unaffected members of a valid manifest can still be restored. Paths
that have become symbolic links or a structurally invalid manifest block the
whole operation until those paths/journal are inspected. Only empty
directories recorded as missing at commit are removed. Temporary files with
recorded ownership and a matching known hash can be cleaned up during recovery;
an unknown partial or edited temporary file is retained as a conflict.

This is not a globally atomic filesystem transaction or a cross-process lock.
Other observers can see an intermediate state between files; an external writer
can race the final hash check and rename. Native object/scene Undo operations,
provider jobs and plugin installation are outside the file set. Follow a set
with saved-script diagnostics, dependency checks, scene reload as needed, and
actual runtime/acceptance tests. Engine crashes, power loss and disk corruption
have not been proven recoverable on a physical Android device.

## Restart, history and evidence

A fresh runtime reads manifests for the current project only and compares them
with actual file hashes. `applying` or `rolling_back` without an active executor
is reported as `interrupted`. Status never resumes writes. Applying an
interrupted or rolled-back set is rejected; inspect it and use rollback instead.
Repeated apply on an unchanged completed set does not write again. A completed
rollback is idempotent and does not touch later edits.

Touched members join the existing per-turn recovery journal and change summary.
Status also repairs missing per-turn entries from the set manifest after an
interruption. A failed turn-journal update is reported separately from the
durable set journal. The existing Restore turn action can restore these entries;
subsequent set status reports the actual before/after/conflict positions.

Successful mutations and failed applications that reached a write intent both
invalidate project knowledge, diagnostics and acceptance evidence. Compensation
does not reuse old proof merely because the restored bytes match. The agent must
collect fresh observations before claiming completion. Recovery guidance points
to the existing set and actual files; it does not retry writes automatically.

## Verification

Final checks: **703 runtime assertions, 716 full narrow editor checks and 60
phone_compact scenario checks, all with zero failures**. Both approval captures
were visually inspected. All 34 embedded scripts match their source bytes.
Evidence for this source iteration is under `.ai-qa/changesets-20261028/`.
Runtime tests exercise actual temporary-project files, hash conflicts, an I/O
failure after the first commit, Stop between files, later manual edits, corrupt
drafts, deletion, empty files and recovery from a simulated process-death
checkpoint using a new coordinator instance. The checkpoint simulation is not
an actual forced Android process kill.

Rendered editor tests use the actual panel/tool executor, Plan permissions,
acceptance invalidation including failed/compensated application, Restore turn
and the approval dialog. C++ syntax/type checks cover the new scene-state
bridge; the bridge requires a rebuilt editor for execution. Test totals and
remaining limitations are recorded in `PROGRES_SI_PLAN.md`. No live provider,
generation credits or APK build are involved.
