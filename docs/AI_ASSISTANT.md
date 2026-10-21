# Godot AI Android

This fork starts at `4.7.2-stable` (`ed1daf0bf001b61586d9930840f2f1394092c079`).
The Android application ID is `com.jdscript.godotai` (debug builds append `.debug`).
It installs alongside upstream Godot. Engine and third-party license notices are retained.

## Configuration

Open **Editor Settings → General → AI Assistant**. Each category opens the global
configuration window, also reachable from the **AI Assistant** bottom panel.

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
`.ai-qa/rendered/{desktop,narrow}` with screenshots, reports and editor logs.

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
| Embedded scripts, URL/path handling, tool modes, HTTP/SSE, multi-turn calls, MCP pagination, ComfyUI PNG/GLB download and real Godot GLB parsing | 73 automated assertions passed locally with official Godot 4.7.2; provider responses are deterministic fixtures |
| Companion authentication boundary, SDK tool relay, cancellation and stdio MCP | 7 tests passed with deterministic runtimes; TypeScript build passed |
| Panel and settings rendering, node/property changes, Undo/Redo, script attachment/calls, scene saving and file recovery | 22 checks passed at each of 1280x900 and 480x900 under the real Linux editor with a fixture secret store |
| Android C++/Kotlin integration and APK | [Initial native build passed](https://github.com/JDscript1/godot-ai-android/actions/runs/39599251683); signature and phone package checked locally. The latest source still requires its matching CI artifact |
| Physical Android installation, touch, Keystore and suspend/resume | Device verification pending; desktop rendering does not establish these |
| ChatGPT, Claude, Copilot and Kimi account logins | User-authorized live account checks required |
| Runware and local ComfyUI image/GLB generation | Live configured-provider checks required |
| Real Ollama/LM Studio coding and tool use | Reachable configured-model checks required |

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
