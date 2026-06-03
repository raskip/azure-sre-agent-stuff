# Scheduled Tasks — Templates for Proactive SRE Agent Automation

Natural-language task templates ready to paste into the SRE Agent portal:
**Builder → Scheduled tasks → Create task**.

Each file is a complete, self-contained recipe with:
- The exact form-field values to enter
- The natural-language **Task details** text (copy-paste verbatim)
- Verification steps for the first run
- Discussion points
- Cost / cleanup notes

## What are scheduled tasks?

Scheduled tasks let your agent run on a cadence — daily, weekly, hourly,
or any cron — without anyone asking. The agent uses its connectors,
tools, knowledge, and memory to reason about context, then produces a
summary (and optionally takes action, depending on the autonomy mode).

This is *not* a cron job running a script. The task is described in
plain English; the agent decides how to fulfil it each run.

Concept reference: <https://sre.azure.com/docs/capabilities/scheduled-tasks>

## Templates in this folder

| # | Template | Cadence | Mode | Pairs well with |
|---|---|---|---|---|
| **01** | [Daily VM Inventory & Health](01-daily-vm-inventory.md) | Daily 08:00 weekdays | **Autonomous** (diagnostic only) | The VM fleet from `examples/01-quick-wow-high-cpu.md` |
| **02** | [Weekly Cost Watcher](02-weekly-cost-watcher.md) | Monday 09:00 | **Review** (cost actions need human approval) | `examples/03-business-value-right-sizing.md` |
| **03** | [Hourly Skill Smoke](03-hourly-skill-smoke.md) | Cron `0 * * * *` | **Autonomous**, Fast tier | Any skill — picks the most-reliable one for canary |

## How to choose

| You want to… | Template | Why |
|---|---|---|
| Catch operational drift before someone reports it | 01 — Daily inventory | Surfaces deallocations, alert backlog, anomaly trends |
| Catch cost surprises early | 02 — Weekly cost | Compares week-over-week, flags >25% growth, ties to Activity Log |
| Catch agent / skill regressions | 03 — Hourly smoke | Treats the agent path itself as a production service to monitor |
| All three | All three | They're complementary; combined ≈ a few $ / month in compute |

## Common patterns across templates

- **Output format is specified explicitly.** The Task details prescribe the
  output shape so downstream automation (Teams cards, ticket bodies) can
  parse reliably. Don't trust the model to format consistently across
  runs without instruction.
- **Memory matters more than you think.** After 2-3 runs, the agent
  starts citing prior runs. After a month, recurring noise is filtered
  out automatically. See `../walkthrough-08-memory-and-learning.md`.
- **Mode is the safety knob.** Autonomous = the agent acts without
  approval (use only for diagnostic / read-only tasks or trusted
  remediation). Review = the agent proposes, you approve. Default to
  Review on anything that spends money or changes infrastructure.

## Cleanup

Pause a task: **Scheduled tasks** → task row → toggle **Off**. History
is preserved.

Delete a task: **Scheduled tasks** → task row → **Delete**. History is
removed too.

## Adding new templates

Drop a new `NN-name.md` here following the existing template structure:

```
# Scheduled Task — <name>
## Form fields  (table with portal form values)
## Task details (paste verbatim)  (the natural-language block)
## Verification (T+N)             (what to check after first run)
## Discussion points
## Cost considerations             (model tier + tokens)
## Cleanup
```

Then add a row to the table at the top of this README and to the
top-level repo README's scheduled-tasks section.
