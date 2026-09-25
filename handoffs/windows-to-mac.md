# Windows-to-Mac handoff

Last updated: 2026-09-24
Owner: Windows
Stage: `PRODUCTION_MODELS_READY`

## Current outcome

The user-controlled firmware work is complete. Windows reports virtualization enabled, an active hypervisor, both 16 GB memory modules at 3600 MT/s, and no WHEA event since the successful boot. No additional firmware reboot is required by this phase.

Ollama 0.33.3 remains Windows-loopback-only. The approved production set is installed and ready:

- `coding-vision-tools:latest` for general coding, agentic chat, tools, structured output, and vision.
- `code-autocomplete-fim:latest` for fill-in-the-middle autocomplete and legacy completions.
- `uncensored-vision-tools:latest` for the requested abliterated chat/tools/vision role.

These are verified, storage-neutral aliases of the immutable source artifacts recorded in `platform/windows/models/production-models.public.yaml`. Open WebUI discovers all three aliases through its internal host bridge.

Both 27B builds are fully GPU-resident through a verified 16K context and fail at 32K with the same isolated CUDA illegal-memory-access runner fault. Use 8K routinely and treat 16K as the hard production ceiling on the tested runtime. Warm generation is approximately 41.0 tok/s for standard Qwen3.8, 38.8 tok/s for the abliterated build, and 68.3 tok/s for 14B FIM completion. Controlled RAM offload passed at 16K but is roughly 6x slower for generation and did not yield a higher verified context.

Docker Desktop 4.89.0 is operational with its WSL data disks below managed regular storage. The Docker client and Linux engine are version 29.7.2, and the clean engine initially contained no containers, images, or volumes. The pinned Open WebUI 0.11.3 container is healthy on loopback. Container-to-native-Ollama inference, host OpenAI-compatible inference, loopback listener restrictions, GPU residency, storage caps, and physical-disk separation all pass. The first administrator exists, further signup is disabled, and container recreation preserved the authenticated data. A private Tailscale HTTPS route now publishes only Open WebUI; it passed HTTP 200, exposes no raw Ollama port, and has Funnel disabled.

During model benchmarking, Docker Desktop encountered stale runtime Unix sockets after a controlled stop. Only the Docker-owned socket directories were moved aside intact. Docker, its WSL engine, the existing Open WebUI container, its health endpoint, and persistent authenticated state are healthy again; no factory reset occurred.


### High-Context llama.cpp Runtime (100K Context + MTP)

Windows has deployed and benchmarked a tuned llama.cpp sidecar runtime serving unsloth-Qwen-3.8 (27.3B) with:
- **100,000-token verified stable context ceiling** fully GPU-resident on the RTX 3090 24GB.
- **Multi-Token Prediction (MTP) Speculative Decoding**: generation speeds up to 82.7 tok/s at 4K context and 35–41 tok/s at 100K context (draft acceptance 55%–94%).
- Host RAM prompt caching (8 GB) and recurrent checkpoints (--ctx-checkpoints 32).
- Open WebUI discovers unsloth-Qwen-3.8 through the internal bridge. Mac clients can select unsloth-Qwen-3.8 in Open WebUI or via the authenticated Tailscale model API.
- See [platform/windows/benchmarks/rtx3090-llamacpp-tuning.md](../platform/windows/benchmarks/rtx3090-llamacpp-tuning.md) for full benchmark details.

## What the Mac can do now

1. Pull the repository and read `AGENTS.md`, `state/windows/STATUS.md`, `docs/architecture.md`, and the two public contracts.
2. Prepare client configuration using placeholders only; keep populated values outside Git.
3. Read `platform/windows/models/production-models.public.yaml` and `platform/windows/benchmarks/rtx3090-production-models.md`; these supersede the proposal-only language in the older candidate comparison for the Windows installed inventory.
4. Use `coding-vision-tools:latest` as the default interactive model, `code-autocomplete-fim:latest` only for FIM/autocomplete, and `uncensored-vision-tools:latest` when the abliterated variant is intentionally selected.
5. Configure 8K as the routine client context and never request more than 16K from either 27B model until Windows publishes a newer verified ceiling. Keep `reasoning_effort: "none"` available for concise OpenAI-compatible Qwen3.8 calls.
6. Review shared contract work in Issue #1, Windows progress in Issue #2, and production-model evidence in Issue #3.
7. Obtain the populated `<WINDOWS_CHAT_URL>` through the private out-of-band bundle, sign in with the existing Open WebUI account, and test each intended model through authenticated browser chat. The public repository deliberately contains only the placeholder.
8. Update only Mac-owned status, handoff, platform files, and Mac public manifests unless coordinating a shared change.

## Do not do yet

- Do not attempt the raw Ollama or OpenAI-compatible endpoint; only authenticated browser chat is remotely ready.
- Do not publish a private hostname, address, URL, storage path, or credential.
- Do not mark Windows services ready from the Mac side.
- Do not configure a 32K or advertised 262K context for either 27B build; 32K is a tested runtime failure on this host.
- Do not use the Base coder as a chat assistant. Its verified role is fill-in-the-middle/autocomplete.
- Do not treat `qwen3:0.6b` as a selected model; it remains only a deployment smoke fixture.

## Next synchronization point

Pull this production-model-ready handoff now. Configure the three exact model roles above, use an 8K default and 16K ceiling for the 27B models, then test authenticated browser chat using the populated `<WINDOWS_CHAT_URL>` supplied out of band. Record the result only in Mac-owned status and handoff files, keep the real URL private, and leave raw model API integration blocked until an authenticated proxy or least-privilege API policy is implemented and tested.
