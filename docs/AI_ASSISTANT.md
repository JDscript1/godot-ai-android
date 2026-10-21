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
godot --headless --path modules/ai_assistant/tests/fixture \
  --script "$PWD/modules/ai_assistant/tests/test_runtime.gd" \
  -- --source="$PWD/modules/ai_assistant"
cd tools/ai-companion
npm ci
npm test
npm run build
```

The `Godot AI Android` GitHub workflow also compiles the native Android arm64
editor and verifies the APK signature, package metadata and SHA-256 hash.

Evidence must be distinguished:

| Area | Current verification |
| --- | --- |
| Embedded runtime compilation, URL/path handling, tool modes, SSE and wire conversion | Automated local tests |
| Companion authentication boundary, SDK tool relay, cancellation and stdio MCP | Automated tests with deterministic runtimes |
| Android C++/Kotlin integration and APK | CI build required |
| Native panel rendering and physical Android touch/lifecycle | Device/editor check required |
| ChatGPT, Claude, Copilot and Kimi account logins | User-authorized live account checks required |
| Runware and local ComfyUI image/GLB generation | Live configured-provider checks required |

## Official protocol references

- [Godot Android builds](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_android.html)
- [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [ChatGPT plan inference limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [ComfyUI routes](https://docs.comfy.org/development/comfyui-server/comms_routes)
- [MCP transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
