# Windows status

Last updated: 2026-09-24
Owner: Windows
Lifecycle: `POST_REBOOT_VERIFIED`
Overall state: `PRODUCTION_MODELS_READY`; the three approved models are installed and tested, and the authenticated browser UI is available through private HTTPS. Raw model APIs remain intentionally unexposed.

## Sanitized verified baseline

- Hardware class: Windows 11, AMD Ryzen 9 5900X, RTX 3090 with 24 GB VRAM, and 32 GB DDR4 RAM.
- Storage class: the fast and regular roots are on separate physical NVMe SSDs.
- Stack caps: 200 GB fast and 500 GB regular, additionally constrained by live free space and the operating-system reserve.
- Both 16 GB memory modules report 3600 MT/s, matching the selected kit profile. No WHEA event has been recorded since the successful firmware boot; sustained stability testing remains pending.
- CPU virtualization is enabled in firmware, the Windows hypervisor is present, and the WSL 2 Docker Linux engine is operational.
- The pagefile is already Windows-managed on the operating-system drive and is not scheduled to move.
- The old Docker engine data was purged under the explicit Docker-only authorization. No unrelated files, repositories, credentials, or WSL distributions were deleted.
- Tailscale 1.102.3 is connected, its private HTTPS Serve route is verified for the authenticated browser UI, and Funnel is disabled. Private device and network values are intentionally omitted.
- The native runtime and Docker-backed browser UI are verified locally. Both listeners remain restricted to Windows loopback.
- The installed production set uses the role-based aliases `coding-vision-tools:latest`, `code-autocomplete-fim:latest`, and `uncensored-vision-tools:latest`. Immutable source identifiers remain in the public manifest.

## Completed

