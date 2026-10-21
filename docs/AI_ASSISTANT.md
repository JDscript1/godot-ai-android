# Godot AI Android

This fork starts at `4.7.2-stable` (`ed1daf0bf001b61586d9930840f2f1394092c079`).
The Android application ID is `com.jdscript.godotai` (debug builds append `.debug`).
It installs alongside upstream Godot. Engine and third-party license notices are retained.

## Configuration

Open **Editor Settings → General → AI Assistant**, or select the **AI Assistant**
tab at the top right of the editor, next to **Asset Store**. Its **Setări** button
opens the same global configuration window.

- **Furnizori:** select an issuer or paste a distinctive API key. Generic keys such
  as `sk-...` require an issuer selection. Save, then test/list models. Manual model
  IDs remain available for servers without a listing endpoint.
- **Abonamente:** use **Continue with ChatGPT** for the native SIWC flow. Claude,
  Copilot and Kimi use the optional companion on your own computer/server.
- **Generare:** configure Runware with your key and model, or an existing ComfyUI
  server. Import a workflow exported in API format, bind its prompt/reference fields
  and output node, then validate the server. PNG and self-contained GLB 2.0 are supported.
  Runware's public catalog lists model IDs; it does not validate your credentials.
  Its image form supports text-to-image. For 3D, TRELLIS.2 requires a reference image;
  Rodin, Meshy, Tripo and Hunyuan accept text or the supported reference binding.
  Models requiring extra inputs, such as a segmentation mask, need a configured
  ComfyUI workflow. A cancelled wait retains the remote job for later retrieval.
- **MCP:** add a Streamable HTTP endpoint and optional Bearer token. For stdio,
  configure the process in the companion and connect to its `/mcp/<name>` URL.
- **Automatizări:** save a task's instructions and active provider, then run it manually.

HTTP is opt-in per local connection. `127.0.0.1` means this Android device; a server
on your computer needs its reachable LAN address or authenticated HTTPS endpoint.
No inference runtime or generation model is installed automatically.

## Execution and recovery

Analysis is the initial mode. Both confirmation and autonomous modes require
enabling **Control complet pentru această sesiune**. Confirmation mode displays
each modifying/external operation before dispatch. Turning permission off also
gates generic object calls and external MCP calls.

Scene/property edits use Godot Undo where supported. File replacements retain
recovery copies and journal indices. Generic method calls may have effects that
Godot cannot undo; they are always treated as modifications. Internal/native
methods that are not reflected require dedicated adapters; this release does not
claim every private engine function has a tested AI wrapper.

Stopping cancels native HTTP calls and asks companion runtimes to interrupt.
Remote generation may continue at the provider; generation jobs retain their IDs
and can be refreshed after an Android suspend/restart. A workflow running on a
shared ComfyUI server is never globally interrupted on behalf of another job.

## Architecture

`modules/ai_assistant` contains the C++ editor plugin, global settings inspector,
secret-store bridge and embedded GDScript services. Scripts are injected into the
editor in dependency order and are not installed into `res://` on disk. No project
addon, hosted gateway, API key or token is embedded in the APK or game exports.

Android credentials are encrypted with AES-GCM under a non-exportable Android
Keystore key. Desktop development builds use encrypted files and an owner-only
local key. Public profiles hold IDs, endpoints, model metadata and workflow
configuration. Histories, generation artifacts and operation journals are local
and separated by project. Normal context and logs redact stored credentials.

The companion's selected upstream files and hashes are recorded in
`tools/ai-companion/PROVENANCE.json`; copied MIT notices remain beside them.
Original Godot Agent/Hydra-Go-3D worktrees were not edited.

## Verification

Run the embedded-runtime tests with an upstream or forked 4.7.2 editor binary:

```sh
python modules/ai_assistant/tests/run.py --godot /absolute/path/to/godot
# Requires xvfb-run and a working OpenGL software driver on headless Linux:
python modules/ai_assistant/tests/render.py --godot /absolute/path/to/godot
cd tools/ai-companion
npm ci
npm test
npm run build
```

