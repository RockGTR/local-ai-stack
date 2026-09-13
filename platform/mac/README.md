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

## Download a model onto Windows from this Mac

Open the Windows-hosted model manager through the same private HTTPS route:

```sh
platform/mac/Open-WindowsModelManager.sh
```

The launcher first runs the non-authenticated private-route checks, then opens Open WebUI at **Admin Panel → Settings → Models**. Sign in with the existing administrator account, choose **Manage**, enter an exact Ollama model tag under **Pull a model from Ollama.com**, and select **Pull Model**. Open WebUI performs the pull from the Windows host to its loopback-only Ollama service; the model weights are not downloaded to the Mac.

This is an authenticated browser control path, not a raw model API. The launcher stores no credential and starts no download itself. Before selecting **Pull Model**:

- choose an exact model from `docs/model-candidates.md` or coordinate a new candidate in Issue #3;
- for any download over 5 GB, obtain explicit approval and rerun the Windows storage preflight with the exact payload and temporary overhead;
- keep the browser open to observe progress, and verify the resulting model on Windows before treating it as ready; and
- do not use the adjacent delete control unless model removal is explicitly intended and authorized.

Open WebUI 0.11.3 restricts its pull, create, copy, download, upload, and delete handlers to administrators. Ollama remains bound to Windows loopback and Tailscale Serve continues to publish only Open WebUI.

## Requirements

- macOS with `/bin/bash`, `/usr/bin/python3`, `/usr/bin/curl`, and `/usr/bin/open`.
- Tailscale CLI on `PATH` with the Mac connected to the private tailnet.
- A private URL and existing Open WebUI account supplied out of band.

No local model runtime or model download is required for browser-only use.

## DeepSeek Harness

DeepSeek Harness is installed separately as an experimental local agent UI. The pinned deployment record is `deepseek-harness.public.yaml`; start it with:

```sh
platform/mac/Start-DeepSeekHarness.sh
```

The launcher uses the user-local versioned npm installation, the compatible Homebrew `node@22` runtime, a dedicated empty workspace, a private `DSH_HOME`, and a loopback-only listener. It does not alter the global shell environment or configure automatic startup. Pass `--no-open` to suppress its browser launch or `--port <port>` to choose another loopback port. A non-loopback `--host` override is rejected.

The installed Harness is developer-preview software that can execute model-generated commands and access files explicitly made available to it. Add only workspaces you intend it to inspect, review plugins before enabling them, and retain approval prompts.

No model provider is configured. The Windows OpenAI-compatible endpoint remains blocked by the shared contract, and API credentials must never be pasted into Git or chat. When a protected provider is available, configure it through Harness **Settings → Models**; Harness stores credentials under the private `DSH_HOME`.

Harness is a client and agent runtime, not an Ollama model store. Production models belong on the Windows GPU host. Select an exact option in Issue #3, rerun the Windows storage preflight, and pull it from Windows under the managed storage contract. Do not download model weights to this Mac while local disk headroom remains constrained.
