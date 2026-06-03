# Contributing

Thanks for your interest in improving this Azure SRE Agent starter kit! This repo is a
collection of **example** skills, governance hooks, and Bicep deployment templates meant
to be forked and customized. Contributions that make the examples clearer, safer, or more
broadly useful are welcome.

## Before you start

- This is an **example library**, not a production product. Keep contributions
  environment-agnostic — no hardcoded subscription IDs, tenant IDs, or
  organization-specific resource names.
- Verify any product claims against the official docs at
  [sre.azure.com/docs](https://sre.azure.com/docs/) — the SRE Agent evolves quickly.

## Repo conventions

The authoring conventions are documented in
[`.github/copilot-instructions.md`](.github/copilot-instructions.md). In short:

### Skills (`plugins/<plugin>/skills/<skill-name>/`)
- `SKILL.md` — YAML frontmatter (`name`, `description`, `tools`) + numbered steps +
  a structured report template at the end. `name` **must** match the directory name.
- `README.md` — testing guide (VM deploy commands, issue simulation, cleanup).
- Use `{rg}` / `{vm-name}` placeholders; cover both Linux and Windows where relevant.
- Note: `az vm run-command invoke` needs `RunAzCliWriteCommands` even for read-only diagnostics.

### Hooks (`hooks/examples/*.yaml`)
- A top-level `hooks:` map keyed by a known event (`PostToolUse`, `Stop`, …).
- Each entry is typed (`command` needs `script`, `prompt` needs `prompt`).
- `failMode: block` for safety-critical hooks, `failMode: allow` for advisory ones.

### Bicep (`infra/`)
- All environment-specific values are parameters. Keep `@allowed` lists consistent
  across parent and module templates.

## Validate before you open a PR

A lightweight gate runs on every push and PR ([`.github/workflows/lint.yml`](.github/workflows/lint.yml)).
Run it locally first:

```bash
pip install pyyaml
python3 scripts/validate_repo.py
```

It checks skill frontmatter, hook YAML, `marketplace.json` consistency, README
skill/hook counts, and that relative markdown links resolve. Exit 0 = green.

If you change a Bicep template, also build it:

```bash
az bicep build --file infra/<file>.bicep --stdout > /dev/null
```

## Pull requests

- Keep PRs focused and small.
- Update the relevant `README.md` / docs in the same PR.
- Make sure the lint workflow is green.
