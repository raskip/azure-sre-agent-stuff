# Scheduled Task — Weekly Cost Watcher

Copy-paste this into **Builder → Scheduled tasks → Create task**.

## Form fields

| Field | Value |
|---|---|
| **Task name** | `Weekly cost watcher` |
| **Frequency** | Weekly |
| **Day of week** | Monday |
| **Time of day** | 09:00 |
| **Response subagent** | _Leave empty_ unless you've installed a cost-specific subagent |
| **Model tier** | **Reasoning** — cost trend analysis benefits from deeper reasoning |
| **Message grouping for updates** | New thread each week (easier to share single weekly report links) |
| **Agent autonomy level** | **Review** — any remediation recommendation (downsize, deallocate) requires human approval |

## Task details (paste verbatim)

```
Every Monday at 09:00 local time, produce a cost trend report for
subscription <your-subscription-id> covering the previous calendar week.

Steps:
1. Pull the total spend for the prior 7 days and the 7 days before that
   (the comparison window).
2. Break down by service (Compute, Storage, Networking, App Services,
   Defender, etc.) and by resource group.
3. Identify any resource group or service whose spend grew by more than
   25% week-over-week.
4. For each growth flag, cross-reference Activity Log for new resources
   created or SKU changes in the same window.
5. Highlight any resource tagged "workload=sre-demo" that is running
   but hasn't received SSH or run-command traffic in the last 7 days —
   these are candidates to deallocate.
6. Cross-check Azure Advisor for high-impact cost recommendations
   (right-size VMs, shutdown idle disks, etc.).

Output format:
  - "## Headline" — single sentence: trend direction + total $ change
  - "## Breakdown" — table of service / RG / $ / WoW %
  - "## Anomalies" — list of >25% jumps with the corresponding Activity
    Log entries
  - "## Recommendations" — at most 3 concrete actions, each with the
    estimated monthly $ saving and a Review/Autonomous flag
  - "## Memory note" — what the agent learned this week (will be auto-
    indexed for next week)

Post to Teams channel "sre-demos" with the headline + a deep link to
this thread. Do NOT auto-deallocate or downsize anything — every action
is a recommendation requiring my approval.
```

## Verification

After the first Monday run:
1. **Scheduled tasks → Weekly cost watcher → execution history** → status Completed
2. Open the thread — review the "## Recommendations" section
3. If recommendations look reasonable, individually approve them via the
   agent's Review-mode flow. Each approval triggers the actual action.
4. Confirm a Teams message landed in the `sre-demos` channel with the
   headline + deep link.

## Talking points

> *"This is the closer for the cost-conscious audience. Same prose-driven
> task, but with Review mode the agent never spends money on its own. It
> writes recommendations, you click Approve. The agent learns from your
> approvals — after a few weeks it knows you'll always approve 'deallocate
> idle demo VMs' and proactively highlights them earlier."*

> *"The 'Memory note' section at the end of each report is what makes
> this compound. Next Monday's report includes 'this is the third week
> we've flagged the same orphaned disks; consider raising a ticket for
> the platform team to delete them'."*

## Pairing with other tasks

This task pairs well with:
- **Daily VM inventory** (`scheduled-task-01`) — the daily catches operational
  issues; the weekly catches cost trends.
- **Subagent: cost_optimizer** (future) — for tenants with bigger spend,
  delegate this task to a dedicated cost subagent that can also propose
  Reserved Instances and Savings Plans.

## Cleanup

Pause via **Scheduled tasks** → toggle **Off**. Delete via **Delete** action.
