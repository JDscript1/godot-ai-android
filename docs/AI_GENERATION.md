# Native generation providers

Configure profiles in **Setări → Generare**. Cloud profiles of the same provider
share one API key in the credential vault, so Runware image and 3D profiles use
the same key; ComfyUI keeps credentials per endpoint. Cloud endpoints use fixed official HTTPS URLs. ComfyUI alone
accepts a configurable local endpoint with explicit HTTP opt-in. Select a saved
profile from the list below the configuration form or use its ID with `asset_generate` in chat.
Generation consumes provider credits; an API key and access to the model are
required. A chat subscription does not supply these API credits.

| Service | Images | 3D | Reference input |
| --- | --- | --- | --- |
| Runware | Text → PNG | Supported AIR models → GLB | Per-model 3D binding |
| ComfyUI | Workflow → PNG | Workflow → GLB | Bound workflow input |
| Meshy | — | Text → preview GLB; image → textured GLB | Project PNG/JPEG/WebP |
| Tripo v3 | Text → PNG | Text/image → textured GLB | Multipart upload; WebP converted to PNG |
| OpenAI Images | GPT Image text → PNG | — | Not supported by this initial adapter |

An empty model field uses the documented default for Meshy/Tripo. Tripo image
profiles use `seedream_v5`; OpenAI image profiles use `gpt-image-2.5-flare`.
You can enter another compatible model ID. Provider changes clear a previous
model ID to avoid sending a model to the wrong service. Meshy uses GLB for the original preview and
OpenAI forces PNG; Tripo supports separate profiles for either result type.

**Testează cheia / modele** uses an authenticated, non-generating Runware ping,
Meshy/Tripo balance endpoints or the OpenAI
model catalog without submitting a generation. Meshy/Tripo choices are documented
presets, not a dynamic account-specific discovery endpoint. A successful key
check does not establish access to every model. Runware's model list is public;
the separate ping validates the saved key.

Meshy text-to-3D currently submits the `preview` stage only. Its GLB is geometry
without the paid `refine` texture stage. Image-to-3D requests textures/PBR directly.
No extra paid stage is started by the read-only status polling tool.

`asset_generate` returns a persistent job ID. `asset_wait` polls within a bounded,
cancellable wait; `asset_status` refreshes later. Remote IDs, provider, endpoint,
progress and result paths survive restart. OpenAI returns image bytes directly;
these go through the same PNG validation and job storage. Completed originals
are automatically imported under the configured `res://` destination, one
folder per job named from the prompt and a short ID, such as
`res://ai_assets/copac_12345678/copac.glb`. Import checks PNG decoding or
self-contained GLB 2.0 structure and never overwrites an existing file.
Cloud CDN downloads receive no provider API key and only accepted provider domains
are allowed. Plan mode cannot submit or import; Auto requires a short executing
plan, and YOLO/individual confirmation rules apply to paid generation/import.

Stopping the HTTP wait does not cancel a provider task already accepted or undo
its credit charge. A lost submission response cannot always be recovered locally;
check the provider account before manually resubmitting. No automatic retry of
paid submissions or Meshy refine is implemented.

## Export formats

Choose a preferred 3D format in the profile, then select the completed job and
use **Exportă modelul…** for that format. The agent can call `asset_export` after
generation. The original GLB remains the preview/import source; successful
exports are saved beside it with the object name and format suffix. If the
project folder is unavailable, the UI offers a save-file picker. No format is
implemented by renaming an extension. Paid provider conversions still require
the normal external-action permission and are not launched merely by selecting
a preferred format. Manual generation and results are in a collapsed section.

| Format | Runware / ComfyUI | Meshy | Tripo | Result |
| --- | --- | --- | --- | --- |
| GLB | Original | Original | Original | Original self-contained GLB |
| glTF 2.0 | Native | Native | Native | ZIP containing glTF and generated dependencies |
| OBJ / STL / PLY | Native | Native | Native | Static triangle geometry; no materials, rig or animation |
| FBX | — | Provider conversion | Provider conversion | FBX or provider ZIP package |
| USDZ / 3MF | — | Provider conversion | Provider conversion | Original provider container |
| BLEND | — | Provider conversion | — | Original provider file/container |

Native exporters traverse actual imported meshes, apply node transforms and correct
winding for mirrored transforms. STL is binary; OBJ/PLY are text. Coordinates retain
Godot units; STL has no unit metadata, so configure units in the receiving slicer.
Use GLB/glTF to preserve the richer scene/material data. These native exports do not
bake skinning, morphs or animation into geometry. DXF, DAE, USD/USDC, Alembic and
provider export presets are not implemented. Meshy's web application supporting a
format does not establish its availability in the public API.

The agent has `asset_export(job, format[, task_id])`. Cloud conversion is an external,
potentially paid action and follows normal permissions. The UI asks before the first
conversion and offers Stop during export; reopening a known conversion resumes its existing task. Remote conversion
IDs/results persist with the generation job. Repeated native export uses a source-hash
cache. Original generated files are never overwritten.

Meshy uses `POST /openapi/v1/convert` and its task endpoint; Tripo v3 uses
`POST /models/convert` and `GET /tasks/{id}`. Conversions are polled for up to two
minutes per invocation. Stop interrupts waiting, not an accepted provider task. A
lost submission response is recorded as **unknown**, preventing blind paid retries.
The UI/tool can recover using the existing task ID from the provider dashboard.
Do not invent an ID. Explicit HTTP/API rejections permit a fresh, confirmed attempt.

Downloads send no provider credential to CDN hosts. Export checks size, recognizable
FBX/BLEND headers or archive structure and expected members; archives containing parent
traversal paths are rejected. Archives are preserved, never automatically extracted.
These checks are structural, not full FBX/USDZ/BLEND decoders or proof of material
completeness. Separate provider textures may still require packaging by the provider;
GLB/glTF remain the reliable self-contained exchange option.

## Verification boundary

Native Godot HTTP tests exercise documented request/response fixtures, multipart
upload, polling, restart persistence, key isolation, failure handling, CDN
credentials, PNG/GLB validation and actual Godot GLB parsing. They do not prove
paid account access, generated model quality, live provider availability or
physical Android import/rendering. Those require configured-provider/device QA.

## Official schemas used

- [Meshy text-to-3D](https://docs.meshy.ai/en/api/text-to-3d)
- [Meshy image-to-3D](https://docs.meshy.ai/en/api/image-to-3d)
- [Meshy conversion](https://docs.meshy.ai/en/api/convert)
- [Tripo conversion v3](https://developers.tripo3d.ai/en/docs/models-convert)
- [Meshy balance](https://docs.meshy.ai/en/api/balance)
- [Runware authentication and ping](https://runware.ai/docs/models-api/authentication)
- [Tripo text-to-model v3](https://developers.tripo3d.ai/en/docs/generation-text-to-model/standard)
- [Tripo image-to-model v3](https://developers.tripo3d.ai/en/docs/generation-image-to-model/standard)
- [Tripo text-to-image](https://developers.tripo3d.ai/en/docs/generation-text-to-image)
- [Tripo file upload](https://developers.tripo3d.ai/en/docs/files)
- [Tripo task query](https://developers.tripo3d.ai/en/docs/task-query)
- [Tripo account](https://developers.tripo3d.ai/en/docs/account)
- [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation)
