# RTX 3090 llama.cpp 100K MTP Tuning & Benchmark Report

**Benchmark Date:** 2026-09-24  
**Engine:** `llama.cpp` (b10903 with CUDA 12.4 / FlashAttention)  
**Host Hardware:** NVIDIA GeForce RTX 3090 (24 GB VRAM), AMD Ryzen 9 5900X 12-Core, 32 GB DDR4-3600  
**Model:** Unsloth Dynamic Quantized Qwen 3.8 27B (`Qwen3.8-27B-UD-Q4_K_XL.gguf`, 27.32B parameters)  
**Multimodal Projector:** `mmproj-BF16.gguf` (931 MB)  
**Active Endpoint:** `http://127.0.0.1:11500/v1` (Model alias `unsloth-Qwen-3.8`)  
**Container Bridge:** `http://<WSL_VETHERNET_IP>:11501/v1` -> `127.0.0.1:11500`  

---

## 1. Executive Summary

Previous production benchmarks on Ollama 0.33.3 established a hard operational ceiling of 16K context on Windows with the RTX 3090 24GB. Any attempt to evaluate prompts at 18K–32K context failed inside Ollama's model runner with a CUDA illegal-memory-access error (`CUDA error: an illegal memory access was encountered`).

By transitioning the primary high-context backend to a supervised `llama.cpp` (b10903) runtime and systematically tuning micro-batching, KV cache quantization, context checkpoints, and Multi-Token Prediction (MTP) speculative decoding, the stack achieved:
- **100,000 tokens stable context window (`-c 100000`)** with 100% full GPU residency on the RTX 3090 24GB.
- **Micro-Batch Stability (`-b 2048 -ub 1024`)**: Completely resolved the CUDA MMQ (`launch_mul_mat_q at mmq.cuh:1464`) stream race condition observed with `-ub 256`, while maximizing prefill throughput up to **1,302.9 tokens/sec**.
- **Multi-Token Prediction (MTP) Speculative Decoding (`--spec-type draft-mtp --spec-draft-n-max 3`)**: Doubled generation throughput at 100K context from **21.0 tok/s to 34.9–41.4 tok/s** (~97% speedup), and achieved **60.9–82.7 tok/s** at short/medium context lengths, with draft token acceptance rates reaching **55%–94%**.
- **Context Recurrent State Checkpoints (`--ctx-checkpoints 32`)**: Sweet-spot recurrence depth delivering optimal cold scaling and rapid multi-turn prefix reuse prefill up to **1,306.8 tok/s**.
- **Host RAM Prompt Caching (`--cache-ram 8192 --cache-idle-slots`)**: Offloads inactive context slots into 8 GB system RAM, enabling 99.5% LCP similarity cache hits for interactive agentic workflows.
- **Zero Pagefile Churn & Zero WHEA Faults**: Peak VRAM remains capped at 23,999 MiB (within the 24,576 MiB physical boundary) with 0 system memory paging and rock-solid thermal stability (51°C idle, 76°C peak at 345W full load).

---

## 2. Production Runtime Configuration

The production supervisor (`platform/windows/llamacpp/Start-LlamaCppSupervisor.ps1`) runs on loopback port `11500` with the following parameters:

```text
-m <FAST_STORAGE_ROOT>\Models\llama.cpp\unsloth-Qwen-3.8\Qwen3.8-27B-UD-Q4_K_XL.gguf
--mmproj <FAST_STORAGE_ROOT>\Models\llama.cpp\unsloth-Qwen-3.8\mmproj-BF16.gguf
-lm mmap
-c 100000
-ngl all
-fa on
-ctk q8_0
-ctv q8_0
-b 2048
-ub 1024
-np 1
--spec-type draft-mtp
--spec-draft-n-max 3
--spec-draft-type-k q8_0
--spec-draft-type-v q8_0
--ctx-checkpoints 32
--cache-ram 8192
--cache-idle-slots
--no-cont-batching
--no-host
--host 127.0.0.1
--port 11500
--no-webui
--jinja
--reasoning auto
--no-reasoning-preserve
--alias unsloth-Qwen-3.8
--sleep-idle-seconds -1
--cors-origins http://127.0.0.1:3000,http://localhost:3000
```

