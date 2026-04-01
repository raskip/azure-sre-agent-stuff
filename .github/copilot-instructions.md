# Copilot instructions for `azure-sre-agent-stuff`

## Repository purpose

This repository is a starter kit for [Azure SRE Agent](https://sre.azure.com) — it contains example **custom skills**, **governance hooks**, and **Bicep deployment templates** that help teams get started with Azure SRE Agent quickly.

The content is designed to be forked, customized, and extended for your own environment.

## What's in this repo

| Directory | Contents |
|-----------|----------|
| `skills/vm/` | 10 VM troubleshooting skills (SKILL.md + testing README per skill) |
| `hooks/` | 8 governance hook examples (YAML) + comprehensive guide |
| `infra/` | Bicep templates + PowerShell deploy script for SRE Agent provisioning |
| `docs/` | Guides for creating skills and hooks, plus why-and-when explainers for both |

## Skill file format

Each skill lives in its own directory under `skills/vm/<skill-name>/`:

- **`SKILL.md`** — The skill definition. Has YAML frontmatter (`name`, `description`, `tools`) followed by numbered steps. The agent reads this file to know what to do. Uses `{rg}` and `{vm-name}` as placeholders — the agent fills these at runtime.
- **`README.md`** — Testing guide. Contains VM deployment commands, issue simulation steps, example prompts, expected agent behavior, and cleanup.

When creating or editing skills:
- Keep SKILL.md environment-agnostic (use `{rg}`, `{vm-name}` placeholders)
- Include both Linux and Windows variants where applicable
- Always include a structured report template at the end
- Specify which tools are needed in the YAML frontmatter (`RunAzCliReadCommands`, `RunAzCliWriteCommands`)
- Note: `az vm run-command invoke` requires `RunAzCliWriteCommands` even for read-only diagnostics

## Hook file format

Hooks live in `hooks/examples/` as standalone YAML files. Each file contains:
- A `hooks:` top-level key
- Either a `PostToolUse` or `Stop` event
- Configuration: `type` (command/prompt), `matcher`, `timeout`, `failMode`, `script`/`prompt`

When creating hooks:
- Command hooks use Python scripts that read JSON from stdin and output `{"decision": "allow/block"}`
- Prompt hooks use LLM evaluation that returns `{"ok": true/false}`
- Use `failMode: block` for safety-critical hooks, `failMode: allow` for advisory ones

## Bicep templates

The `infra/` directory contains parameterized Bicep templates. They deploy:
- The SRE Agent resource (`Microsoft.App/agents`)
- User-assigned managed identity
- Log Analytics workspace + Application Insights
- RBAC role assignments

All environment-specific values are parameters — no hardcoded subscription IDs or resource group names.

## Conventions

- **Placeholder syntax in READMEs:** `<your-subscription-id>`, `<region>`, `<your-vnet-name>`, etc.
- **Naming convention (CAF-aligned):** `{abbreviation}-{purpose}-{instance}-{region}` (e.g., `rg-sre-agent-001-eastus2`)
- **Default region in examples:** `eastus2` (change to your preferred region)
- **VM naming for tests:** `vm-sre-demo-{scenario}` (e.g., `vm-sre-demo-cpu`, `vm-sre-demo-disk`)

## When helping users with this repo

- If asked to add a new skill, follow the SKILL.md format from existing skills
- If asked to generalize or modify, never introduce hardcoded subscription IDs, tenant IDs, or environment-specific resource names
- Keep all examples self-contained and easy to copy-paste
- Link to official Azure SRE Agent docs where appropriate: https://sre.azure.com/docs/
