# Windows platform

Owner: Windows

These assets are sanitized and contain no machine identity, populated storage path, private URL, or credential. A populated environment file belongs below the private regular-storage configuration area and outside this public repository.

## Included assets

| Asset | Purpose | Mutates state when run |
|---|---|---|
| `windows.public.env.example` | Complete placeholder-only private configuration template | No |
| `config/Import-LocalAiEnvironment.ps1` | Validates paths, policy, and values; optionally loads the current PowerShell process | Process environment only unless `-ValidateOnly` |
| `storage/Test-StoragePreflight.ps1` | Enforces the 200 GB fast cap, 500 GB regular cap, live filesystem reserve, and separate-physical-disk requirement | Only with an explicit create/report option |
| `ollama/Set-OllamaRuntimeEnvironment.ps1` | Applies conservative Ollama settings at process or user scope | Yes, explicitly scoped |
| `ollama/Start-Ollama.ps1` | Starts the managed native binary on loopback and verifies its process, version, and API | Yes |
| `ollama/Test-OllamaRuntime.ps1` | Read-only listener, process-path, pinned-version, and API health check | Only if a private report is requested |
| `ollama/Measure-OllamaInference.ps1` | Repeatable performance and residency benchmark with RAM/pagefile guardrails | Only if a private report is requested |
| `models/production-models.public.yaml` | Exact installed model identifiers, immutable hashes, sources, licenses, and verified capabilities | No |
| `benchmarks/rtx3090-production-models.md` | Sanitized RTX 3090 benchmark results and production recommendations | No |
| `docker/compose.open-webui.yaml` | Loopback-only Open WebUI service with a bind-mounted regular-storage data directory | No by itself |
| `docker/Test-OpenWebUiCompose.ps1` | Checks the pin, bind policy, secret, signup state, and optional Compose rendering | No |
| `verification/Test-PostReboot.ps1` | Checks virtualization, memory speed, WSL, WHEA, NVIDIA, Docker, and storage after the user reboot | Only if a private report is requested |
| `tests/Test-PlatformWindowsScripts.ps1` | Static and module self-tests that create no files and start no services | No |

The Ollama configuration is pinned to `0.33.3` and the managed Docker Desktop executable to exact file version `4.89.0.238018` by the public example. Open WebUI is pinned to the official `v0.11.3` package/index digest `sha256:751b617714b91e4cfd0186a509c72480c858e012976103b09a30dad053c36175`; its selected Linux/amd64 child digest is recorded in the Compose file.

## Private environment

Copy `windows.public.env.example` to a private location such as `<REGULAR_STORAGE_ROOT>\Config\local-ai-stack\windows.env`. Replace every angle-bracket placeholder, generate a unique Open WebUI secret of at least 32 characters, and never add the populated file to Git.

Validate without changing the current process:

```powershell
& .\platform\windows\config\Import-LocalAiEnvironment.ps1 `
    -Path '<REGULAR_STORAGE_ROOT>\Config\local-ai-stack\windows.env' `
    -RequireOpenWebUiSecret `
    -ValidateOnly `
    -PassThru
```

The loader rejects unresolved placeholders, unknown or duplicate keys, roots that contain one another, stack paths outside the two managed roots, non-loopback service binds, Funnel enablement, a malformed Ollama version, and quantized KV cache without flash-attention enablement. It never prints secret values.

## Storage preflight

Run preflight before every download, extraction, image pull, conversion, or large cache operation. Supply the maximum simultaneous download, installed, and temporary byte counts—not only the final artifact size.

```powershell
& .\platform\windows\storage\Test-StoragePreflight.ps1 `
    -FastStorageRoot '<FAST_STORAGE_ROOT>' `
    -RegularStorageRoot '<REGULAR_STORAGE_ROOT>' `
    -FastExpectedDownloadBytes 0 `
    -FastExpectedInstallBytes 0 `
    -FastExpectedTempBytes 0 `
    -RegularExpectedDownloadBytes 0 `
    -RegularExpectedInstallBytes 0 `
    -RegularExpectedTempBytes 0
```

Caps use decimal bytes: 200,000,000,000 fast and 500,000,000,000 regular. The operating-system volume must additionally retain the larger of 50 GB or 15% of its capacity. External, broken, chained, and directory reparse points block a pass because following them could touch unrelated data and skipping them could undercount usage. A relative file symlink is allowed only when its ordinary-file target and every target ancestor remain inside the same managed root; the target bytes are counted through their normal directory to avoid duplication. Private JSON reports are accepted only below the regular root and outside this repository.

