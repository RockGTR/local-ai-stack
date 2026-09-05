# Decision 0001: Windows baseline runtime and storage split

Status: accepted for the pre-reboot baseline

## Decision

- Use native Windows Ollama 0.33.3 as the initial GGUF runtime.
- Keep model weights and process-scoped download scratch under the 200 GB fast-storage contract.
- Keep applications, configuration, logs, Docker state, Open WebUI data, reports, and repositories under the 500 GB regular-storage contract.
- Use Docker Desktop 4.89.0 with the WSL 2 backend for the pinned Open WebUI 0.11.3 deployment after firmware virtualization is enabled.
- Bind application services to loopback and use Tailscale Serve for private HTTPS. Funnel remains disabled.
- Add a second inference backend or API router only when an approved model or repeatable benchmark demonstrates a concrete need.

## Rationale

Native Ollama minimizes operational complexity for ordinary GGUF use and supports the required native and OpenAI-compatible smoke surfaces on the Windows GPU host. The storage split keeps latency-sensitive model material on the fast device while making ordinary application state easier to inspect, back up, and cap. Deferring additional runtimes avoids committing RAM, VRAM, disk, and maintenance overhead before a workload justifies it.

## Verification boundary

The native loopback smoke path is verified with `qwen3:0.6b`. Docker, Open WebUI, private HTTPS, large coding/vision models, maximum context, and RAM-offload behavior remain unverified until their explicit milestones pass.
