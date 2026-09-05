# Model candidates for the RTX 3090 host

Status: `PROPOSED`; only the small `qwen3:0.6b` deployment-smoke fixture is installed. No candidate below has been approved or downloaded.

Research checkpoint: 2026-09-04. Sources are publisher model cards and official Ollama registry artifacts. Registry manifest hashes and upstream revisions are recorded because friendly tags can move.

## Recommended roles

| Preset | Exact Ollama tag | Stored payload | License | Intended role |
|---|---|---:|---|---|
| `coding-quality` | `qwen3.8:27b-q4_K_M` | 17.742 GB | Apache-2.0 | Highest-quality coding, agentic chat, image input, and long-context candidate |
| `coding-fast` | `qwen3-coder:30b-a3b-q4_K_M` | 18.557 GB | Apache-2.0 | Faster sparse-MoE coding and tool-use candidate |
| `vision` | `qwen3.5:9b-q4_K_M` | 6.594 GB | Apache-2.0 | Fast image, OCR, document, and visual-reasoning candidate |
| `completion-fim` | `qwen2.5-coder:7b-base-q4_K_M` | 4.683 GB | Apache-2.0 | Low-latency fill-in-the-middle completion only; not a chat assistant |

Structured JSON is an Ollama runtime feature, not proof that a quantized model will follow every schema. Tool calls, schemas, OpenAI compatibility, image input, and context limits must be verified per exact artifact.

## Immutable records

### Qwen3.8 27B, quality/balanced/vision/long context

