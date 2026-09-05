# Repository collaboration rules

These rules apply to every agent and contributor working in this repository.

## Start of every work session

1. Run `git status` and preserve any dirty work.
2. Fetch `origin`; pull or rebase only when the working tree and branch state make it safe.
3. Read both machine status files, both handoffs, the shared contracts, decisions, and relevant open Issues.
4. Claim or create an Issue whose title starts with `[Windows]`, `[Mac]`, or `[Shared]`.
5. State the files you intend to own before editing them.

Never force-push and never discard another contributor's uncommitted work.

## Ownership

| Owner | Paths |
|---|---|
| Windows | `platform/windows/**`, `state/windows/**`, `handoffs/windows-to-mac.md`, Windows public manifests |
| Mac | `platform/mac/**`, `state/mac/**`, `handoffs/mac-to-windows.md`, Mac public manifests |
| Shared | `docs/contracts/**`, `docs/architecture.md`, `AGENTS.md`, `SECURITY.md`, root configuration, and cross-platform scripts |

Do not edit the other machine's status or outbound handoff to simulate acknowledgment. Shared files require a `[Shared]` Issue and preferably a pull request after the initial scaffold.

## Public/private boundary

This repository is public. Commit only sanitized information.

Allowed:

- Generic hardware classes, sanitized component versions, public model identifiers, benchmark summaries, public ports, placeholders, scripts, and templates.
- Placeholders including `<FAST_STORAGE_ROOT>`, `<REGULAR_STORAGE_ROOT>`, `<WINDOWS_TAILSCALE_HOST>`, `<WINDOWS_CHAT_URL>`, `<WINDOWS_OLLAMA_ORIGIN>`, `<WINDOWS_OPENAI_BASE_URL>`, and `<WINDOWS_DASHBOARD_URL>`.

Forbidden:

- Real absolute machine paths, usernames, home directories, hostnames, device names, private IP addresses, tailnet names, or private URLs.
- Tokens, keys, cookies, credentials, authentication output, populated environment files, or secret-bearing command output.
- Raw inventories, serials, UUIDs, diagnostic logs, prompts, chat history, models, weights, caches, databases, virtual disks, or application data.

Keep populated private configuration outside this repository. Run `scripts/Test-PublicRepository.ps1` before committing from Windows. The checker is a guardrail, not a substitute for review.

## Change workflow

- Keep commits narrow and use `windows:`, `mac:`, or `shared:` prefixes.
- Update the owning status file after each tested milestone.
- Update the owning outbound handoff when the other machine can act.
- Pull or rebase safely immediately before pushing, then verify the remote commit.
- Record shared architectural decisions in `docs/decisions/`.
- Use immutable versions or digests for deployable dependencies; do not silently track mutable tags.

## Status language

- `PLANNED`: documented but not installed.
- `BLOCKED`: cannot proceed until the named dependency is resolved.
- `INSTALLED`: files are present, but functionality may be unverified.
- `VERIFIED`: the stated test passed.
- `READY`: a small inference succeeded and the intended private access path was tested.

Never mark a model or service `READY` based only on process state or a health endpoint.
