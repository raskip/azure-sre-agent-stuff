# Scenario 14 — Backup Health Verification

> **Duration:** 5 minutes | **Skill:** `backup-health-verification` | **Impact:** Medium-high — compliance audiences

---

## Goal

Show the agent auditing **Azure Backup health**: are recent jobs succeeding? When was the last successful restore point? Are there orphaned recovery points consuming cost? Is the policy actually being enforced? The skill produces an audit-ready report instead of "yes, backup is configured."

**Why this works:** Most teams "have backup configured" but can't answer "when did the last successful restore point complete and how long would recovery take?" The agent reads the Recovery Services Vault metadata in seconds and produces the answer. This is the scenario for compliance and DR conversations.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy + backup config

This demo needs an actual Recovery Services Vault and a VM under backup. If one doesn't exist:

```bash
# Quick setup (skip if a vault already covers any sre-demo VM)
az backup vault create -g <vault-rg> -n rsv-sre-demo-<region> -l <region>
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario backup -NoWait
# Enable backup on the VM under default policy
az backup protection enable-for-vm --vault-name rsv-sre-demo-<region> \
  --resource-group <vault-rg> \
  --vm "/subscriptions/<your-subscription-id>/resourceGroups/<backup-rg>/providers/Microsoft.Compute/virtualMachines/vm-sre-demo-backup" \
  --policy-name DefaultPolicy
```

### Step 2: Optionally fail a job to make the demo less boring

If all jobs succeeded, the audit will be a green stamp. To make the agent's branching visible, force a failure:

```bash
# Stop the VM mid-backup window — backup will fail
az vm deallocate -g <backup-rg> -n vm-sre-demo-backup
# After ~10 min the backup attempt will fail; restart the VM before demo
az vm start -g <backup-rg> -n vm-sre-demo-backup
```

---

## Minute-by-minute script

### 0:00 — Frame (45 s)

> *"'Do we have backup?' is the wrong question. The right question is 'when did the last successful restore point complete, how big is it, and could we actually restore from it within RTO?' Most teams can't answer that under audit pressure. Let's see what the agent finds."*

### 0:45 — Paste the prompt (15 s)

```
Audit the backup health for vm-sre-demo-backup in <backup-rg>
(subscription <your-subscription-id>). I need RTO/RPO numbers and
any failed jobs in the last 30 days.
```

### 1:00–4:00 — The audit (~3 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az backup vault list` + resolve which vault protects the VM | *"Finds the vault. Even in a multi-vault environment with shared policies"* |
| 2 | `az backup item show` | *"Reads the protected item — confirms it's actively under backup, not just historically"* |
| 3 | `az backup job list --status Failed --start-date ...` | *"Failed jobs in the last 30 days. There's one — 6 days ago. Reads its error reason"* |
| 4 | `az backup recoverypoint list` | *"Lists recovery points. Reads timestamps. Newest is from 8 hours ago — within the default 24h RPO. Good"* |
| 5 | `az backup item show --query properties.protectionPolicyName` + `az backup policy show` | *"Reads the policy. Snapshot retention 14 days, vault retention 30. Notes that vs the team's stated requirements (we'd ask the human if those numbers fit)"* |
| 6 | RTO estimate | **Estimated restore time: ~25 minutes for this VM size + recovery point size.** Based on Azure published RPO/RTO guidance + observed snapshot size |
| 7 | Verdict | **Audit pass — but with caveats**: 1 failed job 6 days ago (reason: VM deallocated during backup window). Recommend: alert on backup-job-failed to catch this faster. Recovery point lineage is healthy. |

### 4:00–5:00 — Approve a follow-up (1 min)

The skill suggests setting up an Azure Monitor alert for `BackupJobFailed` events. Approve. Agent creates the alert rule with a 1-failure-per-day threshold.

> *"Now the next time a backup fails, someone gets paged within minutes. Compliance + reliability story, both addressed."*

---

## Expected agent behaviour

| Skill loaded | `backup-health-verification` |
| Tools used | RunAzCliReadCommands (vault/item/job/recoverypoint queries), RunAzCliWriteCommands (alert creation) |
| Output | **Audit-style report**: vault, policy, last success, last failure, RPO/RTO numbers, recommendations |
| Read-only by default | The skill doesn't modify backup policies or recovery points; only creates alerts (with approval) |
| Stop hook | Summary section enforced; structure is audit-friendly |

---

## Fallback prompts

```
Use the backup-health-verification skill on vm-sre-demo-backup in <backup-rg>.
```

```
What's our backup posture for vm-sre-demo-backup?
```

---

## Talking points

- **"Audit-grade output."** Vault name, policy name, success/failure history, RPO/RTO numbers, recommendations — exactly the report a compliance auditor asks for.
- **"Pairs with scheduled tasks."** Run this on a schedule (cron) across the whole VM fleet — every Monday you get a state-of-backup report. See `scheduled-tasks/02-weekly-cost-watcher.md` for the cadence pattern.
- **"Doesn't change protection policy."** Read-only audit + creates alerts (with human approval). Backups themselves untouched.

---

## Cleanup

After demo:

```bash
# If you created the vault just for this demo:
az backup protection disable --vault-name rsv-sre-demo-<region> \
  -g <vault-rg> --container-name <auto> --item-name <auto> --delete-backup-data true
# (or leave the vault running; ~$0/month idle)
```

---

## Variants

- **Multi-VM audit**: prompt the agent for the entire `workload=sre-demo` tag — it audits every VM under that tag in one report.
- **Cost angle**: pair with `scheduled-tasks/02-weekly-cost-watcher.md` — orphaned recovery points are a real cost driver.
- **Restore test**: extend the demo by asking the agent to identify which recovery point would be used for a P0 restore. It picks the newest successful + reads its size + estimates restore duration.
