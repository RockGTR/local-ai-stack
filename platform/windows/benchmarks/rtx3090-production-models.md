# RTX 3090 production-model benchmark

Benchmark date: 2026-09-12  
Runtime: Ollama 0.33.3 on Windows, NVIDIA driver 616.56  
Host class: RTX 3090 24 GB, Ryzen 9 5900X, 32 GB DDR4-3600

The repeatable harness is `platform/windows/ollama/Measure-OllamaInference.ps1`. It binds only to the loopback Ollama API, records no prompt or response text, enforces an 8 GB available-RAM floor, samples GPU/RAM/pagefile telemetry, and can require complete GPU residency. Private raw JSON measurements remain outside Git.

## Recommended production settings

- Keep `OLLAMA_MAX_LOADED_MODELS=1` and `OLLAMA_NUM_PARALLEL=1`.
- Use flash attention with `q8_0` KV cache.
- Do not set a global context length. Request 8K for routine work and at most 16K for the two 27B Qwen3.8 variants on this runtime.
- Use full GPU residency. Controlled 48-of-65-layer GPU offload worked, but generation slowed by roughly 6x and provided no verified context benefit.
- Keep the five-minute default keep-alive. Pre-warm the currently needed model when latency matters; do not try to keep a 27B model and the 14B completion model resident together.

## Performance results

| Model/profile | Context and task | Load / wall | Prompt speed | Generation speed | Residency / peak GPU | Minimum available RAM | Result |
|---|---|---:|---:|---:|---:|---:|---|
| Qwen3.8 27B, warm GPU | 8K chat | 0.004 s / 3.47 s | 66.5 tok/s | 41.0 tok/s | full / 19,092 MiB | 16.46 GB | pass |
| Qwen3.8 27B, GPU | 8K window, 6,441-token fill | 0.003 s / 5.61 s | 1,168.2 tok/s | 39.8 tok/s | full / 19,116 MiB | 16.01 GB | pass |
| Qwen3.8 27B, GPU | 16K window, 14,441-token fill | 11.86 s / 24.95 s | 1,115.2 tok/s | 31.3 tok/s* | full / 19,594 MiB | 15.77 GB | pass |
| Qwen3.8 27B, GPU | 32K window | n/a | reached 18,432 prompt tokens | n/a | full before runner fault | >8 GB guard | fail: CUDA illegal memory access |
| Qwen3.8 27B, 48-layer GPU offload | 8K warm chat | 0.003 s / 9.43 s | 48.9 tok/s | 6.4 tok/s | 12.11 GB runtime VRAM / 14,126 MiB peak GPU | 10.91 GB | pass |
| Qwen3.8 27B, 48-layer GPU offload | 16K window, 14,016-token fill | 14.01 s / 32.58 s | 779.8 tok/s | 10.4 tok/s* | 12.35 GB runtime VRAM / 14,456 MiB peak GPU | 9.90 GB | pass |
| Qwen2.5-Coder 14B Base, cold GPU | 8K FIM | 10.83 s / 11.71 s | 320.3 tok/s | 67.0 tok/s | full / 11,499 MiB | 17.09 GB | pass |
| Qwen2.5-Coder 14B Base, warm GPU | 8K FIM | 0.003 s / 1.27 s | 110.0 tok/s | 68.3 tok/s | full / 11,511 MiB | 17.95 GB | pass |
| Qwen3.8 27B Abliterated, cold GPU | 8K chat | 12.07 s / 13.88 s | 120.9 tok/s | 37.9 tok/s | full / 19,090 MiB | 17.10 GB | pass |
| Qwen3.8 27B Abliterated, warm GPU | 8K chat | 0.003 s / 2.12 s | 76.6 tok/s | 38.8 tok/s | full / 19,103 MiB | 16.84 GB | pass |
| Qwen3.8 27B Abliterated, GPU | 16K window, 14,016-token fill | 12.29 s / 24.44 s | 1,177.2 tok/s | 37.5 tok/s* | full / 19,640 MiB | 11.40 GB | pass |
| Qwen3.8 27B Abliterated, GPU | 32K window | n/a | runner fault during prompt fill | n/a | full before runner fault | >8 GB guard | fail: CUDA illegal memory access |

\* Only two or three output tokens were requested during context-fill tests, so these generation rates are directional rather than representative.

The first uncached Qwen3.8 read measured 30.06 seconds of load time. Later OS-cached cold switches were 11.35-12.44 seconds. The Docker/Open WebUI coexistence check kept Qwen3.8 fully GPU-resident at 8K, retained 11.29 GB available RAM, and showed no pagefile growth.

## Capability results

| Capability | Result |
|---|---|
| Qwen3.8 native tool call | pass |
| Qwen3.8 JSON-schema structured output | pass |
| Qwen3.8 image input | pass |
| Abliterated Qwen3.8 native tool call | pass |
| Abliterated Qwen3.8 JSON-schema structured output | pass |
| Abliterated Qwen3.8 image input | pass |
| Qwen2.5-Coder Base fill-in-the-middle | pass; insertion was syntactically correct |
| OpenAI `/v1/models` | pass |
| OpenAI `/v1/chat/completions` | pass |
| OpenAI chat streaming | pass; SSE frames and terminal `[DONE]` received |
| OpenAI tool calls and JSON schema | pass |
| OpenAI image message | pass |
| OpenAI `/v1/completions` | pass with the Base coder; not recommended for the thinking chat model |

## Context conclusion

The production-safe, fully GPU-resident ceiling is 16K for both 27B builds on the tested Ollama version. Each passed a real 14K-token fill at 16K and failed a 32K attempt with the same CUDA illegal-memory-access error. The standard build reached 18,432 processed prompt tokens before the runner fault. Both failures occurred despite fitting the apparent VRAM budget. This is a Qwen hybrid-model/runtime boundary, not proof of a storage, RAM, or pagefile shortage. The advertised 262K model context must not be exposed as an operational limit.

The controlled RAM-offload profile also has a 16K verified ceiling. It kept approximately 5.45 GB of runtime allocation outside VRAM, stayed above the 8 GB RAM safety floor, and caused no pagefile growth. A higher offload context is deliberately not declared after the 32K GPU-profile kernel fault; offload is therefore a diagnostic fallback, not a recommended production mode.

No WHEA or display-driver event appeared during the suite. Maximum observed GPU temperature was 63°C.
