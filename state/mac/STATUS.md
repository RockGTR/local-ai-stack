# Mac status

Last updated: 2026-09-12
Owner: Mac
Lifecycle: `LOCAL_HARNESS_VERIFIED`
Overall state: the Mac can reach the Windows Tailscale peer and run a local DeepSeek Harness UI. The browser route was previously verified, but its latest check returned HTTP 502; remote chat, model management, and inference await Windows Open WebUI availability.

## Sanitized baseline

- Hardware class: Apple Silicon Mac with 16 GB unified memory.
- Operating-system class: macOS 26.
- Tailscale is connected. Peer reachability and MagicDNS resolution passed.
- The private HTTPS request reached the Windows peer rather than the Mac, returned HTTP 200, negotiated TLS 1.3, and passed certificate validation without a bypass.
- The route identifies Open WebUI 0.11.3, reports that public signup is disabled, and presents the existing-account login path.
- The latest route check reached the Windows peer but returned HTTP 502. No repeat polling was performed; the likely loopback backend availability issue remains for Windows to verify.
- A permission-restricted populated client config exists outside the public repository. No global environment variable was added.
- The public Mac scripts use only the browser-chat URL. They do not configure or probe the blocked raw model APIs.
- A Mac launcher opens the administrator-only Open WebUI model-management page through the same private HTTPS route. It does not start a pull or store credentials.
- Official DeepSeek Harness 0.1.5-rc.2 is installed in user scope and runs with an explicitly selected Node 22 runtime. Its npm registry signatures and attestations passed verification.
- Harness generated state and credentials storage are permission restricted outside the repository. No provider credential is configured.
- No local model runtime or model was installed.

## Capability status

| Capability | State | Notes |
|---|---|---|
| Tailscale peer reachability | `VERIFIED` | Direct peer response passed |
| MagicDNS | `VERIFIED` | Private peer hostname resolved |
| Private HTTPS and certificate | `VERIFIED` | HTTP 200; normal trust validation passed |
| Open WebUI route and closed signup | `VERIFIED` | Version and public configuration matched the Windows handoff |
| Windows model-manager launcher | `BLOCKED` | Launcher is installed, but its required route check currently returns HTTP 502; no pull has been authorized or tested |
| Authenticated browser inference | `BLOCKED` | Requires the user to sign in with the existing private account and run a small chat |
| DeepSeek Harness local UI | `VERIFIED` | Pinned CLI booted on loopback, served its UI, and shut down cleanly |
| DeepSeek Harness model provider | `BLOCKED` | No credential configured; protected Windows API is unavailable |
| Native Ollama API | `BLOCKED` | Windows intentionally leaves the raw API unexposed |
| OpenAI-compatible API | `BLOCKED` | Await an authenticated proxy or least-privilege policy |
| Dashboard | `PLANNED` | Shared contract marks it optional and deferred |

## Mac client files

- `platform/mac/mac-client.public.env.example`: placeholder-only configuration template.
- `platform/mac/Test-MacClient.sh`: Tailscale, DNS, TLS, route, and closed-signup verification.
- `platform/mac/Open-PrivateChat.sh`: opens the populated private chat URL in the default browser.
- `platform/mac/Open-WindowsModelManager.sh`: opens the authenticated Open WebUI administrator model page without calling raw Ollama.
- `platform/mac/Start-DeepSeekHarness.sh`: starts the pinned user-local Harness on loopback.
- `platform/mac/deepseek-harness.public.yaml`: immutable package and verification record.

## Known local follow-up

- The installed Tailscale CLI and running GUI/daemon have different versions. Current connectivity passes; reconcile versions only during an authorized maintenance step.
- The default Homebrew Node.js runtime remains unusable because of a missing dynamic-library dependency. Harness uses a separate existing compatible Node 22 runtime; the default was not repaired or relinked.
- Local model downloads remain inappropriate until disk headroom is addressed and a Mac-local runtime is explicitly required.
- The private browser route must return HTTP 200 again before chat or the model-manager launcher can proceed.

Browser-client work is tracked in Issue #5. Harness installation is tracked in Issue #6. Remote model-manager launching is tracked in Issue #7; production-model selection remains in Issue #3.
