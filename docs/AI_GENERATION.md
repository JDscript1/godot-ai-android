# Native generation providers

The catalog flow below is implemented in source on 26 October 2026; the current
Download APK `e401e8f` predates it. Physical Android and paid-provider generation
are separate from the checks listed below.

Configure profiles in **Setări → Generare**:

1. Select **Imagini** or **Mesh-uri 3D**, then the cloud provider.
2. Paste the API key. After a short debounce, the app validates it through a
   non-generating request and loads models without first saving a profile.
3. Search the model list and select a row. Its right column shows the price;
   selecting it shows the billing conditions, source and publication/check date.
4. Choose the project destination and preferred 3D export format, then save.
   The agent uses that saved profile for generation.

Cloud profiles of the same provider share one key in the credential vault.
Runware, Meshy and Tripo can use it for both images and meshes. Switching result
type starts an independent profile; changing provider clears the draft key.
Invalid replacement keys do not replace the last validated credential or retain
stale model choices. Keys from older per-profile entries are verified and reused.
Keys remain out of configuration/model metadata and are masked in errors.
ComfyUI keeps endpoint-specific credentials and its workflow configuration.

Cloud endpoints are fixed official HTTPS URLs. **Actualizează modele** also
works before saving; it checks the current draft key or the saved provider key.
A model ID override and optional profile name remain under **Opțiuni profil**.
New cloud profiles require a verified catalog and a selected/nonempty model ID.
Older profiles without a model ID keep their adapter defaults until edited.
A chat subscription does not supply generation API credits.

| Service | Images | 3D | Catalog source |
| --- | --- | --- | --- |
| Runware | Text → PNG | Supported AIR models → GLB | Live public index + per-model schemas; authenticated ping checks the key |
| ComfyUI | Workflow → PNG | Workflow → GLB | Local node definitions/workflow |
| Meshy | Text → image | Text → preview GLB; image → textured GLB | Documented model presets; authenticated balance checks the key |
| Tripo v3 | Text → PNG | Text/image → textured GLB | Documented model presets; authenticated balance checks the key |
| OpenAI Images | GPT Image text → PNG | — | Authenticated account model list, restricted to image models |

Runware prices load progressively with at most four public schema requests in
flight and a 24-hour cache. No API key is sent to the documentation host.
Retired models and the unsupported mask-dependent SAM 3D workflow are excluded.
OpenAI's retired GPT Image 1 aliases are excluded from new selections.
Meshy/Tripo do not expose an account-specific discovery endpoint in this adapter:
the list is a documented catalog, and a valid key does not guarantee entitlement
to every listed model, sufficient credits or access to every option.

## Price meaning

Each row has a price cell. **USD** and **cr.** retain the provider's billing unit;
Meshy credit prices are not converted using an invented subscription exchange rate.
A `+` means a starting price, and `≈` identifies a measured example/estimate.
Token billing is **Variabil** when a defensible per-generation amount is unavailable.
Unpublished/failed pricing is **Indisponibil**, distinct from a real zero tariff.
Conditions such as reference input, textures, resolution, quality and prompt
usage can add costs. In particular, OpenAI's documented low-quality output
example is a starting point, not a quote for automatic quality or the input prompt.
The adapter preserves its existing generation defaults.

Runware rates come from `info["x-pricing"]` in the official model schemas;
measured GPU examples never become fixed tariffs. Meshy and Tripo presets and
tariffs were checked on **2026-10-26**. The saved profile includes the selected
model's public price metadata so the agent can see the same conditions. It must
not describe an estimate as the final charge. Reading catalogs, prices and
validating keys never submits a generation or conversion.

Sources: [Runware pricing JSON](https://runware.ai/docs/models-api/pricing),
[Meshy API prices](https://docs.meshy.ai/en/api/pricing),
[Tripo API prices](https://developers.tripo3d.ai/en/pricing),
[OpenAI image costs](https://developers.openai.com/api/docs/guides/image-generation#calculating-costs).


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

## Catalog verification, 26 October 2026

- Real Godot runtime/HTTP fixture suite: **465 assertions**, including priced
  catalogs, shared keys, invalid draft keys, PNG/GLB import and the Meshy image API.
- Dedicated rendered UI: tablet and narrow layout checks cover paste-to-discover,
  per-row pricing, selected-model persistence, provider/type changes, legacy
  credentials and the absence of paid requests. Screenshot and report paths:
  `.ai-qa/generation-catalog-final-*`.
- Real read-only Runware requests through the Godot transport returned **106 image
  models and 6 supported mesh models**, plus two real price schemas. No API key
  or paid generation was used: `.ai-qa/generation-public-verification.json`.
- Start-screen shared-panel regression passed **52 checks**. A broad tablet
  editor pass exceeded its 180-second local limit; it is not counted as passed.
  The broad narrow editor pass passed **466 checks**. Dedicated passes passed
  **52 checks each on tablet and narrow**, followed by **53 tablet checks** with
  an authentication error that echoes the draft key; the echoed key is masked.
- Script loader includes the new `generation_catalog.gd` in the native embedded
  module and test loaders. The workflow includes dedicated catalog screenshots
  for both upstream and compiled native editors on the next build.
