# Scenario 16 — VM Connectivity Troubleshooting

> **Duration:** 5 minutes | **Skill:** `vm-connectivity-troubleshooting` | **Impact:** Medium — networking-flavoured audience

---

## Goal

Show the agent diagnosing **SSH/RDP failures**: it walks NSG rules, checks the VM's effective routes, reads boot diagnostics, and probes the OS firewall — all from a single prompt. It identifies whether the block is at the cloud edge (NSG), the routing layer (UDR), the VM boot itself, or the OS firewall.

**Why this works:** "Can't connect to the VM" is one of the most common Tier-1 tickets, and root-causing it manually takes a senior engineer 15–30 minutes of clicking through portal blades. The agent does it in 2 minutes and surfaces the actual answer.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario conn -NoWait
```

### Step 2: Inject a connectivity break

```bash
./examples/sre-agent/scripts/simulate-issues.sh nsg-block
```

This adds an NSG rule that denies inbound 22 from `0.0.0.0/0` (priority lower than the AllowSSH-Demo rule). The block is subtle — the AllowSSH rule still exists but is overridden by the new Deny — so the agent has to read NSG rule **priority order**, not just "is there a deny rule".

---

## Minute-by-minute script

### 0:00 — Frame (45 s)

> *"VM-can't-connect tickets are one of the most boring engineering exercises — walk every layer top to bottom, find the one block. The agent does it in two minutes by reading rule priority correctly. Watch."*

Show the symptom: try to SSH to the VM (will hang/refuse).

### 0:45 — Paste the prompt (15 s)

```
I can't reach vm-sre-demo-conn in <conn-rg>
(subscription <your-subscription-id>) on SSH. Has been working for weeks,
broke today. Investigate.
```

### 1:00–4:00 — The investigation (~3 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm get-instance-view` → power state + boot diagnostics URI | *"VM is `Running` and recently booted. Boot diagnostics show clean console. Rules out 'the OS hasn't come up'"* |
| 2 | `az network nic show` → resolves NIC + NSG + subnet NSG | *"Two NSGs to check — NIC-level AND subnet-level. Most people forget the subnet one"* |
| 3 | `az network nic list-effective-network-security-rules` | *"This is the killer call. It computes the *effective* rules including subnet + NIC + Azure platform rules, in priority order. Reads the resolved set"* |
| 4 | Identifies offending rule | *"There. Rule `DenyAllSSH-Inbound` at priority 100, source `*`. The AllowSSH-Demo rule at priority 1000 is overridden. Rule priority 100 < 1000, so the deny wins"* |
| 5 | `az network route-table show` for the subnet's UDR (defensive) | *"Also confirms no weird UDR is sending SSH traffic to a black-hole route. NSG is the only block"* |
| 6 | `az vm run-command invoke` → `sudo iptables -L INPUT --line-numbers | head -10` | *"And checks the OS firewall just to rule out a host-level block. iptables is wide open. Issue is 100% the NSG"* |
| 7 | Proposes remediation | **Option A**: delete the offending rule (was it added by mistake?). **Option B**: lower its priority below the AllowSSH rule. **Option C**: scope it more narrowly so it doesn't catch legitimate SSH. Recommends investigation of *who added the rule and when* before deleting (uses Activity Log) |
| 8 | Investigates: Activity Log → `Microsoft.Network/networkSecurityGroups/securityRules/write` events in last 7 days | *"Found the audit trail — added by user X at timestamp Y. Recommends asking that user before deleting"* |

### 4:00–5:00 — Wrap (1 min)

The agent does **not** auto-delete the rule. It produces a Summary section with:
- Root cause (offending NSG rule + priority order)
- Who added it (Activity Log evidence)
- 3 remediation options
- A specific question to ask the human ("Was this rule added intentionally as a maintenance lock?")

> *"That's not just diagnosis. That's diagnosis-with-audit-trail. The kind of report you'd put in a postmortem."*

---

## Expected agent behaviour

| Skill loaded | `vm-connectivity-troubleshooting` |
| Tools used | RunAzCliReadCommands (NIC/NSG/UDR/Activity Log) + RunAzCliWriteCommands (run-command for iptables check) |
| Layered investigation | Boot → NSG (NIC + subnet, effective rules) → UDR → OS firewall — in that order |
| **Priority awareness** | Reads NSG rule priority order, not just deny/allow presence |
| Audit-trail mining | Activity Log lookup to identify who added the offending rule |
| Default action | **Investigates only**; recommends but does not auto-delete network rules |
| Stop hook | Summary section enforced |

---

## Fallback prompts

```
Use the vm-connectivity-troubleshooting skill on vm-sre-demo-conn in <conn-rg>.
```

```
Why can't I SSH to vm-sre-demo-conn?
```

---

## Talking points

- **"Effective rules, not configured rules."** Most network troubleshooting fails because people read the rules as configured, not as resolved at the kernel layer. The `list-effective-network-security-rules` call is the magic.
- **"Audit trail is the value-add."** Diagnosing the rule is half the job. Identifying *who* added it and *when* is what postmortems need.
- **"Read-only by default."** Network changes have blast radius; the skill explicitly avoids auto-correcting. Recommendation + audit trail → human approves.
- **"Generalises to RDP, custom ports, outbound."** Same skill, same priority-order logic, different rules.

---

## Cleanup

```bash
./examples/sre-agent/scripts/simulate-issues.sh nsg-block --stop
az vm deallocate -g <conn-rg> -n vm-sre-demo-conn --no-wait
```

---

## Variants

- **UDR black-hole**: instead of NSG deny, add a UDR sending SSH traffic to a non-existent next-hop → agent should land on the UDR branch, not the NSG branch.
- **OS-firewall iptables block**: skip the NSG change, add `iptables -A INPUT -p tcp --dport 22 -j DROP` → agent should reach Branch D (OS firewall).
- **Boot failure**: cordon the VM into a kernel-panic-on-boot state → Branch E (boot diagnostics + serial console).
- **Compound (NSG + OS firewall both)**: agent should report both layers, not just the first one found.
