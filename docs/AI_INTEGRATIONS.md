# Control, integrations and project skills

Current source, compiled-package and delivery evidence are recorded in
[PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md). OAuth protocol implementation is
separate from registering the project's GitHub app and verifying live login.

## Control

The work mode menu contains Auto, Default and Plan only. General contains YOLO, chat
placement (center/left/right), and completion sounds with a preview action.
Preferences save immediately. YOLO defaults to off: Auto and Default ask before each
modifying/external operation. Enabling YOLO permits automatic operations;
Plan remains read-only. Applying a plan never changes the YOLO preference.
Execution and history budgets remain internal, outside General.

The native plugin moves the existing panel through Godot's `EditorDock` manager;
it does not create another conversation or another agent. Returning to center
restores the main tab. Docked chat stays available beside the editor, and opening
its tab restores the prior workspace. Moving it is refused during active work or
voice capture. The top expand action temporarily centers docked chat and restores
its prior dock on collapse, retaining the saved position. Docked expansion also
waits for active work to finish. Preferences survive restart. The C++ bridge compiled and ran in the native fork editor fixture: 324 checks
in each of five display configurations, including real dock moves. Physical
Android interaction and sound output remain unverified.

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

Integrations contains GitHub, desktop Blender CLI, Skills and saved tasks.
MCP servers and image/3D generation have their own settings pages. The duplicate
Services card and its shortcuts have been removed in source after APK `db5343b`.

GitHub and Blender configuration is stored per project in the editor's private
`projects/<hash>/integrations.json`. GitHub tokens use the existing encrypted
vault/Android Keystore and never enter that JSON, model instructions or logs.
The OAuth Client ID is public editor configuration, shared across projects.
Changing repositories in one project does not configure another project.

- GitHub uses native HTTP, without `git`, `gh` or a shell. **Sign in with GitHub**
  starts Device Flow, displays a public code and opens GitHub in the browser. Confirm
  the code there, then choose a repository from the paginated account list or enter
  `owner/repository` manually. The account is verified through `/user` before its
  token is saved. Refusal, expiry, cancellation and `slow_down` are handled; a late
  response cannot reconnect a cancelled/disconnected account. Manual tokens remain
  available under **Configurare autentificare**. Public repositories can still be
  read without a token. **Verifică** distinguishes account login from public access.
- **One-time setup is still required:** this project has no registered GitHub OAuth
  app/Client ID yet. Register our own app, enable **Device Flow**, and put its public
  Client ID in **Configurare autentificare**. No Client Secret is requested or shipped.
  The link opens GitHub registration; it does not register an app automatically.
  Once the public ID is available it can also be supplied as the fork's default.
  Third-party application IDs and developer `gh` credentials are never reused.
- Default scopes are `read:user public_repo`; enabling private repositories requests
  `repo`. GitHub shows the requested permissions during approval. Device Flow can be
  cancelled in the editor; local disconnect erases the token, and server-side OAuth
  grants can be revoked in GitHub settings. Disconnect does not claim to revoke the
  remote grant. Account selection alone does not grant the agent permission to publish.
- `github_read` inspects repository metadata, branches, issues, pull requests and
  file/directory contents. Lists are paginated and bounded; file content includes
  its revision. `github_create_issue` publishes only for an explicit request under
  Auto/Default/Plan and YOLO/confirmation rules. Git clone, commits, push and PR
  creation are not implemented by these adapters.
- Blender CLI appears only on Windows/Linux, when Blender is already installed.
  Select its executable and verify the version. `blender_run` starts Blender
  directly with an argument array, no shell, using background/factory mode,
  disabled automatic file scripts and an explicit project Python script.
  Optional `.blend` input is project-scoped. A nonblocking process loop captures
  bounded output, supports Stop/timeout and reports nonzero/Python exit status
  as failure. Scripts have Blender's desktop filesystem access. Android has no
  Blender CLI control or tool, and the APK never installs Blender.
- Existing manually launched saved tasks remain under Integrations → Sarcini.
  This adds no autonomous scheduler.

Authentication follows [GitHub OAuth Device Flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow).
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
adapter read the public `godotengine/godot` repository. Device Flow protocol tests use local HTTP fixtures, including pending/slowdown,
refusal, expiry, cancellation, invalid account tokens and repository listing.
No live issue was created and no private GitHub account was connected; real OAuth
login still requires app registration and user browser authorization. Rendered editor fixtures cover
permissions, skills/recovery, memory conflicts, context, settings and dock moves.
Exact counts and evidence are recorded in [PROGRES_SI_PLAN.md](../PROGRES_SI_PLAN.md).
Windows execution, physical Android and actual audio playback remain unverified. The current source/build/delivery status is recorded in the progress document.
