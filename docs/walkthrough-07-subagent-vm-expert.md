# Walkthrough 07 — Subagent VM Expert (5 min)

> **Audience**: technical evaluators or new platform team members
> **Goal**: install a domain-expert subagent in 30 seconds via REST API,
> then show the `/agent` slash-command handoff in chat.

## What you're demoing

Custom agents (subagents) are scoped specialists the user invokes with the
`/agent` slash command. Unlike skills (which the main agent loads
automatically when relevant), subagents are explicit — you reach for them
when you want focused expertise on a specific domain.

This demo installs a `safe_vm_troubleshooter` subagent that:
- Has VM-troubleshooting instructions baked in
- Has access to the marketplace-imported VM skills
- Has the `allowlist-remediation` hook pre-attached so it never runs
  anything outside the approved command list

## Prerequisites

Have ready:
1. A provisioned SRE Agent (any region)
2. Local clone of this repo
3. `az` logged in to the subscription that owns the agent
4. A fresh chat thread in the portal

If you completed [Walkthrough 05](walkthrough-05-marketplace-onboarding.md) first, the VM
skills are already imported. If not, do that first.

## The narrative — 5 minutes

### Minute 0 — The pain (30 s)

> *"Today the agent decides on its own which skill to apply. That's great
> for routine triage, but sometimes we want explicit delegation: 'this is
> a VM problem, hand it to the VM specialist.' That's what subagents are
> for. And the specialist comes with its own guardrails — its own hook
> stack, its own allowed-skills list."*

### Minute 1 — Install in 30 seconds (1 min)

From the repo root on the operator's laptop:

```bash
./examples/sre-agent/hooks/install-via-api.sh \
  --subscription <your-subscription-id> \
  --resource-group <your-agent-rg> \
  --agent <your-agent-name>
```

The script:
1. Resolves the agent's data-plane endpoint via Azure Resource Manager
2. Acquires a token for the `https://azuresre.ai` audience
3. PUTs an `ExtendedAgent` v2 payload to
   `$AGENT_URL/api/v2/extendedAgent/agents/safe_vm_troubleshooter`
4. The payload includes instructions, a PostToolUse audit hook, and a
   PostToolUse allowlist-remediation hook

Expected output:

```
==> Resolving agent endpoint…
    https://<agent>--<hash>.<region>.azuresre.ai
==> Acquiring token (audience: https://azuresre.ai)…
==> PUT $AGENT_URL/api/v2/extendedAgent/agents/safe_vm_troubleshooter
==> HTTP 202 — custom agent + hooks installed.
```

Switch to the portal: **Builder → Agent Canvas**. The new
`safe_vm_troubleshooter` node appears in the canvas with its two attached
hooks.

> *"30 seconds. No portal clicking, no copy-pasting YAML. The subagent
> definition is in source control, the install is a CI-friendly bash
> script, and the agent is configured."*

### Minute 2 — `/agent` handoff (1 min)

In the chat:

```
/agent safe_vm_troubleshooter

My VM <vm-name> in <resource-group> is reporting high CPU. Take a look.
```

The agent picks up the subagent invocation, switches to the
`safe_vm_troubleshooter` persona, and starts investigating. Watch the
chat header indicate "Active: safe_vm_troubleshooter".

> *"Notice the chat context is preserved — the subagent sees the full
> conversation history. If we'd asked something else first, the subagent
> would have all that context too. It's not a fresh agent, it's a
> specialist taking over the same conversation."*

### Minute 3 — Hook stack in action (1 min)

Continue the conversation:

```
Can you also clean up the temp files in /var/log on that VM?
```

The subagent reasons about the request, plans a remediation, but the
`allowlist-remediation` hook intercepts: cleaning up `/var/log` isn't
in the allowlist (which currently permits `disk update`, `growpart`,
`systemctl restart`, etc., but not file deletion).

The subagent reports back: *"I attempted to run `find /var/log -delete`
but the allowlist hook blocked it. Approved remediation patterns are:
disk expansion, filesystem resize, service restart, ..."*

> *"The subagent doesn't have to know about the hook. The hook applies
> automatically because we attached it at install time. This is how
> 'specialist + governance' compose without coupling."*

### Minute 4 — Memory + skill stacking (1 min)

Ask one more thing:

```
What VM SKU would you recommend for this workload long-term?
```

The subagent has `enable_skills: true` in its YAML, so it can load the
`vm-right-sizing` skill from the marketplace-imported set. Watch the
planning step: *"Loading skill: vm-right-sizing".*

> *"This is the composition story. The subagent is the persona. The skills
> are the playbooks it can reach for. The hooks are the safety rails.
> All three are independent and reusable — replace any one without
> touching the others."*

### Minute 5 — Recap + side note (30 s)

Quick recap on the canvas:

```
Main agent
   └── /agent safe_vm_troubleshooter
         ├── allowed_skills:  vm-* (10 skills)
         ├── PostToolUse hook: audit-all-tool-usage
         └── PostToolUse hook: allowlist-remediation
```

**Side note** for the developer-flavoured audience: there's also a
**VS Code MCP extension for SRE Agent** that lets you edit subagent YAML
in your editor with changes syncing live to the agent. Worth a follow-up
session for teams who manage many subagents.

## Cleanup

To remove the subagent:

```bash
az rest --method DELETE \
  --uri "$AGENT_URL/api/v2/extendedAgent/agents/safe_vm_troubleshooter" \
  --headers "Authorization=Bearer $TOKEN"
```

Or in the portal: **Builder → Agent Canvas → safe_vm_troubleshooter → Delete**.

## Discussion points

- **"It's a YAML and a curl."** No magic. Source-controlled, CI-friendly,
  reproducible across tenants.
- **"Composition over inheritance."** Subagent + skills + hooks compose.
  Each is independently testable, replaceable, observable.
- **"Same conversation context."** Subagents aren't a context restart.
  Handoff chains naturally if you wire `handoffs: [...]` in the YAML.

## What this isn't (yet)

- We don't yet show **handoff chains** (subagent → subagent → ...).
  That's a Tier 3 follow-up demo.
- We don't yet show the **Test playground** workflow for iterating on
  subagent instructions before going live. Easy add later.
- We don't yet show **VS Code MCP** integration. Mentioned as a side note.
