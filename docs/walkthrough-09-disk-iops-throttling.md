# Scenario 09 — Disk IOPS Throttling Diagnosis

> **Duration:** 5–7 minutes | **Skill:** `disk-iops-throttling` | **Impact:** Medium-high — cross-layer correlation is the wow

---

## Goal

Show the agent diagnosing slow disk performance autonomously: it correlates **host-level Azure Monitor disk metrics** with **in-guest `iostat`** to distinguish IOPS throttling from throughput throttling, identifies the workload generating the IO, and recommends a remediation that fits the actual bottleneck (disk SKU resize vs Premium SSD v2 upgrade vs workload throttle vs caching).

**Why this works:** "Disk is slow" is one of the noisiest symptom classes — could be a thousand things. Watching the agent cross-reference Azure metrics with in-guest stats and land on "data disk IOPS cap, not throughput, not OS disk" is the moment audiences see the difference between an agent and a script.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Ensure `vm-sre-demo-diskiops` exists

```bash
# From the repo root:
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario diskiops -NoWait
```

This creates `<diskiops-rg>` with a 32-GiB Standard SSD data disk mounted at `/mnt/data`. The disk SKU has a low IOPS cap (500 IOPS / 100 MB/s), which throttles immediately under `fio` load.

### Step 2: Fire `fio` against the data disk

```bash
./examples/sre-agent/scripts/simulate-issues.sh disk-iops --duration 30
```

`fio` runs random-write 4 KB at queue depth 8 for up to 30 minutes via managed Run Command v2. Disk IOPS will saturate within ~60 seconds and `Data Disk IOPS Consumed Percentage` will sit at 100%.

Verify via `az monitor metrics list --metric "Data Disk IOPS Consumed Percentage" ...` if you want to see the climb.

---

## Minute-by-minute script

### 0:00 — Frame the problem (45 s)

> *"Slow disk is the worst kind of incident. Could be storage, could be the application, could be the OS, could be neighbouring workloads. Most teams give up and just resize to the next disk SKU and hope. Let's see if the agent can do better than 'resize and pray'."*

Show the alert / symptom (a Teams notification, a metric dashboard, or just the prompt below).

### 0:45 — Paste the prompt (15 s)

```
I'm getting alerts that VM vm-sre-demo-diskiops in resource group <diskiops-rg>
(subscription <your-subscription-id>) is showing very high disk latency.
Application response times have doubled. Investigate.
```

### 1:00–4:30 — Watch the agent work (~3.5 min)

The agent loads `disk-iops-throttling`. Open the **Tool calls** panel. Key moments to narrate:

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm show` → reads VM SKU + disk topology | *"First it figures out what kind of VM we're on — D2s_v5 has its own IOPS budget that's separate from the disk's"* |
| 2 | `az monitor metrics list --metric "Data Disk IOPS Consumed Percentage"` | *"Host-side view first. Notice this is sitting at 100%. The metric is data-disk specific — OS disk is fine"* |
| 3 | `az monitor metrics list --metric "VM Cached IOPS Consumed Percentage"` | *"It's also checking VM-level caps. They're not the bottleneck, so the throttle is at the disk SKU layer"* |
| 4 | `az vm run-command invoke` → in-guest `iostat -xz 1 5` | *"Now it goes inside the guest. iostat confirms — `await` is in the hundreds of milliseconds on `sdc`, and `%util` is pinned at 100"* |
| 5 | `iostat` again with `--name=fio` filter / `pgrep fio` | *"It found the actual process — fio. So the IO source isn't the OS or some daemon; it's a workload we (or the customer) launched"* |
| 6 | Classification verdict | **Branch A: IOPS-limited at the data disk SKU (Standard SSD, 500 IOPS cap), not throughput-limited, not VM-cap-limited** |
| 7 | Remediation options | Three options ranked: (a) Premium SSD v2 with custom IOPS, (b) resize disk to a larger Standard SSD, (c) move workload to a managed cache layer. Each with $/month + downtime estimate. |

### 4:30–5:30 — Approve a remediation (1 min)

Pick option (a) — Premium SSD v2 — and click **Approve**. The agent runs the migration prep steps. Don't actually complete the migration in a live demo (takes ~15 min); just show that the agent **knows the migration steps** and would execute them.

### 5:30–6:30 — Wrap (1 min)

Click into the agent's **Summary** section. Notice the Stop hook forced a `## Summary` heading. Read the summary aloud:

> *"Root cause: data disk IOPS cap exhausted by `fio` random writes at queue depth 8.
> Remediation: migrate `disk-sre-demo-iops` from Standard SSD (500 IOPS) to Premium SSD v2 with 5000 provisioned IOPS.
> Cost impact: +$8/month per disk.
> Verification: post-migration `Data Disk IOPS Consumed Percentage` should sit at ~10–15% under the same workload."*

> *"That's the difference. Not 'resize the disk'. 'Resize to this specific SKU with this specific provisioning, here's the cost delta, here's how we verify it worked.' That's the value."*

---

## Expected agent behaviour

| Skill loaded | `disk-iops-throttling` (auto-selected from the prompt) |
| Tools used | RunAzCliReadCommands (metrics, vm-show), RunAzCliWriteCommands (run-command invoke) |
| Classification | **Branch A — data disk IOPS-limited** (vs Branch B: throughput-limited, vs Branch C: VM-level cap-limited) |
| Cross-source correlation | Azure Monitor disk-level metric + in-guest `iostat` (this is the key story) |
| Stop hook | `require-summary-section` enforces `## Summary` heading |
| Remediation | Recommends + waits for human approval (Review mode) |

---

## Fallback prompts

If the agent doesn't auto-load the skill:

```
Use the disk-iops-throttling skill on vm-sre-demo-diskiops in <diskiops-rg>.
```

One-liner version:

```
Investigate disk IOPS throttling on vm-sre-demo-diskiops in <diskiops-rg>.
```

---

## Talking points (memorise these)

- **"Cross-layer is the whole game."** Any monitoring tool can show you "the disk metric is 100%". The agent ties that to a specific in-guest process via `iostat` + `pgrep` — *that's* what an SRE does manually.
- **"Throttling has flavours."** Disk SKU, VM cap, cache cap, throughput cap. The agent's classification matrix distinguishes them, because the remediation is different for each.
- **"Cost-aware remediation."** The agent surfaces the $/month delta — most teams don't have that conversation until the bill arrives.
- **"Review mode matters."** It proposed, it didn't execute. Production-grade safety on a remediation that costs real money.

---

## Cleanup

After the demo:

```bash
# Stop the fault
./examples/sre-agent/scripts/simulate-issues.sh disk-iops --stop
# Or just wait — fio self-terminates at the duration you set

# Deallocate the VM (keeps it for the next demo, no compute charges)
az vm deallocate -g <diskiops-rg> -n vm-sre-demo-diskiops --no-wait
```

Full teardown (rare):

```bash
az group delete -n <diskiops-rg> --yes --no-wait
```

---

## Variants

- **Comparison demo**: pair with Scenario 03 (right-sizing) — IOPS throttling story is also a VM-SKU-vs-disk-SKU conversation.
- **Combined disk demo**: chain into Scenario 10 (disk-expansion) — "the agent diagnosed throttling, but the better fix here is expansion, not SKU change". Shows the agent's reasoning, not just rules.