- Upstream: `Qwen/Qwen3.8-27B` at revision `1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0`.
- Ollama tag: `qwen3.8:27b-q4_K_M`.
- Manifest SHA-256: `25b843619e944cd0ae6069f94ff4e5e26a16e109ccbc0a66a0f05979ed70098e`.
- Model blob: `f5f1dd8920d417aac2718b0bda3403da274301efdd6760b4f0f4b864ff2ad57d`, 16,810,714,464 bytes.
- BF16 vision projector: `ac3714bfdddeca31351f2752bf1a63f266f4df87c0b68c895e44945ca704448e`, 931,146,016 bytes.
- Parameters: 27.3B language model plus 461M vision projector; `Q4_K_M` language weights.
- Capabilities: text, image, tools, and thinking in the official Ollama artifact; structured output through Ollama; no documented FIM template.
- Context claim: 262,144 native. The practical GPU-only limit is unknown. Start at 8K, then test 16K and 32K before attempting larger windows.
- Residency estimate: tight but plausible for one fully GPU-resident model at a modest context. Measure buffers and KV cache rather than assuming the advertised window fits 24 GB.
- Use the explicit non-MTP tag as the reproducible baseline. Benchmark MTP only later; do not pull the mutable `:27b` tag silently.
- Sources: [pinned publisher model card](https://huggingface.co/Qwen/Qwen3.8-27B/tree/1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0), [official Ollama artifact](https://ollama.com/library/qwen3.8:27b-q4_K_M), and [Ollama Qwen3.8 support release](https://github.com/ollama/ollama/releases/tag/v0.32.12).

### Qwen3-Coder 30B-A3B, faster agentic coding

- Upstream: `Qwen/Qwen3-Coder-30B-A3B-Instruct` at revision `b2cff646eb4bb1d68355c01b18ae02e7cf42d120`.
- Ollama tag: `qwen3-coder:30b-a3b-q4_K_M`.
- Manifest SHA-256: `06c1097efce0431c2045fe7b2e5108366e43bee1b4603a7aded8f21689e90bca`.
- Model blob: `1194192cf2a187eb02722edcc3f77b11d21f537048ce04b67ccf8ba78863006a`, 18,556,688,736 bytes.
- Parameters: 30.5B total, 3.3B active; `Q4_K_M`.
- Capabilities: text, tools, non-thinking agentic coding; no vision and no documented FIM template.
- Context claim: 262,144 native. Start GPU-only testing at 8K, then 16K and 32K; do not assume 64K fits.
- Residency estimate: model weights leave limited space for the display, runtime buffers, and KV cache. Only one large model is loaded at a time.
- Sources: [pinned publisher model card](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct/tree/b2cff646eb4bb1d68355c01b18ae02e7cf42d120), [official Ollama artifact](https://ollama.com/library/qwen3-coder:30b-a3b-q4_K_M).

### Qwen3.5 9B, fast vision

- Upstream: `Qwen/Qwen3.5-9B` at revision `c202236235762e1c871ad0ccb60c8ee5ba337b9a`.
- Ollama tag: `qwen3.5:9b-q4_K_M`.
- Manifest SHA-256: `6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7`.
- Model blob: `dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c`, 6,594,462,816 bytes; total manifest layers are 6,594,474,236 bytes.
- Parameters: 9.65B; `Q4_K_M`.
- Capabilities: text, image, tools, and thinking. The upstream card also discusses video, but the Ollama artifact advertises text and image only, so direct video is out of scope.
- Context claim: 262,144 native. Approximately 32K with `q8_0` KV cache should be a comfortable first full-GPU target, but this is an estimate.
- Publisher benchmarks favor the full-precision 9B checkpoint over Qwen3-VL-30B-A3B on many OCR/document/vision rows. Quality retention at Q4 is unverified.
- Sources: [pinned publisher model card](https://huggingface.co/Qwen/Qwen3.5-9B/tree/c202236235762e1c871ad0ccb60c8ee5ba337b9a), [official Ollama artifact](https://ollama.com/library/qwen3.5:9b-q4_K_M).

### Qwen2.5-Coder 7B Base, FIM completion

- Upstream: `Qwen/Qwen2.5-Coder-7B` at revision `0396a76181e127dfc13e5c5ec48a8cee09938b02`.
- Ollama tag: `qwen2.5-coder:7b-base-q4_K_M`.
- Manifest SHA-256: `bd8755145f1c58dcc43bbac9958832257a5c0c65c1bfeca859867ad71f6a9f60`.
- Model blob: `0aa0872a8ea3451cf9b9eeea4f4048d3040a7acf29c64f95d103d6916d4911dd`, 4,683,073,952 bytes; total manifest layers are 4,683,085,412 bytes.
- Parameters: 7.62B; `Q4_K_M`.
- Capabilities: the official Ollama template emits FIM prefix/suffix/middle tokens. Use `/api/generate` with `suffix`; do not use the Base model for conversation or tool use.
- Context claim: 32K in Ollama. The publisher describes a longer YaRN configuration, which is not enabled for the baseline because it can reduce short-context quality.
- Sources: [pinned publisher model card](https://huggingface.co/Qwen/Qwen2.5-Coder-7B/tree/0396a76181e127dfc13e5c5ec48a8cee09938b02), [official Ollama artifact](https://ollama.com/library/qwen2.5-coder:7b-base-q4_K_M).

## Alternative and rejection

`devstral-small-2:24b-instruct-2512-q4_K_M` is a credible Apache-2.0 coding/tool/vision alternative: model blob 15,177,370,240 bytes; total manifest layers 15,177,373,679 bytes; manifest `24277f07f62db8f9cb68e9dfc679ea1818a7fbac47a50eff0a701d3f645b63c8`; upstream revision `55c5b41e98c2dbd21b0c8afffc540dcfc9eb5128`. It is a benchmark alternative rather than an initial download because Qwen3.8 already covers the quality/vision role. Sources: [publisher model card](https://huggingface.co/mistralai/Devstral-Small-2-24B-Instruct-2512/tree/55c5b41e98c2dbd21b0c8afffc540dcfc9eb5128), [official Ollama artifact](https://ollama.com/library/devstral-small-2:24b-instruct-2512-q4_K_M).

`qwen3-coder-next:q4_K_M` is rejected for this host baseline. Its official Q4 artifact is 51.742 GB, too large for a 24 GB GPU and unsafe to combine with available system RAM while preserving the OS reserve and avoiding pagefile dependence.

## Exact approval choices

Current fast-root use is 0.523 GB, and the preflight permits another 199.477 GB. These are storage checks only; they do not prove VRAM residency.

The full 47.576 GB working-set proposal also passed a dry preflight with an additional 5 GB temporary allowance: projected fast-root use is 53.099 GB, the 200 GB cap is preserved, and the OS-volume reserve remains intact. This preflight must still be repeated immediately before any approved download because free space can change.

1. Minimal quality/vision: Qwen3.8 27B only, 17.742 GB payload.
2. Recommended coding pair: Qwen3.8 27B plus Qwen3-Coder 30B-A3B, 36.299 GB combined payload.
3. Recommended full working set: add Qwen3.5 9B vision and Qwen2.5-Coder 7B Base FIM, 47.576 GB combined payload.
4. Optional alternative benchmark: Devstral Small 2, another 15.177 GB.

Before any approved pull, rerun storage preflight with the exact payload plus temporary overhead. After each pull, verify the manifest, license, API behavior, GPU residency, peak RAM/pagefile activity, and cold/warm load times. Never keep both large models loaded merely because both fit on disk.
