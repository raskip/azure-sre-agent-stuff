# Scenario 12 — Security Incident Triage

> **Duration:** 6–7 minutes | **Skill:** `security-incident-triage` | **Impact:** High — the security audience demo

---

## Goal

Show the agent triaging a **suspicious activity** signal: investigate failed logins, identify rogue processes, surface unexpected open ports, check for filesystem integrity drift, and decide whether the situation calls for isolation, deeper forensics, or all-clear. The narrative target: **Tier-1 security triage, fully autonomous**.

**Why this works:** Security teams are perpetually short-handed. "Could you take a quick look at this alert and tell me if it's real?" is the most repeated SOC ask. Watching the agent do that triage from a single sentence — with the right tools called in the right order — is the security audience's wow moment.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario svc -NoWait
```

We re-use the `svc` scenario VM (`vm-sre-demo-svc`) for security demos too — the skill is OS-level, doesn't require a specific image.

### Step 2: Inject suspicious activity

```bash
./examples/sre-agent/scripts/simulate-issues.sh security-incident
```

This via Run Command v2 does several things on the VM:
- Adds ~50 failed `sshd` login entries to `/var/log/auth.log` (simulated brute-force attempt)
- Launches a fake "rogue" process under a non-standard name listening on `127.0.0.1:31337`
- Touches `/etc/passwd` (changes mtime; doesn't actually modify content)

These are pure simulation — no real attack, no real network exposure. The agent's classification should converge on **simulated** signals after correlating.

---

## Minute-by-minute script

### 0:00 — Frame (1 min)

> *"Your SOC has 1000 alerts a day. Maybe 5 are real. Tier-1 triage — figuring out which is which — eats the team's entire day. Let's see what the agent does with a single suspicious alert."*

### 1:00 — Paste the prompt (15 s)

```
Defender for Cloud is flagging suspicious activity on vm-sre-demo-svc
in <svc-rg> (subscription <your-subscription-id>). Triage it. Is this
real or noise?
```

### 1:15–5:00 — The triage flow (~3.5 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm show` + tags + recent Activity Log | *"Context first. Is this a known demo VM or a production critical asset? Tags say `workload=sre-demo` — lower the panic level immediately"* |
| 2 | `az security alert list --filter "ResourceId contains 'vm-sre-demo-svc'"` | *"Pulls Defender for Cloud alerts. Reads them in order"* |
| 3 | `az vm run-command invoke` → in-guest `last -F -n 30; lastb -F -n 30` | *"Failed login history. There it is — 50+ failed root attempts from a single IP in the last 10 minutes. Brute force pattern"* |
| 4 | `ps auxef | grep -v "\[" ; ss -tlnp` | *"Processes + listening ports. Found it — a process named `not_a_backdoor.elf` listening on 127.0.0.1:31337"* |
| 5 | `find /etc -mmin -60 -type f` | *"What's changed in /etc in the last hour? `passwd` shows recent mtime. Suspicious enough to flag"* |
| 6 | `stat /etc/passwd` + diff against a known good hash if available | *"But contents match expected. mtime changed without content change — looks like a `touch` test, not an actual modification"* |
| 7 | Cross-correlate signals | **Verdict: simulated / training. The brute-force pattern + suspicious-process + mtime-only change on /etc/passwd matches a security-drill signature, not an active attack** |
| 8 | Recommendation | "Recommend: tag this thread `simulation-confirmed`, suppress similar alerts on demo-tagged VMs for the next 24h, and re-engage if any of these signals appear on a non-demo-tagged VM." |

### 5:00–6:00 — Approve + record (1 min)

The agent doesn't take destructive action automatically (it's a triage skill, not a kill-the-VM skill). Instead it offers: (a) acknowledge the Defender alert, (b) create a memory note for future similar patterns, (c) escalate to humans if anything in the triage felt off.

Choose (b). The agent saves a synthesized memory note like:

> *"Pattern: brute-force + named-process + /etc mtime-only is a Defender drill / demo signature on demo-tagged VMs. Suppress noisy escalation for similar combinations."*

---

## Expected agent behaviour

| Skill loaded | `security-incident-triage` |
| Tools used | RunAzCliReadCommands (defender, activity log, vm-show), RunAzCliWriteCommands (run-command for in-guest checks) |
| Cross-source correlation | Defender alerts + Activity Log + in-guest auth.log + process list + filesystem mtime |
| **Verdict pathway** | Real attack vs simulated/drill vs noise — three branches, each with different follow-up |
| Default action | **Triage only — does not isolate, does not block, does not stop services**. Recommendation goes to a human. |
| Memory side-effect | Writes a synthesized memory note for future similar patterns |

---

## Why this is a triage skill, not a remediation skill

- Security remediations have **regulatory consequences** (chain of custody, incident-response playbooks, legal notifications). The agent intentionally **does not auto-isolate or auto-kill**. It triages and hands a clear recommendation to a human.
- The skill is **noise-reduction first, action second**. SOC pain is alert fatigue, not lack of action. Filtering noise is the bigger value.

---

## Fallback prompts

```
Use the security-incident-triage skill on vm-sre-demo-svc in <svc-rg>.
```

```
Investigate the suspicious activity alert on vm-sre-demo-svc.
```

---

## Talking points

- **"Triage is the bottleneck."** Real attacks are rare; noise is constant. The agent's value is filtering, not striking.
- **"Defaults to safe."** No kill-on-suspicion. The skill explicitly recommends, doesn't act, on security findings.
- **"Memory across investigations."** After the agent has classified one drill, it recognises the pattern faster next time. Compounding value.
- **"Audit trail."** Every step (Defender query, auth.log read, process list, etc.) is logged for chain-of-custody, regardless of how the human follows up.

---

## Cleanup

```bash
# Stop the rogue process + clear simulated entries
./examples/sre-agent/scripts/simulate-issues.sh security-incident --stop

# Or just deallocate the VM
az vm deallocate -g <svc-rg> -n vm-sre-demo-svc --no-wait
```

---

## Variants

- **Real-looking drill**: pair with a Defender for Cloud alert suppression rule for `workload=sre-demo` tag — shows the policy + agent stack.
- **Cross-VM lateral movement drill**: deploy 2 VMs, simulate access from one to the other; watch the agent correlate.
- **Chain into the on-call subagent**: pair with `safe_vm_troubleshooter` (Scenario 07) — the security subagent triages and hands off to the troubleshooter for deeper context-gathering.
