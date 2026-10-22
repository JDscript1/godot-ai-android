# Assistant icon artwork

The provider marks are downloaded SVG artwork from
[Lobe Icons](https://github.com/lobehub/lobe-icons); llama.cpp uses its
[upstream logo](https://github.com/ggml-org/llama.cpp/tree/master/media).
Action icons come from [Lucide](https://github.com/lucide-icons/lucide).
These replace the previously hand-drawn provider approximations.

`manifest.json` records each upstream URL, pinned revision and SHA-256. The
original SVG files and full licenses are kept here. Brand names and logos
identify their respective services; this fork is not affiliated with them.

Run `python modules/ai_assistant/icons/sync.py` to download the pinned sources
and regenerate `runtime/icons.gd`. Embedding normalizes the viewport to 24×24;
the artwork paths and brand colors are retained. Mono `currentColor` marks
inherit the interface ink. Textures are rasterized at editor scale and cached.
The app uses the embedded artwork offline, without a React/Node dependency.

Custom API endpoints use Lucide's generic code icon. The two Qwen regions
share their brand mark. Subscription profiles retain their service identity.
