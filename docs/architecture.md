# Architecture

Status: `PARTIALLY_IMPLEMENTED`; consult the machine status files for verified surfaces.

## Objectives

- Run inference on the Windows GPU host while allowing a Mac client to use chat and OpenAI-compatible APIs over a private tailnet.
- Keep the primary runtime simple, modular, reversible, and measurable.
- Put performance-sensitive model material in fast storage and ordinary application state in regular storage.
- Expose no service publicly and publish no machine-specific values in Git.

## Planned topology

```text
Mac clients
    |
    | private HTTPS through Tailscale Serve
    v
Windows loopback gateways
    +-- chat       -> Open WebUI
    +-- model API  -> authenticated proxy or least-privilege route
    +-- status     -> optional controller, only if existing UI is insufficient
                         |
                         +-- native Ollama on Windows loopback
                         +-- GPU inference
                         +-- model/cache data in fast storage
                         +-- application/config/data/logs in regular storage
```

The initial backend is native Windows Ollama. Open WebUI supplies the browser interface. A second llama.cpp, vLLM, or SGLang backend is added only when a reviewed model or benchmark demonstrates a concrete need. An API router is deferred until multiple active backends need a unified endpoint.

## Storage contract

| Class | Public placeholder | Hard stack cap | Intended content |
|---|---|---:|---|
| Fast | `<FAST_STORAGE_ROOT>` | 200 GB | Model weights and caches or scratch data that materially improve inference or load time |
| Regular | `<REGULAR_STORAGE_ROOT>` | 500 GB | Repositories, applications, configuration, logs, databases, Docker data, bind mounts, reports, and backups |

The caps are maximum total usage, not reservations. Every pull or conversion must also preserve the operating-system safety reserve and account for temporary plus final space. If free space makes a cap unsafe, the smaller calculated allowance wins.

All controllable bulk Docker data is planned under the regular root after the authorized clean rebuild. Windows system components, vendor system-wide CLI integration, minimal metadata, credentials, and startup integration that have no supported relocation remain in their supported operating-system or user-profile locations and are documented as private exceptions. Controllable primary application payloads and bulk mutable stack data stay under the two managed roots.

## Runtime policy

- Default to one large loaded model and one parallel request.
- Use flash attention and quantized KV cache only after verifying support and quality on the installed runtime.
- Do not force one global context size.
- Keep GPU-only and controlled RAM-offload benchmark profiles separate.
- Preserve at least 8 GB of available system RAM during RAM-offload tests and abort on material sustained paging.
- A model is ready only after a small inference succeeds.

## Network policy

- Backends listen on loopback only.
- Tailscale Serve terminates private HTTPS according to `docs/contracts/service-map.public.yaml`.
- Funnel stays disabled.
- No public or LAN firewall rule is part of this design.
- The raw Ollama API is unauthenticated and is not exposed to the tailnet until a least-privilege ACL/grant or authenticated proxy is verified.
- Open WebUI's container-to-native-runtime path is a post-reboot security gate. Do not widen Ollama to a broad listener to make `host.docker.internal` work; use a constrained internal bridge or a verified alternative deployment.
- Real tailnet identifiers and URLs are injected through ignored private configuration.

## Firmware dependency

Docker and WSL-backed workloads remain blocked until CPU virtualization is enabled in firmware. The memory profile also requires a firmware change to restore the modules' intended speed. Both changes are combined into one user-controlled maintenance reboot; see `docs/runbooks/windows-reboot.md`.
