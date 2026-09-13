# Windows-to-Mac handoff

Last updated: 2026-09-12
Owner: Windows
Stage: `PRIVATE_CHAT_READY`

## Current outcome

The user-controlled firmware work is complete. Windows reports virtualization enabled, an active hypervisor, both 16 GB memory modules at 3600 MT/s, and no WHEA event since the successful boot. No additional firmware reboot is required by this phase.

Ollama 0.33.3 is verified only on Windows loopback with the `qwen3:0.6b` smoke model. Native chat, OpenAI-compatible chat, structured output, controlled unload/reload, and full GPU residency passed. The small model loaded cold in 1.66 seconds and returned the immediate warm check in 24 milliseconds. These are smoke measurements, not a recommended coding-model benchmark.

Docker Desktop 4.89.0 is operational with its WSL data disks below managed regular storage. The Docker client and Linux engine are version 29.7.2, and the clean engine initially contained no containers, images, or volumes. The pinned Open WebUI 0.11.3 container is healthy on loopback. Container-to-native-Ollama inference, host OpenAI-compatible inference, loopback listener restrictions, GPU residency, storage caps, and physical-disk separation all pass. The first administrator exists, further signup is disabled, and container recreation preserved the authenticated data. A private Tailscale HTTPS route now publishes only Open WebUI; it passed HTTP 200, exposes no raw Ollama port, and has Funnel disabled.

## What the Mac can do now

1. Pull the repository and read `AGENTS.md`, `state/windows/STATUS.md`, `docs/architecture.md`, and the two public contracts.
2. Prepare client configuration using placeholders only; keep populated values outside Git.
3. Review shared contract work in Issue #1, Windows progress in Issue #2, and the pending model choice in Issue #3.
4. Prepare Mac client configuration with `reasoning_effort: "none"` available for concise Qwen3-compatible smoke checks, while keeping model-specific behavior configurable.
5. Review `docs/model-candidates.md`; its production models are proposals, not an installed inventory.
6. Obtain the populated `<WINDOWS_CHAT_URL>` through the private out-of-band bundle, sign in with the existing Open WebUI account, and run a small chat check. The public repository deliberately contains only the placeholder.
7. Update only Mac-owned status, handoff, platform files, and Mac public manifests unless coordinating a shared change.

## Do not do yet

- Do not attempt the raw Ollama or OpenAI-compatible endpoint; only authenticated browser chat is remotely ready.
- Do not publish a private hostname, address, URL, storage path, or credential.
- Do not mark Windows services ready from the Mac side.
- Do not assume a model identifier or API feature is available until Windows records a tested model.
- Do not treat `qwen3:0.6b` as the selected coding or vision model; it is a deployment smoke fixture only.

## Next synchronization point

Pull this private-chat-ready handoff now. The Mac may test authenticated browser chat using the populated `<WINDOWS_CHAT_URL>` supplied out of band. Record the result only in Mac-owned status and handoff files, keep the real URL private, and leave raw model API integration blocked until an authenticated proxy or least-privilege API policy is implemented and tested.
