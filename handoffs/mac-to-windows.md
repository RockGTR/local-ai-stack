# Mac-to-Windows handoff

Last updated: 2026-09-12
Owner: Mac
Stage: `PRIVATE_CHAT_ROUTE_VERIFIED`

## Mac acknowledgment

- Pulled and read the Windows `PRIVATE_CHAT_READY` status, handoff, shared architecture, and public contracts.
- Confirmed the Windows Tailscale peer responds and its MagicDNS name resolves from the Mac.
- Confirmed private HTTPS reaches the remote peer, returns HTTP 200, and validates its certificate normally with TLS 1.3.
- Confirmed the route reports Open WebUI 0.11.3 with public signup disabled and the existing-account login form enabled.
- Added placeholder-only Mac client configuration and reusable route verification/opening scripts under `platform/mac/**`.
- Stored the populated URL only in a permission-restricted private file outside Git; no global model-provider variables were changed.

## Verification boundary

- The authenticated small-chat check remains pending because it requires the user to sign in with the existing private account.
- The Mac did not probe the native Ollama origin, OpenAI-compatible base, `/v1/models`, dashboard port, or any model-management operation.
- No DeepSeek Harness, Ollama runtime, or model was installed on the Mac.
- The Windows smoke fixture is not treated as a selected production model.

## Next actions

1. User: open the private route with `platform/mac/Open-PrivateChat.sh`, sign in, and run one small chat. The Mac can then promote its browser-client state to `READY` if inference succeeds.
2. Windows/shared: keep the raw Ollama API unexposed. Publish a new contract and handoff only after an authenticated proxy or least-privilege policy is implemented and tested.
3. Mac: defer DeepSeek Harness or other API clients until that protected API surface is available; browser-only chat requires no local runtime or model.

Tracked in Issue #5. All machine identity, tailnet details, populated URLs, credentials, paths, and raw diagnostics remain private.
