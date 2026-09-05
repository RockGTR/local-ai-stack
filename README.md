# local-ai-stack

Shared control plane, setup scripts, status handoffs, and reproducible configuration for a private Mac-to-Windows local LLM system.

This public repository contains sanitized coordination material only. Machine-specific values belong in ignored private configuration and are represented here by placeholders.

Start with:

- [Agent collaboration rules](AGENTS.md)
- [Architecture](docs/architecture.md)
- [Windows status](state/windows/STATUS.md)
- [Windows-to-Mac handoff](handoffs/windows-to-mac.md)
- [Runtime API contract](docs/contracts/runtime-api.md)
- [Public service map](docs/contracts/service-map.public.yaml)
- [Windows reboot runbook](docs/runbooks/windows-reboot.md)
- [Pinned model candidates and approval choices](docs/model-candidates.md)

No service is considered reachable or ready merely because it appears in a contract. Check the owning machine's status file first.
