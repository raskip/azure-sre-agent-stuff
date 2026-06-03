# Scenario 10 — Disk Expansion (The Remediation Closer)

> **Duration:** 7–10 minutes | **Skill:** `disk-expansion` | **Impact:** Highest — this is the closer

---

## Goal

Show the agent **performing** a real remediation end-to-end: resize a managed disk via Azure Resource Manager, rescan the SCSI bus inside the VM, grow the partition, grow the filesystem, verify with `df -h`. **Three control planes** (Azure API, kernel, filesystem) — one prompt. The agent's reasoning makes correct decisions about partition tables, LVM presence, and online vs offline operations.

**Why this works:** Most automation demos stop at "the agent diagnosed the problem". This one **executes the fix**. Audiences see the autonomy story end-to-end with a remediation that has visible before/after state.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy + fill the disk

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario diskexpand -NoWait
./examples/sre-agent/scripts/simulate-issues.sh disk-full
```

This creates `<diskexpand-rg>` with a 32-GiB data disk at `/mnt/data` and fills it to ~95% with `fallocate`. `df -h` inside the VM will show `Use% ≈ 95%`.

### Step 2: Confirm starting state

```bash
az disk show -g <diskexpand-rg> -n vm-sre-demo-diskexpand-data --query "{size:diskSizeGB, sku:sku.name}" -o tsv
# 32  StandardSSD_LRS
```

> The data disk topology in this demo is **raw block device → ext4** (no partition table, no LVM). The agent's skill is topology-aware and detects this; it doesn't blindly run `growpart`.

---

## Minute-by-minute script

### 0:00 — Frame the closer (1 min)

> *"This is the one. So far we've watched the agent diagnose things and propose fixes. Now we watch it actually do the fix — across three different control planes — based on one English sentence. If it works, this is the scenario that builds the cost-savings case."*

Show `df -h` output via the portal or a side terminal:

```
/dev/sdc      32G   30G  1.5G   95%  /mnt/data
```

### 1:00 — Paste the prompt (15 s)

```
The data disk on vm-sre-demo-diskexpand in <diskexpand-rg>
(subscription <your-subscription-id>) is at 95% capacity. Expand it to 64 GiB
and grow the filesystem online. No downtime tolerated.
```

### 1:15–7:00 — The execution arc (~6 min, narrate)

#### Plane 1: Azure ARM (1–2 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm show` → confirms VM is `Running` | *"Online operation requires the VM to be running. It checks."* |
| 2 | `az disk show` → reads current size (32 GiB) + SKU + LUN | *"Reads current state — 32 GiB, Standard SSD, LUN 0. Notes that Standard SSD supports online resize without VM restart"* |
| 3 | **Asks for approval**: *"Proposed: resize `vm-sre-demo-diskexpand-data` from 32 → 64 GiB. Standard SSD permits this online with no compute downtime. Approve?"* | **Click Approve.** |
| 4 | `az disk update --size-gb 64` | *"Resize call returns. Disk is now 64 GiB at the ARM level. But the kernel inside the VM still sees 32"* |

#### Plane 2: Kernel (SCSI rescan) (1–2 min)

| 5 | `az vm run-command invoke` → `echo 1 > /sys/class/scsi_device/.../device/rescan` | *"The Linux kernel doesn't watch ARM. It has to be told to re-read the disk size"* |
| 6 | `lsblk` → confirms `/dev/sdc` now shows 64G | *"Kernel sees 64G now"* |
| 7 | Topology probe: `blkid`, `lsblk -o NAME,TYPE,FSTYPE`, `mount | grep sdc` | *"Critical — what kind of filesystem layout do we have? Raw + ext4? Partition + ext4? LVM? The right next command depends on this"* |

#### Plane 3: Filesystem (online grow) (1–2 min)