- Tuned and verified llama.cpp b10903 with CUDA 12.4 and FlashAttention, delivering a verified **100,000-token context ceiling** on the RTX 3090 24GB for unsloth-Qwen-3.8 (Qwen3.8-27B-UD-Q4_K_XL.gguf + mmproj-BF16.gguf).
- Solved the CUDA illegal memory access crash that previously capped Ollama context at 16K: tuned micro-batching to -b 2048 -ub 1024 with q8_0 KV cache, ensuring full GPU residency with 0 WDDM shared memory paging and 0 WHEA events.
- Enabled Multi-Token Prediction (MTP) draft speculative decoding (--spec-type draft-mtp --spec-draft-n-max 3), achieving 60.9-82.7 tok/s at short/medium contexts and 34.9-41.4 tok/s at 100K context (up to ~97% generation speedup) with 55%-94% draft token acceptance.
- Tuned recurrent state checkpoints (--ctx-checkpoints 32) and 8 GB host RAM prompt caching (--cache-ram 8192 --cache-idle-slots) for multi-turn prefix reuse prefill speeds up to 1,306.8 tok/s.
- Created sanitized supervisor (Start-LlamaCppSupervisor.ps1), WSL bridge (Start-OpenClawLlamaBridge.ps1), and repeatable harness (Measure-LlamaCppInference.ps1) under platform/windows/llamacpp/.
- Published comprehensive RTX 3090 100K MTP benchmark report at platform/windows/benchmarks/rtx3090-llamacpp-tuning.md.
- Completed the user-controlled firmware work. Windows now reports firmware virtualization enabled, an active hypervisor, 32 GiB across two 3600 MT/s modules, and no WHEA event since boot. No additional firmware reboot is required by this phase.
- Started Docker Desktop after quarantining two small Docker-only local metadata directories containing stale socket files. The quarantine is recoverable; no unrelated data, source repository, credential, virtual disk, or WSL distribution was touched.
- Verified Docker client and Linux engine 29.7.2, overlay storage, and a clean initial inventory. Docker created both managed VHDX files below the approved regular-storage data root, with no active legacy Docker VHDX under the vendor local-application-data directory.
- Pulled the pinned Open WebUI 0.11.3 image, verified its immutable digest and Linux/amd64 platform, and started it from the public Compose definition with persistent data below managed regular storage.
- Verified the Open WebUI container as healthy, its host health endpoint as HTTP 200, an actual container-to-native-Ollama inference returning the requested sentinel, and a host OpenAI-compatible inference returning the requested sentinel.
- Completed the first-administrator bootstrap locally, disabled further signup in private configuration, recreated the container, and verified that the single administrator and authenticated chat records persisted. No identity or message content was inspected.
- Verified that Ollama and Open WebUI listen only on `127.0.0.1`; the smoke model is fully GPU-resident and no new WHEA event appeared during inference.
- Enabled Tailscale Serve and verified the private HTTPS path at HTTP 200. The route targets only loopback Open WebUI, does not expose the Ollama port, and has Funnel disabled.
- Updated the storage-cap scanner to allow only relative file symlinks whose ordinary-file targets and full target ancestry remain inside the same managed root. The Open WebUI embedding cache has 30 such deduplication links; it has zero unsafe reparse points, and both hard-cap checks pass.
- Pulled all three approved production models after a passing storage preflight. Every pull completed runtime SHA-256 verification, and exact public identifiers, manifest hashes, upstream revisions, licenses, quantization, sizes, and capabilities are recorded in `platform/windows/models/production-models.public.yaml`.
- Verified the general and abliterated 27B Qwen3.8 builds for chat, vision, native tool calling, JSON-schema output, and OpenAI-compatible chat. Verified the 14B Base coder for fill-in-the-middle and legacy OpenAI completions.
- Verified the running Open WebUI container can discover all three production identifiers through the existing internal host bridge while Ollama remains loopback-only.
- Benchmarked cold/warm inference, real 8K and 16K context fills, full GPU residency, controlled 48-of-65-layer RAM offload, Docker coexistence, RAM headroom, pagefile behavior, and thermal/event-log health. The repeatable harness and sanitized results are published under `platform/windows/ollama` and `platform/windows/benchmarks`.
- Established 16K as the tested production-safe ceiling for both 27B models on Ollama 0.33.3. Both 32K attempts faulted their isolated model runner with a CUDA illegal-memory-access error; Ollama recovered, Docker/Open WebUI stayed healthy, and no WHEA or display-driver event appeared.
- Recovered Docker Desktop from recurring stale Unix-socket metadata without a factory reset. Only Docker runtime socket directories were moved aside intact; the engine, existing container, persistent Open WebUI data, and authenticated state all returned healthy.
- Replaced the three opaque source tags with storage-neutral role-based aliases after verifying identical manifest digests and successful inference through every alias. Open WebUI discovers all three names; shared model weights were preserved without another download.
- Read-only hardware, storage, pagefile, runtime, and network audit.
- Confirmed that the two storage roots reside on different physical devices.
- Created the approved managed directory layout and passed cap, reserve, containment, and separate-disk preflight checks.
- Left the Windows-managed pagefile on the operating-system drive unchanged.
- Installed Ollama 0.33.3 under the managed regular-storage application root and routed its models and process-scoped pull scratch to fast storage.
- Configured Ollama for loopback-only access, one loaded model, one parallel request, five-minute keep-alive, flash attention, `q8_0` KV cache, and no global context override.
- Pulled the sub-5 GB smoke model `qwen3:0.6b` (`Q4_K_M`, Apache-2.0) and verified native chat, OpenAI-compatible chat, structured JSON output, unload/reload, and full GPU residency.
- Purged the authorized legacy Docker engine state and installed Docker Desktop 4.89.0 with its primary payload under the managed regular-storage application root. The installer also placed 0.713 GB of signed system-wide CLI-plugin integration in Docker's supported OS location; all 15 files match the managed copies. They are a documented vendor-required exception.
- Prepared and deployed a pinned Open WebUI 0.11.3 Compose definition with an immutable digest, loopback publishing, a managed bind mount, authentication, and telemetry disabled.
- Installed GitHub CLI 2.100.0 under the managed regular-storage application root.
- Replaced the vendor Ollama logon shortcut with a managed launcher; the original shortcut is backed up privately. The native runtime was already healthy at the post-reboot check; full-stack persistence remains a future verification item.
- Created coordination Issues #1 (`[Shared]`), #2 (`[Windows]`), and #3 (production-model selection).
- Published immutable model-candidate records, the final installed model manifest, and measured production recommendations.
- Firmware-change and rollback procedure documented in `docs/runbooks/windows-reboot.md`.

## Verified native-runtime smoke result

