# Walkthrough 05 — Marketplace Onboarding (5 min)

> **Audience**: technical evaluators or new platform team members
> **Goal**: install our curated skill catalogue in under a minute and prove the agent uses the new skills immediately.

## Prerequisites

Have these tabs ready:
1. Your agent at https://sre.azure.com → Builder → **Plugins**
2. The marketplace repo (browser): `https://github.com/raskip/azure-sre-agent-stuff`
3. A fresh chat thread in the agent for the post-import test

## The narrative — 5 minutes

### Minute 0 — The pain (30 s)

> *"Until last quarter, adding skills meant: open SKILL.md, copy YAML frontmatter into one box, copy markdown body into another box, click around the tool picker — for every single skill. If you wanted ten skills, you spent a couple of hours and you had no record of where they came from."*

Show the existing "Create skill" dialog. Don't dwell — the audience either knows the pain or they're glad they don't.

### Minute 1 — Add the marketplace (45 s)

In the portal: **Builder → Plugins → Add marketplace**.

Paste the marketplace repo URL:

```
https://github.com/raskip/azure-sre-agent-stuff
```

> *"The portal fetches the marketplace manifest from this repo over GitHub's anonymous read. No GitHub PAT, no service principal."*

The plugin card appears: **vm-sre-skills (10 skills)**.

### Minute 2 — Browse and preview (1 min)

Click into **vm-sre-skills**. Show:
- The 10 skill cards with their descriptions
- Click into one (e.g., `high-cpu-vm-troubleshooting`) — full SKILL.md preview appears
- The "View source" link goes directly to the GitHub file
- The version badge says `1.0.0`

> *"Provenance is built in — every skill remembers its source repo and content hash. When the upstream repo updates, your agent tells you."*

### Minute 3 — Import (30 s)

Select **vm-sre-skills** → click **Import selected**.

A toast appears: *"10 skills imported"*. Navigate to **Builder → Skills**.

The 10 skills are all there. **Same source, same versions, same SHA-256 hashes** as the repo. Show the "Source" column.

### Minute 4 — Prove it works (1 min)

Open the fresh chat thread. Paste:

```
I'm getting a high-CPU alert on the VM I just deployed for testing. Walk me
through your diagnostic procedure.
```

The agent picks the freshly-imported `high-cpu-vm-troubleshooting` skill automatically (no `/skill` command needed). Watch the planning step: *"Loading skill: high-cpu-vm-troubleshooting"*.

> *"It just worked. No restart, no reconfigure, no waiting. The skill is live."*

### Minute 5 — Updates (1 min)

Back in **Builder → Plugins → vm-sre-skills**, click **Check for updates**.

> *"Today everything's at v1.0.0 so there's nothing to apply. But when the upstream repo ships v1.1.0 of one skill, you'll see a side-by-side diff and decide per-skill whether to update."*

Optional: open the marketplace repo in a separate tab, point out that anyone can fork it, change a skill, and instantly become their own marketplace source. *"It's just GitHub."*

---

## What's installed by default

Importing **vm-sre-skills** adds these 10 skills:

| Skill | Category |
|---|---|
| high-cpu-vm-troubleshooting       | Diagnostic |
| high-memory-oom-troubleshooting   | Diagnostic |
| disk-iops-throttling              | Diagnostic |
| disk-expansion                    | Remediation |
| vm-connectivity-troubleshooting   | Diagnostic |
| service-crash-loop-detection      | Diagnostic |
| security-incident-triage          | Diagnostic |
| vm-right-sizing                   | Advisory |
| backup-health-verification        | Diagnostic |
| vm-extension-failure-remediation  | Remediation |

Hook examples remain available in `hooks/examples/` for manual review or loading through the portal when you want to test governance patterns.

## Discussion points

- **"It's GitHub all the way down."** The marketplace is just a JSON manifest in a public repo. Anyone can publish their own, anyone can fork ours.
- **"Provenance is the killer feature."** Six months from now, looking at a custom skill, you can answer "where did this come from, who owns it, and is it up to date?" — without spelunking.
- **"Updates aren't surprises."** SHA-256 hashing means the portal can tell you exactly what changed before you apply it.
- **"It's not an API substitute, it's the answer."** Microsoft didn't ship a REST API for skill CRUD. The marketplace pattern is what they shipped instead, and it's better for our use case because the source-of-truth is in GitHub where we already collaborate.

## Cleanup

- To remove all imported skills from the demo agent: **Builder → Skills → select all → Delete**.
- To remove the marketplace registration: **Builder → Plugins → vm-sre-skills → Remove marketplace**. This does NOT uninstall previously-imported skills; do those separately.

## Variants

- **For a more compliance-flavoured audience**, pair the marketplace walkthrough with a quick stop in `hooks/examples/` to show that governance samples are still ready for manual loading through the portal.
- **For a Mac-using or remote audience**, share your screen of the actual portal — no `az` CLI involved.
