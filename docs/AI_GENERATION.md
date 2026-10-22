# Native generation providers

Configure profiles in **Setări → Generare**. Each profile owns its API key in the
credential vault. Cloud endpoints use fixed official HTTPS URLs. ComfyUI alone
accepts a configurable local endpoint with explicit HTTP opt-in. Select a saved
profile from the generation form or use its ID with `asset_generate` in chat.
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
model ID to avoid sending a model to the wrong service. Meshy forces GLB and
OpenAI forces PNG; Tripo supports separate profiles for either result type.

**Verifică server / modele** uses Meshy/Tripo balance endpoints or the OpenAI
model catalog without submitting a generation. Meshy/Tripo choices are documented
presets, not a dynamic account-specific discovery endpoint. A successful key
check does not establish access to every model. Runware uses a public catalog
and does not verify the key in that action.

Meshy text-to-3D currently submits the `preview` stage only. Its GLB is geometry
without the paid `refine` texture stage. Image-to-3D requests textures/PBR directly.
No extra paid stage is started by the read-only status polling tool.

`asset_generate` returns a persistent job ID. `asset_wait` polls within a bounded,
cancellable wait; `asset_status` refreshes later. Remote IDs, provider, endpoint,
progress and result paths survive restart. OpenAI returns image bytes directly;
these go through the same PNG validation and job storage. Import uses unique
project filenames and checks PNG decoding or self-contained GLB 2.0 structure.
Cloud CDN downloads receive no provider API key and only accepted provider domains
are allowed. Plan mode cannot submit or import; Auto requires a short executing
plan, and YOLO/individual confirmation rules apply to paid generation/import.

Stopping the HTTP wait does not cancel a provider task already accepted or undo
its credit charge. A lost submission response cannot always be recovered locally;
check the provider account before manually resubmitting. No automatic retry of
paid submissions or Meshy refine is implemented.

## Verification boundary

Native Godot HTTP tests exercise documented request/response fixtures, multipart
upload, polling, restart persistence, key isolation, failure handling, CDN
credentials, PNG/GLB validation and actual Godot GLB parsing. They do not prove
paid account access, generated model quality, live provider availability or
physical Android import/rendering. Those require configured-provider/device QA.

## Official schemas used

- [Meshy text-to-3D](https://docs.meshy.ai/en/api/text-to-3d)
- [Meshy image-to-3D](https://docs.meshy.ai/en/api/image-to-3d)
- [Meshy balance](https://docs.meshy.ai/en/api/balance)
- [Tripo text-to-model v3](https://developers.tripo3d.ai/en/docs/generation-text-to-model/standard)
- [Tripo image-to-model v3](https://developers.tripo3d.ai/en/docs/generation-image-to-model/standard)
- [Tripo text-to-image](https://developers.tripo3d.ai/en/docs/generation-text-to-image)
- [Tripo file upload](https://developers.tripo3d.ai/en/docs/files)
- [Tripo task query](https://developers.tripo3d.ai/en/docs/task-query)
- [Tripo account](https://developers.tripo3d.ai/en/docs/account)
- [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation)