| 8 | Topology classification | **Verdict: raw block device, ext4 directly on `/dev/sdc`. No partition table → skip `growpart`. No LVM → skip `lvextend`.** |
| 9 | `resize2fs /dev/sdc` | *"Online ext4 resize. Doesn't unmount, doesn't restart. Just tells the filesystem 'use the rest of the space'"* |
| 10 | `df -h /mnt/data` | **Before: 32G used 95%. After: 64G used 47%.** Numbers visible to the audience |

### 7:00–8:00 — The summary (1 min)

The Stop hook fires; `## Summary` heading shows:

> *"Root cause: data disk at 95% utilisation, projected to fill within 18 hours at current growth rate.
> Action taken: expanded `vm-sre-demo-diskexpand-data` from 32 → 64 GiB online (no VM restart). Rescanned SCSI bus to refresh kernel view. Grew ext4 filesystem on `/dev/sdc` with `resize2fs`. Now at 47% utilisation.
> Verification: `df -h /mnt/data` reports 64G total, 30G used, 33G free.
> Cost impact: +$1.92/month at Standard SSD per-GB pricing."*

> *"Three control planes. One prompt. No human in any of them after the approval."*

### 8:00–9:00 — Reset for next demo run (1 min, optional)

```bash
./examples/sre-agent/scripts/reset-diskexpand.sh
```

Shrinks the disk back to 32 GiB (offline operation — VM restarts), so you can re-run the demo for the next audience.

---

## Expected agent behaviour

| Skill loaded | `disk-expansion` |
| Tools used | RunAzCliReadCommands + RunAzCliWriteCommands (resize + run-command) |
| **Topology classification** | Raw block device → no growpart, no LVM. **The skill is topology-aware; it doesn't blindly run growpart.** |
| Approval gate | Asks before `az disk update` (Review mode) |
| Tools chain | `disk update` → `scsi rescan` → `resize2fs` (or `growpart + resize2fs` if partition table was present) |
| Stop hook | Summary section enforced |

---

## What the skill avoids (the value proposition)

- ❌ Does not blindly run `growpart` on a raw block device (would fail)
- ❌ Does not skip the SCSI rescan (kernel would still see old size)
- ❌ Does not require VM restart for online ext4 / xfs (it would for offline filesystems)
- ❌ Does not over-resize (uses the operator's stated target, doesn't extrapolate)

---

## Fallback prompts

```
Use the disk-expansion skill to grow the data disk on vm-sre-demo-diskexpand
in <diskexpand-rg> to 64 GiB.
```

```
The data disk on vm-sre-demo-diskexpand is almost full. Expand to 64 GiB.
```

---

## Talking points

- **"Three planes, one prompt."** ARM resize → kernel rescan → filesystem grow. Each is a separate technology with separate failure modes; the agent sequences them correctly.
- **"Topology-aware."** Raw vs partitioned vs LVM matter. The skill probes first, branches second. *"Not a script. A reasoning agent."*
- **"Online by default."** Right-sized for production. Standard SSD supports online resize; Premium SSD v2 too. The agent knows which.
- **"Approval gate where it matters."** Resize is reversible-ish (you can shrink) but costs money + has a tiny risk of corruption if something goes wrong. The approval pause is the right place to put the human.

---

## Cleanup

After demo:

```bash
# Reset for re-run:
./examples/sre-agent/scripts/reset-diskexpand.sh

# Or full teardown:
az group delete -n <diskexpand-rg> --yes --no-wait
```

---

## Variants

- **Failure-mode demo**: artificially break the SCSI rescan step (e.g., remove sudo) and watch the agent diagnose + retry.
- **LVM topology demo**: deploy a VM with LVM in cloud-init, re-run. The skill takes a different branch (`lvextend` + `resize2fs`).
- **Premium SSD v2**: do this on PSSDv2 — even faster, and the agent picks up the SKU difference automatically.
- **Pair with Scenario 09**: combined disk story — first throttling-based reasoning, then expansion as the answer.
