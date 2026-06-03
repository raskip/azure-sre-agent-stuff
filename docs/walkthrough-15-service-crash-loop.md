# Scenario 15 — Service Crash-Loop Detection

> **Duration:** 5 minutes | **Skill:** `service-crash-loop-detection` | **Impact:** Medium — DevOps audience

---

## Goal

Show the agent investigating **a systemd service that keeps crashing**: reads `systemctl status`, walks the journal logs back to the crash signature, identifies whether it's an OOM, a config error, a missing dependency, or a code bug — then proposes a stable remediation instead of just `systemctl restart`.

**Why this works:** Most "service unhealthy" responses devolve into restart loops. The agent's job is to *break the loop* by finding the actual cause. Showing that distinction — restart vs root-cause-then-fix — is the value.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario svc -NoWait
```

### Step 2: Create a deliberately-flapping service

```bash
./examples/sre-agent/scripts/simulate-issues.sh service-crash
```

This creates a systemd service (`demo-bad.service`) that calls a binary with an invalid argument and `Restart=always`. After ~30 seconds it's crash-looped 5+ times, visible in `systemctl status demo-bad`.

---

## Minute-by-minute script

### 0:00 — Frame (45 s)

> *"Restart loops are operator pain at its purest — the service keeps coming back, then falling over, and on-call eventually adds a Cron job to restart it every 5 minutes. That's not a fix; it's a tax. Let's see if the agent finds the actual cause."*

### 0:45 — Paste the prompt (15 s)

```
The demo-bad service on vm-sre-demo-svc in <svc-rg>
(subscription <your-subscription-id>) keeps restarting. Investigate
and fix.
```

### 1:00–4:00 — The investigation (~3 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm run-command invoke` → `systemctl status demo-bad.service` | *"Status first. Reads `Active: failed`, `Failed runs: 5+`, the last few attempt timestamps. Crash-loop signature confirmed"* |
| 2 | `journalctl -u demo-bad.service --since "10 min ago" --no-pager | tail -50` | *"Pulls recent journal entries. There's the actual error — the binary is being called with an invalid `--mode` argument"* |
| 3 | `systemctl cat demo-bad.service` | *"Reads the unit file. Sees `ExecStart=/usr/local/bin/my-app --mode crazy` — and 'crazy' isn't a valid mode the app supports"* |
| 4 | Classifies the crash | **Branch A: config / argument error** (vs B: OOM kill from cgroup limit, vs C: missing dependency, vs D: code bug — needs upstream fix) |
| 5 | Proposes fix | **Option A**: edit the unit file to use a valid `--mode` value. **Option B**: stop + disable the service (if it's not actually needed). Recommends A. |
| 6 | Applies fix (with approval) | `systemctl edit demo-bad.service` to add a drop-in with the corrected ExecStart, then `daemon-reload` + `restart`. Verifies it stays `active (running)` for > 30s. |

### 4:00–5:00 — Verify + summary (1 min)

`systemctl status demo-bad.service` shows `Active: active (running)`, uptime increasing. `## Summary` heading recaps. Stop-hook fires.

> *"It didn't restart and pray. It read the journal, found the bad argument, and corrected the unit. The kind of fix you'd want a senior engineer to apply, applied autonomously."*

---

## Expected agent behaviour

| Skill loaded | `service-crash-loop-detection` |
| Tools used | RunAzCliWriteCommands (run-command for systemctl + journalctl + edits) |
| Classification | Config / OOM / dependency / code-bug — four branches, four different remediations |
| Default action | **Diagnose first, fix only with approval** |
| Stop hook | Summary section enforced |

---

## Fallback prompts

```
Use the service-crash-loop-detection skill on vm-sre-demo-svc in <svc-rg>.
```

```
Why does demo-bad.service keep crashing on vm-sre-demo-svc?
```

---

## Talking points

- **"Restart isn't a fix."** The skill explicitly avoids the `systemctl restart` reflex. It reads the journal first.
- **"Drop-in over edit."** When it modifies a unit, it uses `systemctl edit` to create a drop-in — preserves the original, doesn't touch upstream package files. Audit-friendly.
- **"Branches change everything."** OOM-crash means scale up or trim memory usage. Config-crash means fix the config. Dependency-crash means check what's missing. Code-bug means *don't auto-fix; escalate*. The agent distinguishes.
- **"Generalises beyond systemd."** Pairs well with container runtimes (CrashLoopBackOff in AKS) — same reasoning, different tool surface.

---

## Cleanup

```bash
./examples/sre-agent/scripts/simulate-issues.sh service-crash --stop
az vm deallocate -g <svc-rg> -n vm-sre-demo-svc --no-wait
```

---

## Variants

- **OOM-crash branch**: trim the cgroup memory limit in the unit so the service hits the limit and gets killed → Branch B classification.
- **Missing dependency branch**: remove a package the binary needs → Branch C.
- **Code-bug branch**: deliberately crash the binary with a segfault → Branch D, agent should *escalate* not auto-fix.
- **AKS pair**: same reasoning applied to a CrashLoopBackOff pod, when an AKS skill is added in a future iteration.
