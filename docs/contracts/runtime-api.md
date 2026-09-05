# Runtime API contract

Status: `PARTIALLY_VERIFIED`. Local native and OpenAI-compatible smoke checks passed; private remote availability must be confirmed by `state/windows/STATUS.md`.

## Public placeholders

| Purpose | Placeholder |
|---|---|
| Browser chat | `<WINDOWS_CHAT_URL>` |
| Native Ollama origin | `<WINDOWS_OLLAMA_ORIGIN>` |
| OpenAI-compatible base | `<WINDOWS_OPENAI_BASE_URL>` |
| Status interface | `<WINDOWS_DASHBOARD_URL>` |

Actual values belong in private configuration and must not be committed.

## Required capabilities

### Native runtime

- Model discovery and runtime status.
- Chat and generation with streaming.
- Model pull with observable progress.
- Explicit keep-warm and unload behavior where supported.
- Image messages for an approved vision model.

### OpenAI-compatible surface

- `GET /v1/models`
- `POST /v1/chat/completions`
- Streaming chat completions.
- Tool calls and structured output where the selected model and runtime support them.
- Text completions only where the installed runtime exposes a compatible operation.

Feature support is recorded per tested model; the presence of an endpoint is not proof that every model supports every feature.

## Service states

Clients may display:

- `unloaded`
- `downloading`
- `loading`
- `ready`
- `stopping`
- `error`

`ready` requires a successful small inference, not merely a live process or successful health request.

## Administrative operations

- Model identifiers must be validated against the runtime's model inventory or an approved source.
- Pull progress may be streamed to the client.
- Deletion requires explicit confirmation and is never inferred from a storage warning.
- No operation accepts an arbitrary shell command or unrestricted filesystem path.
- All administrative access remains inside the private Tailscale boundary.
- Tailnet membership alone is not application authentication. The raw Ollama API must not be served until least-privilege tailnet policy or an authenticated proxy limits pull, delete, and resource-consuming operations.

## Compatibility changes

Breaking route, port, payload, or state changes require a `[Shared]` Issue. Prefer additive changes and preserve old behavior until both machine status files acknowledge migration.
