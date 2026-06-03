# Scenario 11 — Memory Pressure & OOM Investigation

> **Duration:** 5 minutes | **Skill:** `high-memory-oom-troubleshooting` | **Impact:** Medium — pairs naturally with the CPU demo

---

## Goal

Demonstrate the agent investigating a different resource-pressure class than CPU: **memory exhaustion**, swap thrash, and OOM kills. The agent reads `free`, `vmstat`, `dmesg` for OOM-killer entries, identifies the culprit process, and reasons about whether the right answer is restart, scale-up, scale-out, or a real memory leak fix.

**Why this works:** Memory pressure is sneakier than CPU. It often manifests as "VM is slow but CPU is fine". The agent's job is to see through that and find the actual signal — swap-in, OOM events, RSS growth — that a naive operator would miss.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy + saturate memory

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario mem -NoWait
./examples/sre-agent/scripts/simulate-issues.sh high-memory --duration 20
```

This runs `stress-ng --vm 2 --vm-bytes 3G --vm-keep` on `vm-sre-demo-mem` (a 2 GiB VM), forcing memory pressure + swap thrash + eventual OOM kills.

### Step 2: Confirm starting state

After ~2 minutes you should see `Available Memory Bytes` collapse to <200 MB and `Page Reads/sec` spike — that's the swap thrash signature.

---

## Minute-by-minute script

### 0:00 — Frame the problem (45 s)

> *"CPU is the easy one. Memory pressure is where most on-call rotations fail — because it manifests as 'general slowness' with CPU at 30% and people assume it's the application. Let's see if the agent can find the real signal."*

### 0:45 — Paste the prompt (15 s)

```
VM vm-sre-demo-mem in <mem-rg> (subscription <your-subscription-id>)
is becoming unresponsive. CPU looks fine but everything is slow.
Investigate.
```

### 1:00–4:00 — The agent's investigation (~3 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm show` + SKU lookup → 2 GiB Standard VM | *"Notes the memory ceiling — 2 GiB. Anything close to that is suspect"* |
| 2 | `az monitor metrics list --metric "Available Memory Bytes"` | *"Available memory is dropping fast. That's host-side visibility — Linux's `free` would lie about this if the kernel had reclaimed page cache"* |
| 3 | `az monitor metrics list --metric "Inbound Flows" / "Network Throughput"` (rules out network) | *"Rules out a network bottleneck. Notice it's not jumping to conclusions"* |
| 4 | `az vm run-command invoke` → `free -m && vmstat 1 5 && cat /proc/meminfo | head -20` | *"Goes inside the guest. `free` shows 100 MB available, `vmstat` shows `si` and `so` at hundreds — that's swap-in/swap-out activity. The system is thrashing"* |
| 5 | `ps aux --sort=-%mem | head -10` + `cat /proc/<pid>/status | grep VmRSS` | *"Identifies the top memory consumer — `stress-ng-vm` holding 3 GB of resident set"* |
| 6 | `dmesg | grep -i "out of memory" | tail -5` | *"OOM-killer logs! Look — the kernel has already killed processes. This isn't just pressure, it's active OOM kills happening"* |
| 7 | Classification | **Pressure source: userspace memory exhaustion by a single process** (vs Branch B: kernel memory leak, Branch C: page cache pressure from IO-heavy workload) |
| 8 | Remediation options | Three: (a) restart the offending process / pod, (b) scale up VM SKU to 4 GiB, (c) fix the leak in the application. Each with its trade-off. |

### 4:00–5:00 — Approve a remediation + verify (1 min)

Choose (a) — restart the process. The agent runs the kill, watches `Available Memory Bytes` climb back to ~1.5 GB, confirms the recovery in `## Summary`.

> *"Notice — it didn't immediately propose 'scale up the VM'. That's the easy expensive answer. It read the situation: one bad process. Restart fixes it. Real engineering."*

---

## Expected agent behaviour

| Skill loaded | `high-memory-oom-troubleshooting` |
| Tools used | RunAzCliReadCommands (metrics, vm-show), RunAzCliWriteCommands (run-command) |
| Cross-source correlation | Azure Monitor "Available Memory Bytes" + in-guest `free`/`vmstat`/`dmesg` (OOM-killer logs) |
| Classification | **Userspace OOM** (vs kernel leak vs page cache) |
| Remediation | Restart-first, scale-up-second |
| Stop hook | `## Summary` enforced |

---

## Fallback prompts

```
Use the high-memory-oom-troubleshooting skill on vm-sre-demo-mem in <mem-rg>.
```

```
Investigate memory pressure on vm-sre-demo-mem.
```

---

## Talking points

- **"Memory hides."** Available Memory ≠ free memory; the kernel reclaims page cache to make `free` look fine. The agent reads the metrics that actually matter (swap-in rate, OOM-killer dmesg).
- **"OOM kills are the canary."** If dmesg shows OOM-killer ran, you're past the warning stage. The agent surfaces this without being asked.
- **"Don't auto-scale to mask a leak."** The cheapest correct remediation is restart-the-process. Scale up is for sustained legitimate growth, not for hiding a leak. The agent makes the distinction.

---

## Cleanup

```bash
./examples/sre-agent/scripts/simulate-issues.sh high-memory --stop
az vm deallocate -g <mem-rg> -n vm-sre-demo-mem --no-wait
```

---

## Variants

- **Page-cache pressure demo**: change the fault to a `dd if=/dev/zero` write loop — same low Available Memory, but no OOM kills. Agent should land in **Branch C: page cache pressure, not userspace OOM**.
- **Kernel leak demo**: pin a kernel module that intentionally leaks `kmalloc` — Branch B classification.
- **Pair with high-CPU**: same VM, different fault, different skill — shows the agent's reasoning shifts based on the symptom, not just the resource.
