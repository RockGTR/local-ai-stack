# Mac status

Last updated: 2026-09-12
Owner: Mac
Lifecycle: `PRIVATE_CHAT_ROUTE_VERIFIED`
Overall state: the Mac can reach the authenticated browser-chat route through private HTTPS; an authenticated small inference remains an interactive user checkpoint.

## Sanitized baseline

- Hardware class: Apple Silicon Mac with 16 GB unified memory.
- Operating-system class: macOS 26.
- Tailscale is connected. Peer reachability and MagicDNS resolution passed.
- The private HTTPS request reached the Windows peer rather than the Mac, returned HTTP 200, negotiated TLS 1.3, and passed certificate validation without a bypass.
- The route identifies Open WebUI 0.11.3, reports that public signup is disabled, and presents the existing-account login path.
- A permission-restricted populated client config exists outside the public repository. No global environment variable was added.
- The public Mac scripts use only the browser-chat URL. They do not configure or probe the blocked raw model APIs.
- No local model runtime, model, or DeepSeek Harness component was installed.

## Capability status

| Capability | State | Notes |
|---|---|---|
| Tailscale peer reachability | `VERIFIED` | Direct peer response passed |
| MagicDNS | `VERIFIED` | Private peer hostname resolved |
| Private HTTPS and certificate | `VERIFIED` | HTTP 200; normal trust validation passed |
| Open WebUI route and closed signup | `VERIFIED` | Version and public configuration matched the Windows handoff |
| Authenticated browser inference | `BLOCKED` | Requires the user to sign in with the existing private account and run a small chat |
| Native Ollama API | `BLOCKED` | Windows intentionally leaves the raw API unexposed |
| OpenAI-compatible API | `BLOCKED` | Await an authenticated proxy or least-privilege policy |
| Dashboard | `PLANNED` | Shared contract marks it optional and deferred |

## Mac client files

- `platform/mac/mac-client.public.env.example`: placeholder-only configuration template.
- `platform/mac/Test-MacClient.sh`: Tailscale, DNS, TLS, route, and closed-signup verification.
- `platform/mac/Open-PrivateChat.sh`: opens the populated private chat URL in the default browser.

## Known local follow-up

- The installed Tailscale CLI and running GUI/daemon have different versions. Current connectivity passes; reconcile versions only during an authorized maintenance step.
- The existing Homebrew Node.js runtime is not usable because of a missing dynamic-library dependency. It is not required for browser-only chat, and it was not repaired in this milestone.
- Local model downloads remain inappropriate until disk headroom is addressed and a Mac-local runtime is explicitly required.

Work is tracked in Issue #5.
