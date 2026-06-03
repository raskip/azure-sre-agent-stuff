# Security Policy

## Scope

This repository contains **example** skills, governance hooks, and Bicep deployment
templates for Azure SRE Agent. It is intended to be forked and customized. The examples
are not a hosted service and process no data themselves.

## Reporting a vulnerability

If you find a security issue in this repository — for example a hook or skill that could
enable unintended privileged actions, or a Bicep template that grants excessive
permissions — please report it privately:

- Use **[GitHub Security Advisories](https://github.com/raskip/azure-sre-agent-stuff/security/advisories/new)**
  ("Report a vulnerability") on this repository, **or**
- Open a regular issue **only if** the report contains no sensitive details.

Please do **not** disclose exploitable details in public issues before a fix is available.

## What to include

- A description of the issue and its impact.
- The affected file(s) and, if applicable, a minimal reproduction.
- Any suggested remediation.

## Out of scope

- Vulnerabilities in Azure SRE Agent itself — report those to Microsoft via the
  [official channels](https://sre.azure.com/docs/).
- Issues that require already-elevated access an attacker would not normally have.

## Hardening reminders for users

These examples are starting points. Before using them in a real environment:

- Review every hook and skill — they can run commands inside your VMs.
- Deploy with least-privilege RBAC (start with the `Low` access level).
- Never commit real subscription IDs, tenant IDs, or secrets. The repo `.gitignore`
  excludes `.env` and `*.local.json`; keep secrets out of tracked files.
