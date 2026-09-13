# Mac status

Last updated: 2026-09-12
Owner: Mac
Lifecycle: `LOCAL_HARNESS_VERIFIED`
Overall state: the Mac can reach the authenticated browser-chat route and run a local DeepSeek Harness UI; model inference remains blocked pending interactive browser authentication or a protected API provider.

## Sanitized baseline

- Hardware class: Apple Silicon Mac with 16 GB unified memory.
- Operating-system class: macOS 26.
- Tailscale is connected. Peer reachability and MagicDNS resolution passed.
- The private HTTPS request reached the Windows peer rather than the Mac, returned HTTP 200, negotiated TLS 1.3, and passed certificate validation without a bypass.
- The route identifies Open WebUI 0.11.3, reports that public signup is disabled, and presents the existing-account login path.
- A permission-restricted populated client config exists outside the public repository. No global environment variable was added.
- The public Mac scripts use only the browser-chat URL. They do not configure or probe the blocked raw model APIs.
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
- `platform/mac/Start-DeepSeekHarness.sh`: starts the pinned user-local Harness on loopback.
- `platform/mac/deepseek-harness.public.yaml`: immutable package and verification record.

## Known local follow-up

- The installed Tailscale CLI and running GUI/daemon have different versions. Current connectivity passes; reconcile versions only during an authorized maintenance step.
- The default Homebrew Node.js runtime remains unusable because of a missing dynamic-library dependency. Harness uses a separate existing compatible Node 22 runtime; the default was not repaired or relinked.
- Local model downloads remain inappropriate until disk headroom is addressed and a Mac-local runtime is explicitly required.

Browser-client work is tracked in Issue #5. Harness installation is tracked in Issue #6.
