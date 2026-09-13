# Windows status

Last updated: 2026-09-12
Owner: Windows
Lifecycle: `POST_REBOOT_VERIFIED`
Overall state: `PRIVATE_CHAT_READY`; the authenticated browser UI is available through private HTTPS, while raw model APIs remain intentionally unexposed.

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

## Completed

- Completed the user-controlled firmware work. Windows now reports firmware virtualization enabled, an active hypervisor, 32 GiB across two 3600 MT/s modules, and no WHEA event since boot. No additional firmware reboot is required by this phase.
- Started Docker Desktop after quarantining two small Docker-only local metadata directories containing stale socket files. The quarantine is recoverable; no unrelated data, source repository, credential, virtual disk, or WSL distribution was touched.
- Verified Docker client and Linux engine 29.7.2, overlay storage, and a clean initial inventory. Docker created both managed VHDX files below the approved regular-storage data root, with no active legacy Docker VHDX under the vendor local-application-data directory.
- Pulled the pinned Open WebUI 0.11.3 image, verified its immutable digest and Linux/amd64 platform, and started it from the public Compose definition with persistent data below managed regular storage.
- Verified the Open WebUI container as healthy, its host health endpoint as HTTP 200, an actual container-to-native-Ollama inference returning the requested sentinel, and a host OpenAI-compatible inference returning the requested sentinel.
- Completed the first-administrator bootstrap locally, disabled further signup in private configuration, recreated the container, and verified that the single administrator and authenticated chat records persisted. No identity or message content was inspected.
- Verified that Ollama and Open WebUI listen only on `127.0.0.1`; the smoke model is fully GPU-resident and no new WHEA event appeared during inference.
- Enabled Tailscale Serve and verified the private HTTPS path at HTTP 200. The route targets only loopback Open WebUI, does not expose the Ollama port, and has Funnel disabled.
- Updated the storage-cap scanner to allow only relative file symlinks whose ordinary-file targets and full target ancestry remain inside the same managed root. The Open WebUI embedding cache has 30 such deduplication links; it has zero unsafe reparse points, and both hard-cap checks pass.
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
- Published immutable model-candidate records and exact download choices; no production model has been selected or downloaded.
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

## Storage usage at the post-reboot local-service checkpoint

| Root class | Current stack use | Hard cap | Maximum additional use now |
|---|---:|---:|---:|
| Fast | 0.523 GB | 200 GB | 199.477 GB |
| Regular | 19.124 GB | 500 GB | 480.876 GB |

The maximum-additional figures already apply the live cap and OS-volume reserve calculation. The regular-root scan includes Docker and Open WebUI data and passed with no unsafe reparse point. Funnel remains disabled. The raw Ollama API will not be served merely on the strength of tailnet membership: a least-privilege grant/ACL or authenticated proxy must first protect pull, delete, and resource-consuming operations.

## Verification qualification

- The current Codex process is not elevated, so direct Windows optional-feature metadata inspection was unavailable. Firmware state, active-hypervisor state, WSL commands, and the running Docker Linux engine provide operational proof. Rerun the verifier from an elevated PowerShell at the next convenient administrator session to close only this evidence gap.
- When the hypervisor owns the virtualization extensions, WMI may report `VMMonitorModeExtensions=false`. The verifier now accepts an active Windows hypervisor as the capability fallback while still requiring firmware virtualization.
- No automatic reboot was initiated. The pagefile remains Windows-managed on the operating-system volume and needs no change.

## Remaining work

- Remove the Docker-only socket-metadata quarantines after a longer stable operating interval; they are deliberately retained for recoverability at this checkpoint.
- Rerun the elevated verifier and complete a sustained memory-stability workload with a post-workload WHEA query.
- Download any model larger than 5 GB; each requires a separate exact model proposal and approval.
- Run GPU-only and RAM-offload context benchmarks.
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

- Windows host work remains coordinated under Issue #2; the shared chat-readiness promotion is tracked in Issue #4. Explicit production-model selection remains open under Issue #3.
- Actual URLs, host identity, and populated storage roots remain private.
