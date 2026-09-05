# Windows status

Last updated: 2026-09-04
Owner: Windows
Lifecycle: `PRE_REBOOT`
Overall state: `PARTIALLY_VERIFIED`; Docker/Open WebUI remain `BLOCKED` on the user-controlled firmware changes.

## Sanitized verified baseline

- Hardware class: Windows 11, AMD Ryzen 9 5900X, RTX 3090 with 24 GB VRAM, and 32 GB DDR4 RAM.
- Storage class: the fast and regular roots are on separate physical NVMe SSDs.
- Stack caps: 200 GB fast and 500 GB regular, additionally constrained by live free space and the operating-system reserve.
- Memory is currently configured below the kit's rated profile.
- CPU virtualization is currently disabled in firmware, blocking Docker/WSL-backed runtime work.
- The pagefile is already Windows-managed on the operating-system drive and is not scheduled to move.
- The old Docker engine data was purged under the explicit Docker-only authorization. No unrelated files, repositories, credentials, or WSL distributions were deleted.
- Tailscale 1.102.3 is connected and Funnel is disabled. Private device and network values are intentionally omitted.
- The native runtime is verified locally. The Docker-backed browser UI cannot start until firmware virtualization is enabled.

## Completed

- Read-only hardware, storage, pagefile, runtime, and network audit.
- Confirmed that the two storage roots reside on different physical devices.
- Created the approved managed directory layout and passed cap, reserve, containment, and separate-disk preflight checks.
- Left the Windows-managed pagefile on the operating-system drive unchanged.
- Installed Ollama 0.33.3 under the managed regular-storage application root and routed its models and process-scoped pull scratch to fast storage.
- Configured Ollama for loopback-only access, one loaded model, one parallel request, five-minute keep-alive, flash attention, `q8_0` KV cache, and no global context override.
- Pulled the sub-5 GB smoke model `qwen3:0.6b` (`Q4_K_M`, Apache-2.0) and verified native chat, OpenAI-compatible chat, structured JSON output, unload/reload, and full GPU residency.
- Purged the authorized legacy Docker engine state, installed Docker Desktop 4.89.0 with its primary payload under the managed regular-storage application root, and prepared a clean WSL data root there. The installer also placed 0.713 GB of signed system-wide CLI-plugin integration in Docker's supported OS location; all 15 files match the managed copies. They were documented rather than deleted. A small reboot-held Docker-only quarantine remains for deletion after the manual reboot.
- Prepared a pinned Open WebUI 0.11.3 Compose definition with an immutable digest, loopback publishing, a managed bind mount, authentication, and telemetry disabled. Its container-to-native-Ollama bridge is explicitly unverified and blocked until a constrained post-reboot path is proven.
- Installed GitHub CLI 2.100.0 under the managed regular-storage application root.
- Replaced the vendor Ollama logon shortcut with a managed launcher; the original shortcut is backed up privately. Persistence remains unverified until the user-controlled reboot.
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

## Storage usage at the pre-reboot checkpoint

| Root class | Current stack use | Hard cap | Maximum additional use now |
|---|---:|---:|---:|
| Fast | 0.523 GB | 200 GB | 199.477 GB |
| Regular | 9.052 GB | 500 GB | 490.948 GB |

The maximum-additional figures already apply the live cap and OS-volume reserve calculation. No safe local setup step remains before the firmware restart. Tailscale Serve still requires separate tailnet-owner enablement; it is not a reason to delay the firmware work, and Funnel must remain disabled. The raw Ollama API will not be served merely on the strength of tailnet membership: a least-privilege grant/ACL or authenticated proxy must first protect pull, delete, and resource-consuming operations.

## Deferred until after the user-controlled reboot

- Verify firmware virtualization and memory profile.
- Start WSL 2 and the Docker Linux engine.
- Validate that Docker creates and uses its clean data disk under the approved managed regular-storage root, then remove the reboot-held Docker-only quarantine.
- Pull and start the pinned Open WebUI image and verify that its container can reach the loopback-native Ollama service through the supported host bridge.
- Start and verify the chat UI, native model API, OpenAI-compatible API, and private HTTPS routes.
- Download any model larger than 5 GB; each requires a separate exact model proposal and approval.
- Run GPU-only and RAM-offload context benchmarks.
- Verify service persistence across reboot.

## Public service readiness

| Surface | State | Notes |
|---|---|---|
| Browser chat | `PLANNED` | Not reachable yet |
| Native model API | `VERIFIED` | Local loopback smoke inference passed; private HTTPS route is not active |
| OpenAI-compatible API | `VERIFIED` | Local loopback chat and model discovery passed |
| Status interface | `DEFERRED` | Build only if existing UI is insufficient |
| Tailscale Serve | `BLOCKED` | Owner enablement and per-surface access-control verification are required; Funnel remains disabled |

## Open coordination items

- Continue Windows implementation under Issue #2, shared contract work under Issue #1, and explicit model selection under Issue #3.
- Actual URLs, host identity, and populated storage roots remain private.
