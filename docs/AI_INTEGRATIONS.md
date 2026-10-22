# Control, integrations and project skills

These are source changes after APK `9a019f6`. No APK was rebuilt for this stage.

## Control

The work mode menu contains Auto and Plan only. General contains YOLO, chat
placement (center/left/right), and completion sounds with a preview action.
Preferences save immediately. YOLO defaults to off: Auto asks before each
modifying/external operation. Enabling YOLO permits automatic operations;
Plan remains read-only. Applying a plan never changes the YOLO preference.
Execution and history budgets remain internal, outside General.

The native plugin moves the existing panel through Godot's `EditorDock` manager;
it does not create another conversation or another agent. Returning to center
restores the main tab. Docked chat stays available beside the editor, and opening
its tab restores the prior workspace. Moving it is refused during active work or
voice capture. The top expand action temporarily centers docked chat and restores
its prior dock on collapse, retaining the saved position. Docked expansion also
waits for active work to finish. Preferences survive restart. Native C++ was checked for syntax;
the rendered fixture exercises real editor docks with its test EditorPlugin.
Execution of the newly compiled C++ bridge remains pending.

A small ring and percentage stay visible in the bottom toolbar. Input usage is
compared with a known model capacity; estimated values are marked and unknown
capacity displays a dash. Hovering gives token details. Zero-valued catalog
capacity does not overwrite an actual capacity supplied by the provider. Usage
from a different selected model/conversation is not reused as current context.

The completion chime is generated as a short native PCM stream. Sounds default
to off and play on successful final completion, once the message queue is empty;
failed/cancelled/unfinished execution does not play the completion sound. The
preview action works independently of the preference. Hardware playback needs
separate device verification.

## Integrations

GitHub and Blender configuration is stored per project in the editor's private
`projects/<hash>/integrations.json`. GitHub tokens use the existing encrypted
vault/Android Keystore and never enter that JSON, model instructions or logs.
Changing repositories in one project does not configure another project.

- GitHub uses native HTTP, without `git`, `gh` or a shell. Configure
  `owner/repository`, optionally save a token and enable the connection.
  `github_read` inspects repository metadata, branches, issues, pull requests and
  file/directory contents. Lists are paginated and bounded; file content includes
  its revision. `github_create_issue` is an external mutation intended for an
  explicit user request and follows Auto/Default/Plan and YOLO/confirmation rules.
  It does not implement git clone, commits, push or PR creation.
- Blender CLI appears only on Windows/Linux, when Blender is already installed.
  Select its executable and verify the version. `blender_run` starts Blender
  directly with an argument array, no shell, using background/factory mode,
  disabled automatic file scripts and an explicit project Python script.
  Optional `.blend` input is project-scoped. A nonblocking process loop captures
  bounded output, supports Stop/timeout and reports nonzero/Python exit status
  as failure. Scripts have Blender's desktop filesystem access. Android has no
  Blender CLI control or tool, and the APK never installs Blender.
- Existing MCP and image/3D generation pages are linked from Integrations.
  Existing manually launched saved tasks remain under Integrations → Sarcini.
  This adds no autonomous scheduler.

The adapters follow [GitHub repository contents](https://docs.github.com/en/rest/repos/contents),
[GitHub issues](https://docs.github.com/en/rest/issues/issues) and
[Blender CLI arguments](https://docs.blender.org/manual/en/5.4/advanced/command_line/arguments.html).

## Skills and memory

Integrations → Skills lists portable project instructions in
`res://.godot_ai/skills/<id>/SKILL.md`. The manager creates, edits, enables,
disables and deletes skills; deletion uses native file recovery. Revisions are
checked before updates/removal, and project-path/symlink rules still apply.
Enable flags are local per project. Disabled skills are absent from agent context
and agent reads. Skills are text instructions; they never execute automatically
or grant additional tool permissions.

The agent receives the enabled catalog and uses `skill_list`, `skill_read` and
`skill_save` through normal discovery and permission checks. It can save a concise
reusable workflow after checking actual results. It cannot save a skill in Plan
mode or bypass confirmation when YOLO is off. Learning quality remains dependent
on the configured model; tool tests do not establish that every self-written
procedure is correct.

AGENT.MD edits `res://AGENT.md`, included alongside existing `AGENTS.md` guidance.
Legacy private memories prefill the editor when the project file is absent;
the file is created only on explicit Save or an authorized memory tool call.
Save checks the original revision and preserves recovery; Reload refreshes an
externally edited file. Existing `AGENTS.md` is preserved.

Jurnal is a read-only console with chronological request/tool/result/settlement
entries, live follow, search and copy. Stored entries are redacted. The display
is bounded to prevent large tool results from freezing the editor; the project
journal retains its existing 1,000-entry limit.

## Verification boundary

Local runtime checks include a deterministic GitHub HTTP fixture and a real
Blender 4.3.2 process on Debian ARM64: Python → GLB → Godot import, Python errors,
cancellation and timeout. A separate unauthenticated request through the native
adapter read the public `godotengine/godot` repository. No live issue was created
and no private GitHub account was connected. Rendered editor fixtures cover
permissions, skills/recovery, memory conflicts, context, settings and dock moves.
Exact counts and evidence are recorded in [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).
Windows execution, the recompiled native dock bridge, physical Android and actual
audio playback remain unverified. The last delivered APK is unchanged.
