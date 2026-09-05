# Security and privacy policy

## Scope

This repository is a public coordination surface for a private local-AI stack. It must remain useful without revealing either machine's identity, storage layout, network topology, credentials, or private data.

## Repository hygiene

- Use the placeholders defined in `AGENTS.md` in every tracked example and report.
- Keep populated configuration, inventories, logs, databases, model files, caches, and backups outside the repository.
- Review staged changes and run `scripts/Test-PublicRepository.ps1` before every commit from Windows.
- Do not paste authentication output into Issues, pull requests, commits, or handoffs.
- If sensitive data is exposed, stop work, revoke or rotate the affected credential where applicable, and coordinate repository-history remediation with the owner.

## Network boundary

- Application services bind to loopback by default.
- Private remote access uses Tailscale Serve.
- Tailscale Funnel remains disabled.
- Do not create public, LAN, or broad tailnet firewall listeners as a convenience workaround.
- Actual hostnames, addresses, and URLs belong only in private configuration.

## Model and controller safety

- Do not enable remote model code unless a specific source and revision have been reviewed.
- Validate model identifiers before passing them to a runtime.
- Never expose arbitrary shell execution through a status or model-management controller.
- Require explicit confirmation before model deletion.
- Before downloading any model larger than 5 GB, document its source, immutable revision, license, quantization, transfer size, installed estimate, and storage-preflight result for approval.

## Reporting a security issue

Do not open a public Issue containing exploit details, credentials, or private topology. Contact the repository owner through an already trusted private channel.