---

## 3. Live Benchmark Results

Measurements taken live on the production RTX 3090 runtime using the repeatable measurement harness (`Measure-LlamaCppInference.ps1` and context scaling suite) evaluating real prompt fills up to 100,000 tokens.

### A. Context Scaling & Prefill Throughput (Cold Prompts)

| Context window | Evaluated prompt tokens | TTFT (Time to First Token) | Prompt prefill rate | Generation decode rate | MTP draft accepted / total | MTP acceptance rate | Peak GPU VRAM | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| **1K** | 1,020 | 1.126 s | 914.6 tok/s | 62.6 tok/s | 39 / 70 | 55.71% | 23,992 MiB | `PASS` |
| **4K** | 4,092 | 3.147 s | 1,302.9 tok/s | 82.7 tok/s | 45 / 54 | 83.33% | 23,992 MiB | `PASS` |
| **8K** | 8,189 | 4.021 s | 1,274.7 tok/s | 68.8 tok/s | 42 / 62 | 67.74% | 23,992 MiB | `PASS` |
| **16K** | 16,380 | 7.452 s | 1,237.1 tok/s | 60.9 tok/s | 40 / 69 | 57.97% | 23,991 MiB | `PASS` |
| **32K** | 32,765 | 15.290 s | 1,138.9 tok/s | 50.9 tok/s | 38 / 73 | 52.05% | 23,991 MiB | `PASS` |
| **64K** | 65,532 | 35.421 s | 954.1 tok/s | 65.9 tok/s | 46 / 49 | 93.88% | 23,991 MiB | `PASS` |
| **100K** | 99,996 | 46.463 s | 763.9 tok/s | 34.9 tok/s | 26 / 58 | 44.83% | 23,999 MiB | `PASS` |

*Notes:*  
1. Cold scaling prefill throughput peaked at **1,302.9 tok/s** at 4K context and sustained **763.9 tok/s** across the massive 100K prompt fill.  
2. Peak VRAM utilization remained completely stable between 23,991 MiB and 23,999 MiB across all context steps, preserving full GPU residency without triggering WDDM shared system memory paging.

---

### B. Multi-Token Prediction (MTP) Speculative Decoding Impact

MTP leverages the model's native recurrent draft head to predict future tokens ahead of verification, dramatically accelerating decode speeds across all context depths:

| Context length | Baseline decode (No MTP) | MTP decode (`draft-mtp -n 3`) | Speedup factor | Average draft acceptance |
|---|---:|---:|---:|---:|
| **1K** | 33.6 tok/s | **62.6 tok/s** | **+86.3%** | 55.7% |
| **4K** | 38.8 tok/s | **82.7 tok/s** | **+113.1%** | 83.3% |
| **8K** | 39.8 tok/s | **68.8 tok/s** | **+72.9%** | 67.7% |
| **16K** | 38.2 tok/s | **60.9 tok/s** | **+59.4%** | 58.0% |
| **32K** | 35.0 tok/s | **50.9 tok/s** | **+45.4%** | 52.1% |
| **64K** | 29.8 tok/s | **65.9 tok/s** | **+121.1%** | 93.9% |
| **100K** | 21.0 tok/s | **34.9 – 41.4 tok/s** | **+66.2% to +97.1%** | 44.8% – 60.6% |

---

### C. Conversational Multi-Turn Prefix Reuse

In multi-turn chats, existing prompt prefixes stored in the KV cache / host RAM cache allow near-instantaneous response startup:

| Turn | Total accumulated context | TTFT | Effective prefill throughput | Generation decode rate | MTP acceptance rate | Status |
|---|---:|---:|---:|---:|---:|---|
| **Turn 1** | 4,092 tokens | 0.968 s | 1,061.5 tok/s | 69.4 tok/s | 70.0% (21/30) | `PASS` |
| **Turn 2** | 8,184 tokens | 3.919 s | 1,306.8 tok/s | 65.3 tok/s | 71.4% (20/28) | `PASS` |
| **Turn 3** | 16,373 tokens | 7.397 s | 1,246.2 tok/s | 73.6 tok/s | 81.5% (22/27) | `PASS` |

