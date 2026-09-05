# Windows-to-Mac handoff

Last updated: 2026-09-04
Owner: Windows
Stage: `PRE_REBOOT`

## Current outcome

The Windows audit, managed storage layout, native runtime smoke deployment, Docker clean reinstall, and public coordination scaffold are complete. Docker-backed services are not ready because firmware virtualization is disabled. RAM is also running below its rated profile. Both firmware changes are planned for one user-controlled reboot; Windows will not reboot automatically.

Ollama 0.33.3 is verified only on Windows loopback with the `qwen3:0.6b` smoke model. Native chat, OpenAI-compatible chat, structured output, controlled unload/reload, and full GPU residency passed. The small model loaded cold in 1.66 seconds and returned the immediate warm check in 24 milliseconds. These are smoke measurements, not a recommended coding-model benchmark.

Docker Desktop 4.89.0 is installed with its primary payload and clean WSL data root in managed storage. Its installer also requires signed system-wide CLI-plugin copies in the supported OS integration location; this documented 0.713 GB exception was not deleted. The Open WebUI 0.11.3 Compose definition is pinned by digest. Neither Docker nor Open WebUI can be verified until the firmware reboot. The container-to-loopback Ollama bridge must be proven without a broad host listener. Tailscale Serve also needs tailnet-owner enablement and least-privilege access control before private HTTPS routes can be applied; the raw unauthenticated Ollama API will not be exposed by default. No public service endpoint should be considered available.

## What the Mac can do now

1. Pull the repository and read `AGENTS.md`, `state/windows/STATUS.md`, `docs/architecture.md`, and the two public contracts.
2. Prepare client configuration using placeholders only; keep populated values outside Git.
3. Review shared contract work in Issue #1, Windows progress in Issue #2, and the pending model choice in Issue #3.
4. Prepare Mac client configuration with `reasoning_effort: "none"` available for concise Qwen3-compatible smoke checks, while keeping model-specific behavior configurable.
5. Review `docs/model-candidates.md`; its production models are proposals, not an installed inventory.
6. Treat ports and routes in `service-map.public.yaml` as unavailable until Windows reports the private route `READY`.
7. Update only Mac-owned status, handoff, platform files, and Mac public manifests unless coordinating a shared change.

## Do not do yet

- Do not attempt connectivity or diagnose a missing endpoint.
- Do not publish a private hostname, address, URL, storage path, or credential.
- Do not mark Windows services ready from the Mac side.
- Do not assume a model identifier or API feature is available until Windows records a tested model.
- Do not treat `qwen3:0.6b` as the selected coding or vision model; it is a deployment smoke fixture only.

## Next synchronization point

Pull this pre-reboot handoff now and prepare the Mac-owned client templates. Wait for `state/windows/STATUS.md` to report `POST_REBOOT_VERIFIED` before attempting connectivity. Windows will then provide a sanitized list of ready surfaces and a private out-of-band configuration bundle containing the actual placeholders' values.