On Termux with a Debian proot installation, add `--proot` to the Python commands
and use the official Linux arm64 editor path. Rendered evidence is saved under
`.ai-qa/rendered/{desktop,narrow,wide}` with screenshots, reports and editor logs.

The `Godot AI Android` GitHub workflow also compiles the native Android arm64
editor and verifies the APK signature, package metadata, ABI and SHA-256 hash.
Only the phone/tablet APK `android_editor-android-debug.apk` is delivered.
The personal fork uses the Actions secret `GODOT_AI_DEBUG_KEYSTORE` to preserve
the debug signing identity across updates. Other forks may configure their own
base64-encoded development keystore, or receive an ephemeral runner debug key.
For local builds, `GODOT_AI_DEBUG_KEYSTORE_FILE` selects a development keystore
with the standard `androiddebugkey` alias and `android` debug passwords. CI also
compares the APK certificate with that keystore before uploading an artifact.
This is a development build; no production signing key is included in source.

Evidence must be distinguished:

| Area | Current verification |
| --- | --- |
| Embedded scripts, URL/path handling, tool modes, HTTP/SSE, multi-turn calls, MCP pagination, ComfyUI PNG/GLB download and real Godot GLB parsing | 97 automated assertions passed locally and in CI with official Godot 4.7.2; includes conversation migration/cache, provider isolation, multimodal requests, WAV conversion and concurrency limits; provider responses are deterministic fixtures |
| Companion authentication boundary, SDK tool relay, cancellation and stdio MCP | 9 tests passed with deterministic runtimes, including independent child sessions, attachments and context usage; TypeScript build passed |
| Panel and settings rendering, node/property changes, Undo/Redo, script attachment/calls, scene saving and file recovery | 38 checks passed at each requested resolution of 1280x900, 480x900 and 1920x1080 with upstream Godot; includes queue/model retention, independent approvals and rollback conflicts. Godot may enforce a larger minimum window on the narrow display |
| Native fork main screen, desktop vault, game screenshot/input/watchdog and internal-script scene saves | 46 checks at each of the three resolutions passed using the fork compiled from `66cd1fb`; [native build and rendered evidence](https://github.com/JDscript1/godot-ai-android/actions/runs/39640190502) |
| Android C++/Kotlin integration and APK | [Build 66cd1fb passed](https://github.com/JDscript1/godot-ai-android/actions/runs/39640190502), including signature, persistent signing identity, phone package and ARM64 library checks; all 12 embedded script sources were matched to the downloaded native library |
| Physical Android installation, touch, Keystore and suspend/resume | Device verification pending; desktop rendering does not establish these |
| ChatGPT, Claude, Copilot and Kimi account logins | User-authorized live account checks required |
| Runware and local ComfyUI image/GLB generation | Live configured-provider checks required |
| Real Ollama/LM Studio coding and tool use | Reachable configured-model checks required |

On 2026-10-21, the public Runware catalog was also fetched successfully through
the module's real Godot HTTP transport (six 3D choices after filtering the
mask-dependent model). This establishes catalog access only; no account or
credit-consuming generation was used for that check.

The tested APK source is `66cd1fbb423bd1d246a1387f2f74dc3d82fe6e40`.
Download its `Godot-AI-Android-arm64-66cd1fbb423bd1d246a1387f2f74dc3d82fe6e40`
[artifact](https://github.com/JDscript1/godot-ai-android/actions/runs/39640190502/artifacts/12364857731)
from the build above. The APK is 144,796,977 bytes; its SHA-256 is
`cc5bc31dc3b68f9b79cf8abac22a74e6c2034f84579dbe91d1d09b8f78e6795e`.
The delivered phone copy is `Download/Godot-AI-4.7.2-arm64-66cd1fb-debug.apk`,
with a matching `.sha256` file. Its signature, checksum, package, ABI, Android
voice declarations/classes and exact embedded AI sources were checked locally.
The persistent development certificate SHA-256 is
`2e0a80969c099f7ff72bfe0c0cd33d98ebdd0e64bbf9729294df0b11665fcab5`.
The earlier `db300bd` APK remains in Download. Later documentation-only commits
do not change the APK's tested source.

Native desktop verification runs under Xvfb/Mesa. Nonfatal Vulkan-probe and X11
window warnings can occur in this virtual display; this is not physical-device
rendering proof. The test fails on embedded-script execution/save errors.
Playtest checks use a small fixture scene and direct bridge calls. Actual model-led
playtests, subscription authentication and hardware microphone recording require
configured live services/device checks.

The native tool layer exposes scene and script editing, files with recovery,
resources/materials, project/editor settings, animation players, run/stop,
Output/Debugger text and semantic editor controls. Reflection supplies methods,
properties and signals for classes and discovered object handles. This provides
general editor access, while unreflected/private C++ operations need explicit
adapters. The test counts above cover the exercised paths, not every engine method.

## Official protocol references

- [Godot Android builds](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_android.html)
- [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ChatGPT plan inference limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [ComfyUI routes](https://docs.comfy.org/development/comfyui-server/comms_routes)
- [Runware task polling](https://runware.ai/docs/models-api/task-polling)
- [Runware TRELLIS.2](https://runware.ai/docs/models/microsoft-trellis-2)
- [Runware Rodin Gen-2](https://runware.ai/docs/models/hyper3d-rodin-gen-2)
- [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)

## Native chat workspace

The AI main screen is registered immediately after Asset Store. Scene,
FileSystem and Inspector docks stay available. The native chat uses a graphite
surface and violet/blue gradient; history collapses when the available workspace
is narrower than 900 logical pixels. The message column is limited to 760 logical
pixels. There are no embedded web pages.

Conversations are stored per project, with search, favorites, archive, rename,
fork and Markdown export to the clipboard. Existing `history.json` is imported
once and preserved. Images are cached as separate private files. Switching the
provider/model keeps the conversation and labels responses with their origin;
provider-specific signed/reasoning blocks are retained only for their originating
profile and model. Model selection groups API, subscription and local profiles.

The searchable settings window has General, Providers, Subscriptions, Generation,
MCP, Automations, Journal, Agent, Voice and Playtesting pages. `@` opens project
file/folder references, `$` opens scene-node references and `/` lists commands.
Images can be attached to supported multimodal providers. Context counters use
provider-reported usage when available. `/compact` writes a continuation summary
while preserving the original conversation.

Plan mode permits inspection and presents an Apply plan button, which switches
to confirmation mode. Messages sent during a turn enter a queue with their own
provider/model selection. Stop pauses the queue; `/resume` continues it and
`/steer <instructions>` interrupts the current turn before using the new request.
AGENTS.md guidance and editable project memories are included in context.

Explore and General children inspect independently and return proposed changes;
the parent applies project writes. Cloud profiles allow two children; local and
companion profiles allow one. Companion protocol 2 creates a separate SDK object
and session for each child, so a parent waiting for a tool can receive its result.
Authentication remains shared through the existing local account stores.

The Changes/Undo action shows before/after file contents and offers restoration.
It refuses restoration when file hashes or native scene Undo history changed
subsequently. Generic method calls, external operations and arbitrary setting
changes are not reversible checkpoints.

## Playtest and voice boundaries

Playtest uses the fork's native debugger bridge to inspect the running scene,
capture its actual viewport and send bounded InputMap/key/mouse/touch events.
It never substitutes an editor screenshot for a game frame. The default budget
is 30 steps / 180 seconds. Held input is released on Stop and after a native
2.2-second watchdog; each requested hold is limited to two seconds. Screenshots
and child reports are retained in the project's private AI data directory.
Use a vision-capable model in Playtesting settings or a model whose live catalog
declares image input. A disconnected debugger or unsupported model is reported
as blocked rather than a successful playtest.

Voice supports Android SpeechRecognizer, preferring an installed on-device
service, and a separately configured Whisper-compatible transcription endpoint.
Endpoint recording is capped at 60 seconds and encoded as mono 16 kHz PCM WAV.
The transcription key is stored separately from chat credentials. Transcripts
are inserted into the composer for editing and require an explicit send action.
Stopping or suspending cancels microphone capture. Android permissions, the
installed recognition service, hardware audio and live endpoints still require
physical-device validation; desktop rendering does not establish those results.