| Check | Result |
|---|---|
| Listener | `127.0.0.1:11434` only |
| Native chat | `VERIFIED` |
| OpenAI-compatible chat | `VERIFIED` |
| JSON-schema output | `VERIFIED` |
| Cold smoke-model load | 1.66 s model load; 1.84 s wall |
| Immediate warm response | 24 ms wall |
| Residency | Fully GPU-resident; 2.65 GB runtime allocation reported |

These are deployment-smoke measurements for a small model, not production coding-quality or maximum-context benchmarks. The OpenAI-compatible short-answer check used `reasoning_effort: "none"`; otherwise this reasoning model can consume a small completion budget without returning visible content.

## Production model benchmark summary

| Role | Model | Recommended context | Warm generation | Result |
|---|---|---:|---:|---|
| General coding, tools, vision | `coding-vision-tools:latest` | 8K routine, 16K ceiling | 41.0 tok/s | `READY` |
| FIM autocomplete | `code-autocomplete-fim:latest` | 8K tested | 68.3 tok/s | `READY` |
| Abliterated chat, tools, vision | `uncensored-vision-tools:latest` | 8K routine, 16K ceiling | 38.8 tok/s | `READY` |

The standard Qwen3.8 first uncached model read took 30.06 seconds; later OS-cached cold loads were 11.35-12.44 seconds. Full-GPU 16K remained pagefile-independent. Controlled offload passed at 16K but slowed warm generation to 6.4 tok/s at 8K and did not establish a higher safe context, so it is not the default. See `platform/windows/benchmarks/rtx3090-production-models.md` for the full sanitized matrix.

## Storage usage after production-model installation

| Root class | Current stack use | Hard cap | Maximum additional use now |
|---|---:|---:|---:|
| Fast | 44.991 GB | 200 GB | 100.093 GB |
| Regular | 26.327 GB | 500 GB | 473.673 GB |

The maximum-additional figures already apply both the hard cap and the live volume reserve calculation, so the operating-system reserve—not the 200 GB cap—is currently the tighter fast-storage limit. The regular-root scan includes Docker and Open WebUI data and passed with no unsafe reparse point. Funnel remains disabled. The raw Ollama API will not be served merely on the strength of tailnet membership: a least-privilege grant/ACL or authenticated proxy must first protect pull, delete, and resource-consuming operations.

## Verification qualification

- The current Codex process is not elevated, so direct Windows optional-feature metadata inspection was unavailable. Firmware state, active-hypervisor state, WSL commands, and the running Docker Linux engine provide operational proof. Rerun the verifier from an elevated PowerShell at the next convenient administrator session to close only this evidence gap.
- When the hypervisor owns the virtualization extensions, WMI may report `VMMonitorModeExtensions=false`. The verifier now accepts an active Windows hypervisor as the capability fallback while still requiring firmware virtualization.
- No automatic reboot was initiated. The pagefile remains Windows-managed on the operating-system volume and needs no change.

## Remaining work

- Remove the Docker-only socket-metadata quarantines after a longer stable operating interval; they are deliberately retained for recoverability at this checkpoint.
- Rerun the elevated verifier and complete a sustained memory-stability workload with a post-workload WHEA query.
- Retest 32K only after an Ollama/llama.cpp release explicitly addresses the Qwen3.8 CUDA hybrid-model fault; do not raise the public ceiling based on the advertised context claim.
- Verify full service persistence at a future user-controlled reboot; do not reboot merely for this check.

## Public service readiness

| Surface | State | Notes |
|---|---|---|
| Browser chat | `READY` | Administrator bootstrap is closed; authenticated chat, private HTTPS, and backend inference checkpoints pass |
| Native model API | `VERIFIED` | Local loopback smoke inference passed; private HTTPS route is not active |
| OpenAI-compatible API | `VERIFIED` | Local loopback chat and model discovery passed |
| Status interface | `DEFERRED` | Build only if existing UI is insufficient |
| Tailscale Serve | `READY` | Private HTTPS publishes only authenticated browser chat; raw Ollama is unexposed and Funnel remains disabled |

## Open coordination items

- Windows host work remains coordinated under Issue #2; the shared chat-readiness promotion is tracked in Issue #4. Production-model selection and benchmark evidence are tracked under Issue #3.
- Actual URLs, host identity, and populated storage roots remain private.
