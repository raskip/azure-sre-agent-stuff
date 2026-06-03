# Scheduled Task — Hourly Skill Smoke Test

The "is my agent still working?" canary. Cheap, high-frequency, alerts only
when something's actually broken.

## Form fields

| Field | Value |
|---|---|
| **Task name** | `Hourly skill smoke` |
| **Frequency** | Custom cron |
| **Cron expression (UTC)** | `0 * * * *` (top of every hour) |
| **Response subagent** | _Leave empty_ — main agent picks the skill |
| **Model tier** | **Fast** — single-skill exercise, no need for deep reasoning |
| **Message grouping for updates** | Use same thread (one long history per smoke target) |
| **Agent autonomy level** | **Autonomous** — diagnostic only, no remediation |

## Task details (paste verbatim)

```
At the top of every hour, exercise the high-cpu-vm-troubleshooting skill
end-to-end against the designated smoke VM <vm-name> in resource group
<resource-group> (subscription <your-subscription-id>).

Steps:
1. Pre-flight: confirm the VM is in Running state. If deallocated, output
   "skipped: VM deallocated" and exit successfully. (Don't auto-start —
   skipping is the right answer.)
2. Pull the last hour of Percentage CPU metric. Confirm the metric is
   available (i.e., that VM Insights / Azure Monitor for VMs is still
   collecting).
3. Open a one-line diagnostic: "Investigate current CPU utilisation on
   <vm-name>. Quick triage only — no remediation."
4. Run the high-cpu-vm-troubleshooting skill at standard depth.
5. Capture: which skill was selected, how long the investigation took,
   which tools were called.

Output format (must be parseable for downstream automation):
  STATUS: PASS|FAIL|SKIPPED
  SKILL: <skill name selected>
  DURATION_SEC: <number>
  TOOLS_USED: <comma-separated tool names>
  REASON: <one sentence if FAIL or SKIPPED>

Send a Teams notification ONLY if STATUS != PASS. Do not flood the channel
with hourly "all good" pings.
```

## Verification

After the first 1-2 hours:
1. **Scheduled tasks → Hourly skill smoke → execution history** — should
   show 1-2 entries with status Completed
2. Open the thread → verify the output is parseable
3. Force a fault (deallocate the VM or break the metric pipeline) and
   confirm the next run produces a FAIL/SKIPPED and Teams notification

## Talking points

> *"Treat your agent like any other production service. Cheap canaries
> at high frequency catch regressions before they surface in production. The
> Fast model tier keeps this nearly free — call it a couple of dollars
> a month for a hundred-something smoke runs."*

> *"The output format is structured on purpose. Downstream automation
> can grep the output, scrape the duration trend, and chart it. Slow
> investigation times catch model regressions or quota changes early."*

## Implementation notes

- **Why not a normal Azure Monitor availability test?** Because this
  exercises the *agent path*: skill selection, tool wiring, model
  inference. A platform availability test wouldn't notice a broken
  skill or a permission drift on the agent's managed identity.
- **Why high-cpu specifically?** It's our best-tested skill. The smoke
  test should use the most-reliable skill so failures are real signal,
  not flaky-skill noise. Rotate later if better candidates emerge.
- **Why not multiple skills per run?** Single-skill keeps the run cheap
  and the output deterministic. If you want broader coverage, schedule
  3 parallel hourly smokes (one per skill) at staggered minutes — `5 * * * *`,
  `25 * * * *`, `45 * * * *`.

## Cleanup

Pause via **Scheduled tasks** → toggle **Off**.

> ⚠️ Don't delete the underlying VM (`<vm-name>`) without disabling this
> task first — the SKIPPED branch handles deallocation, but a deleted VM
> will start producing FAIL pings every hour until you turn the task off.
