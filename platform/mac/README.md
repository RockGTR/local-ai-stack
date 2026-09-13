# Mac private-chat client

The Mac is a thin browser client for the authenticated Open WebUI route published by the Windows host through Tailscale Serve. The raw Ollama and OpenAI-compatible surfaces are intentionally unavailable until the shared contract records an authenticated or least-privilege API gateway.

## Private configuration

Keep the populated configuration outside this public repository:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/local-ai-stack"
cp platform/mac/mac-client.public.env.example \
  "${XDG_CONFIG_HOME:-$HOME/.config}/local-ai-stack/mac-client.private.env"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/local-ai-stack/mac-client.private.env"
```

Replace `<WINDOWS_CHAT_URL>` in the private copy only. Do not add the real hostname, URL, address, username, or credentials to this repository or to a global shell profile.

To use another private file without changing global state, pass `--config <path>` or set `LOCAL_AI_MAC_CONFIG` for one command.

## Verify and open

```sh
platform/mac/Test-MacClient.sh
platform/mac/Open-PrivateChat.sh
```

`Test-MacClient.sh` verifies the following without bypassing certificate checks:

- the private config is owned by the current user and is not group/world accessible;
- the configured URL is HTTPS and has no embedded credentials;
- Tailscale is running and the peer responds;
- MagicDNS resolves the peer;
- HTTPS reaches a remote address rather than this Mac;
- the browser route returns HTTP 200; and
- the public Open WebUI configuration identifies Open WebUI with signup disabled.

The test never calls the Ollama port, `/v1/models`, or an inference endpoint. Authentication and a small chat remain an interactive browser check.

## Requirements

- macOS with `/bin/bash`, `/usr/bin/python3`, `/usr/bin/curl`, and `/usr/bin/open`.
- Tailscale CLI on `PATH` with the Mac connected to the private tailnet.
- A private URL and existing Open WebUI account supplied out of band.

No local model runtime or model download is required for browser-only use.