## Ollama

`Start-Ollama.ps1` requires the executable to be inside the configured regular-storage install path and requires an exact expected version unless `-AllowUnpinnedVersion` is deliberately supplied. It sets one loaded model, one parallel request, loopback binding, conservative keep-alive, managed fast-storage models/scratch, and `OLLAMA_NO_CLOUD=1`. It never sets a global context length.

The installed `0.33.3` help confirms `OLLAMA_NO_CLOUD`; it does not advertise `OLLAMA_NOHISTORY` or `OLLAMA_TMPDIR`, so those unsupported variables are omitted. The launcher redirects `TEMP` and `TMP` only long enough for the spawned Ollama process to inherit fast scratch, then restores its own values. User- and machine-level generic temporary-directory settings are never changed.

Flash attention and `q8_0` KV cache are enabled in the example because the installed production models passed inference, vision, tool-call, schema, residency, and pagefile checks with that combination. The tested production ceiling for the Qwen3.8 27B models is 16K; do not infer the advertised 262K limit is usable. A successful runtime health check still reports `Ready = false`; readiness requires a small inference.

## Open WebUI

The Compose template publishes container port 8080 exclusively as `127.0.0.1:3000`, mounts no Docker socket, requires an external secret, and bind-mounts all persistent application data from `OPEN_WEBUI_DATA` below the regular root. `OPEN_WEBUI_OLLAMA_BASE_URL` is a post-reboot bridge candidate, not a readiness claim: a Docker container normally cannot reach a Windows service that listens only on host loopback through `host.docker.internal`. Do not widen Ollama to `0.0.0.0`. Discover and test a bridge constrained to Docker's internal path, confirm that no LAN/public listener appears, and complete a small UI inference before declaring the UI ready.

Keep `OPEN_WEBUI_ENABLE_SIGNUP=false` normally. For a new database, enable it only for the controlled first-admin bootstrap while the service is still loopback-only, create the first administrator, set it back to false, recreate the container, and only then configure private Tailscale Serve exposure.

Render and validate without starting a container:

```powershell
& .\platform\windows\docker\Test-OpenWebUiCompose.ps1 `
    -EnvironmentFile '<REGULAR_STORAGE_ROOT>\Config\local-ai-stack\windows.env' `
    -ValidateWithDockerCompose
```

Do not run `docker compose up` until the user-controlled firmware reboot is complete, the Docker engine has been manually started, its data location is verified below the regular root, and storage preflight passes for the image pull.

Do not expose Ollama's raw, unauthenticated API through Tailscale Serve merely because Funnel is disabled. The separate API route remains blocked until a least-privilege tailnet policy or an authenticated proxy is implemented and tested. Open WebUI's authenticated surface may be used instead if it satisfies the Mac client contract.

## Post-reboot verification

Run the post-reboot check from an elevated PowerShell after the user has enabled firmware virtualization and the supported memory profile, allowed Windows to boot, and manually started Docker Desktop:

```powershell
& .\platform\windows\verification\Test-PostReboot.ps1 `
    -EnvironmentFile '<REGULAR_STORAGE_ROOT>\Config\local-ai-stack\windows.env' `
    -ExpectedMemorySpeedMTs 3600
```

The verifier never reboots Windows and never starts Docker, WSL distributions, containers, or Ollama. By default it requires exactly 32 GiB across two memory modules at the selected speed. It also requires the configured managed Docker CLI with no `PATH` fallback, the exact managed Docker Desktop executable version, matching `wslDefaultDataRoot` in Docker Desktop's installation settings, a nonempty VHDX below that configured root after engine start, and no legacy Docker VHD/VHDX below the user's local application-data Docker directory. Use `-SkipDockerEngine` only for an intermediate firmware/WSL check before Docker is manually started. Any WHEA event since boot blocks a pass by default; after a separate stability workload, rerun with `-WheaObservationStartUtc` set to the workload start time.

All destructive Docker cleanup remains outside these scripts. It must resolve Docker objects explicitly and must never delete unrelated files, source repositories, credentials, virtual disks by pathname, or WSL distributions.