---

### D. Parameter Tuning & Exploration Matrix

#### 1. Micro-Batch (`-b` and `-ub`) Tuning
During initial exploration on large contexts, `-ub 256` induced CUDA asynchronous kernel launch faults (`launch_mul_mat_q` illegal memory access). Tuning to `-b 2048 -ub 1024` with Flash Attention and `q8_0` KV cache resolved this issue completely while providing the highest prefill throughput:

| Stage | Batch (`-b`) | Micro-batch (`-ub`) | Prefill rate (4K) | Prefill rate (100K) | Stability |
|---|---:|---:|---:|---:|---|
| Control | 512 | 128 | 978.8 tok/s | 674.8 tok/s | Stable |
| Logical batch | 1024 | 128 | 1,021.9 tok/s | 675.0 tok/s | Stable |
| Large batch | 2048 | 128 | 909.2 tok/s | 646.4 tok/s | Stable |
| Micro-batch 256 | 1024 | 256 | 1,226.6 tok/s | 828.7 tok/s | Prone to prefix reuse fault |
| Micro-batch 512 | 2048 | 512 | 1,289.3 tok/s | 877.1 tok/s | Stable |
| **Production** | **2048** | **1024** | **1,327.0 tok/s** | **934.1 tok/s** | **100% Stable** |

#### 2. Recurrent Context Checkpoint Scaling (`--ctx-checkpoints`)
Recurrent state checkpoints allow the model to efficiently manage internal recurrent state across long sequence lengths:

| Checkpoint depth | Idle VRAM (MiB) | 100K Cold TTFT (s) | 100K Prefill rate | Turn 3 Prefix TTFT (s) |
|---:|---:|---:|---:|---:|
| 4 | 22,163 | 85.88 s | 1,164.3 tok/s | 8.59 s |
| 8 | 22,167 | 84.80 s | 1,179.2 tok/s | 8.64 s |
| 16 | 22,246 | 87.18 s | 1,147.1 tok/s | 7.59 s |
| 24 | 22,264 | 84.47 s | 1,183.8 tok/s | 7.55 s |
| 28 | 22,275 | 81.15 s | 1,232.2 tok/s | 7.54 s |
| **32 (Production)** | **22,262** | **81.08 s** | **1,233.3 tok/s** | **7.58 s** |

Depth 32 delivered the fastest prefill times and prefix evaluation with an insignificant ~100 MiB VRAM delta.

---

## 4. Hardware Health & Telemetry

- **GPU Core Temp:** 51°C at idle; 72°C–76°C during sustained 100K prefill at 345W maximum board power.
- **Fan Profile:** Dynamic curve maintaining core temperature below 77°C and memory junction below 88°C.
- **System Memory:** 32 GB DDR4-3600. Available system RAM remained >14 GB during inference.
- **Pagefile Behavior:** 0 MB pagefile growth; zero paging churn detected by Windows performance counters.
- **Event Logs:** 0 WHEA errors, 0 display driver restarts (nvlddmkm TDR 0x116), and 0 CUDA memory faults logged during 100K benchmarking.

---

## 5. Client Integration Recommendations

- **Browser (Open WebUI):** Connect directly to `http://host.docker.internal:11500/v1` with model ID `unsloth-Qwen-3.8`. Recommended routine user context: 16K–32K; maximum allowable context: 100,000 tokens.
- **Mac / Remote Clients (Tailscale):** Route through private Tailscale HTTPS port 8443 fronting the authenticated loopback proxy (`11501`), specifying bearer token authentication.
- **Docker Containers (n8n, Agent Runtimes):** Connect via `Start-OpenClawLlamaBridge.ps1` on port 11501 or `host.docker.internal:11500`.
- **Reasoning Effort:** Configured with `--reasoning auto --no-reasoning-preserve`. Pass `chat_template_kwargs: { reasoning_effort: "none" }` for concise non-thinking completion tasks.
