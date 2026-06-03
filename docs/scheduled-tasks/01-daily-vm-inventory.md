# Scheduled Task — Daily VM Inventory & Health

Copy-paste this into **Builder → Scheduled tasks → Create task** in the SRE
Agent portal. Adjust the bracketed placeholders for your environment.

## Form fields

| Field | Value |
|---|---|
| **Task name** | `Daily VM inventory & health` |
| **Frequency** | Daily |
| **Day of week** | Mon–Fri (skip weekends to reduce noise) |
| **Time of day** | 08:00 in your timezone |
| **Response subagent** | _Leave empty_ — main agent handles it. If you have a `vm_expert` subagent installed (see `../walkthrough-07-subagent-vm-expert.md`), pick that. |
| **Model tier** | General Purpose |
| **Message grouping for updates** | Use same thread (keeps the daily history together) |
| **Agent autonomy level** | **Autonomous** — this task is read-only |

## Task details (paste verbatim)

```
Every weekday at 08:00 local time, produce a one-paragraph health report
for all virtual machines tagged "workload=sre-demo" in subscription
<your-subscription-id>.

For each VM, gather:
  - Power state and provisioning state
  - Last 24h: average CPU %, memory pressure indicator, disk IOPS percentage,
    and outbound network bytes
  - Resource Health status (Available / Degraded / Unavailable)
  - Any unresolved Defender for Cloud alerts in the last 24h

Cross-correlate any anomalies with deployments / configuration changes
recorded in Activity Log over the same window. If a VM was running last
weekday but is now deallocated unexpectedly, flag it.

Output format:
  - One H2 heading per VM
  - A 2-3 sentence summary covering health + any flagged anomalies
  - A "## Summary" section at the end with a green / yellow / red badge
    and any items that need human review

If everything is green and no anomalies, send a one-line summary instead
of full per-VM reports.

Post the final summary to Microsoft Teams in channel "sre-demos" via
the built-in Teams connector. Tag the on-call rotation only if any VM
is red.
```

## Verification (T+24h)

After the first scheduled run:
1. Open **Scheduled tasks → Daily VM inventory & health** → execution history
2. Confirm the run shows status **Completed**
3. Open the conversation thread the agent created
4. Look for:
   - Planning step: "I will check VMs tagged workload=sre-demo..."
   - Tool calls: `az resource list`, `Resource Health query`, Activity Log query
   - Memory context (if any prior runs exist, the agent cites them)
   - Outcome: structured summary + Teams notification confirmation
5. Verify the message arrived in the `sre-demos` Teams channel.

## Discussion points

> *"This is what 'set it and forget it' looks like. The agent doesn't just
> list VMs — it cross-correlates with Activity Log so a deallocation that
> wasn't deliberate shows up automatically. After a few weeks, memory kicks
> in: the agent remembers that vm-x always gets restarted Saturday morning
> for maintenance and stops flagging it."*

> *"And we wrote zero scripts. The task is described in plain English. To
> change behaviour we edit the same prose."*

## Cost considerations

- Each run uses ~5-15 k tokens at General Purpose tier ≈ a few cents.
- Switch to **Fast** tier (cheaper, less reasoning) if the agent
  consistently produces over-detailed reports.
- For accounts with strict cost controls, schedule weekly instead of daily.

## Cleanup

To pause: **Scheduled tasks** → toggle the task **Off**. History is preserved.
To delete: **Scheduled tasks** → select task → **Delete**.
