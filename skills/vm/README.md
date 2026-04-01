# Azure SRE Agent — VM Troubleshooting Skills

> **10 example skills** for diagnosing, triaging, and remediating Azure VM issues — designed as starting points you can test, customize, and extend for your environment.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **SRE Agent** | An Azure SRE Agent in **Running** state ([sre.azure.com](https://sre.azure.com)) |
| **Skills loaded** | All 10 VM skills added to the agent (see [How to add skills](../README.md#how-to-add-a-skill-to-your-agent)) |
| **Resource group access** | The agent's managed identity needs access to the target resource group |
| **Permission level** | Depends on the skill type — see below |

### Permission levels

| Level | Role | Skills that need it |
|-------|------|---------------------|
| **Reader** | `Reader` on the resource group | All diagnostic/advisory skills (read metrics, run read-only commands) |
| **Privileged** | `Contributor` or a custom role with write permissions | Remediation skills (`disk-expansion`, `vm-extension-failure-remediation`) |

> 💡 **Tip:** For testing, `Contributor` on the target resource group is the easiest way to cover all skills. For production, scope permissions to the minimum required for each skill.

---

## Skills at a glance

| # | Skill | Type | Description |
|---|-------|------|-------------|
| 1 | [`disk-expansion`](disk-expansion/) | Remediation | Expand VM disks when space is low |
| 2 | [`high-cpu-vm-troubleshooting`](high-cpu-vm-troubleshooting/) | Diagnostic | Diagnose high CPU — top processes, per-core breakdown |
| 3 | [`high-memory-oom-troubleshooting`](high-memory-oom-troubleshooting/) | Diagnostic | Diagnose memory pressure, swap, OOM kills |
| 4 | [`vm-connectivity-troubleshooting`](vm-connectivity-troubleshooting/) | Diagnostic | Diagnose SSH/RDP failures — NSGs, routes, OS firewall |
| 5 | [`service-crash-loop-detection`](service-crash-loop-detection/) | Diagnostic | Investigate services that keep crashing |
| 6 | [`security-incident-triage`](security-incident-triage/) | Diagnostic | Triage brute-force attempts, rogue processes, open ports |
| 7 | [`vm-right-sizing`](vm-right-sizing/) | Advisory | Analyze utilization and recommend optimal VM SKU |
| 8 | [`backup-health-verification`](backup-health-verification/) | Diagnostic | Verify Azure Backup config, recovery points, failed jobs |
| 9 | [`vm-extension-failure-remediation`](vm-extension-failure-remediation/) | Remediation | Diagnose and fix failed VM extensions |
| 10 | [`disk-iops-throttling`](disk-iops-throttling/) | Diagnostic | Investigate disk IOPS/throughput throttling |

---

## Trying the skills

Use this guide to pick which skills to try first based on your scenario.

### Quick start (1–2 skills)

Best skills to try first:

| Skill | Why start here |
|-------|---------------|
| `high-cpu-vm-troubleshooting` | Simple setup, fast results — everyone understands "the server is slow" |
| `security-incident-triage` | Shows multi-faceted investigation (auth logs, connections, processes) |
| `vm-right-sizing` | Low setup effort — just deploy an oversized VM and let it idle |

### Deeper evaluation (3–5 skills)

Once comfortable, try these to explore more capabilities:

| Skill | Why |
|-------|-----|
| `disk-iops-throttling` | Agent correlates VM-level and disk-level metrics — shows depth |
| `vm-connectivity-troubleshooting` | Multi-layer diagnosis (NSG → routes → OS firewall → service) |
| `service-crash-loop-detection` | Agent reads system logs and identifies crash patterns |
| `disk-expansion` | Remediation skill — the agent actually fixes the problem (with safety checks) |

### Full walkthrough (all skills)

To evaluate the full set, work through each skill's testing guide:

| Phase | What to test |
|-------|-------------|
| **1. Diagnostics** | `high-cpu-vm-troubleshooting`, `high-memory-oom-troubleshooting`, `disk-iops-throttling` |
| **2. Multi-layer** | `vm-connectivity-troubleshooting`, `service-crash-loop-detection`, `security-incident-triage` |
| **3. Advisory** | `vm-right-sizing`, `backup-health-verification` |
| **4. Remediation** | `disk-expansion`, `vm-extension-failure-remediation` |
| **5. Governance** | Test with hooks (`restrict-to-readonly`, `block-dangerous-commands`) and re-test |

---

## Skill highlights

### 1. disk-expansion

| | |
|---|---|
| **Best for** | Remediation — the agent actually *fixes* the problem |
| **Complexity** | Medium |
| **Impact** | High — shows the agent going beyond diagnosis into action |
| **Setup effort** | Medium — need a VM with a nearly-full disk |
| **What makes it great** | The agent checks current usage, identifies the constrained disk, validates there's room to expand, performs the expansion, and verifies the result. It's a complete end-to-end remediation story. |

### 2. high-cpu-vm-troubleshooting

| | |
|---|---|
| **Best for** | Quick win — everyone understands "the server is slow" |
| **Complexity** | Low |
| **Impact** | High — immediate "wow" when the agent finds the process in seconds |
| **Setup effort** | Low — just run a stress tool or CPU-intensive script |
| **What makes it great** | The agent pulls Azure Monitor metrics, SSHes into the VM via run-command, identifies the top CPU consumers, breaks down per-core usage, and delivers a structured report. Great for showing multi-step reasoning. |

### 3. high-memory-oom-troubleshooting

| | |
|---|---|
| **Best for** | Pairs well with CPU skill to show breadth |
| **Complexity** | Medium |
| **Impact** | High — OOM kills are notoriously hard to debug manually |
| **Setup effort** | Medium — need to trigger memory pressure or have OOM kill history |
| **What makes it great** | The agent checks memory metrics, swap usage, and OOM kill logs. It can distinguish between a memory leak and genuine under-provisioning. The structured output clearly explains what happened and why. |

### 4. vm-connectivity-troubleshooting

| | |
|---|---|
| **Best for** | Multi-layer diagnosis |
| **Complexity** | Medium-High |
| **Impact** | Very high — connectivity issues are the #1 support ticket category |
| **Setup effort** | Medium — block SSH/RDP via NSG rule or stop the SSH service |
| **What makes it great** | The agent systematically checks NSGs, route tables, NIC configuration, OS-level firewall, and service status. It shows the agent working through a real troubleshooting tree, not just running one command. |

### 5. service-crash-loop-detection

| | |
|---|---|
| **Best for** | Log analysis capabilities |
| **Complexity** | Medium |
| **Impact** | High — crash loops cause outages and are tedious to debug |
| **Setup effort** | Medium — create a service that fails on startup |
| **What makes it great** | The agent reads systemd journal or Windows Event Viewer, identifies the crash pattern, counts restart attempts, and finds the root cause in the logs. It's a great showcase for in-guest diagnostic depth. |

### 6. security-incident-triage

| | |
|---|---|
| **Best for** | Security triage and compliance |
| **Complexity** | Medium |
| **Impact** | Very high — security incidents demand fast response |
| **Setup effort** | Low to medium — generate failed SSH attempts or open unexpected ports |
| **What makes it great** | The agent checks auth logs for brute-force patterns, lists active network connections, identifies rogue processes, and reviews open ports. It delivers a security-focused triage report that would take a human analyst 30+ minutes. |

### 7. vm-right-sizing

| | |
|---|---|
| **Best for** | Cost optimization |
| **Complexity** | Low |
| **Impact** | High — direct dollar savings |
| **Setup effort** | Low — works best with VMs that have been running for a few days with usage history |
| **What makes it great** | The agent analyzes CPU, memory, and disk utilization over time, compares against the current SKU, and recommends a right-sized alternative with estimated cost savings. It's a compelling ROI story. |

### 8. backup-health-verification

| | |
|---|---|
| **Best for** | Compliance and DR readiness |
| **Complexity** | Medium |
| **Impact** | High — backup failures are silent killers |
| **Setup effort** | Medium — need Azure Backup configured (even a simple policy works) |
| **What makes it great** | The agent verifies backup policy configuration, checks recent recovery points, identifies failed backup jobs, and reports on RPO compliance. It's the kind of check that should run daily but often doesn't. |

### 9. vm-extension-failure-remediation

| | |
|---|---|
| **Best for** | Automated fix capabilities |
| **Complexity** | Medium |
| **Impact** | Medium — extension failures block deployments and monitoring |
| **Setup effort** | Medium — trigger an extension failure (e.g., install an extension with bad settings) |
| **What makes it great** | The agent identifies the failed extension, reads its detailed error status, determines the fix (remove and reinstall, fix settings, etc.), and executes the remediation. Another end-to-end fix story. |

### 10. disk-iops-throttling

| | |
|---|---|
| **Best for** | Performance investigation |
| **Complexity** | Medium-High |
| **Impact** | High — throttling causes mysterious slowness that's hard to diagnose |
| **Setup effort** | Medium — need a disk-intensive workload or a small disk that throttles easily |
| **What makes it great** | The agent correlates VM-level and disk-level IOPS/throughput metrics, explains the throttling mechanics (VM cap vs. disk cap vs. burst credits), and recommends specific SKU or disk tier changes. It demonstrates deep Azure platform knowledge. |

---

## Deploying test VMs

Each skill's folder contains a `README.md` with specific setup instructions. Here's the general pattern.

### Before you start

| Parameter | Value |
|-----------|-------|
| **Subscription** | `<your-subscription-id>` |
| **Resource group** | `<your-resource-group>` |
| **Location** | `<your-azure-region>` (e.g., `eastus2`) |
| **VM name** | `<your-vm-name>` |
| **Admin username** | `<your-admin-username>` |
| **SSH key / password** | Your preferred authentication method |

### Create the resource group

```bash
az group create \
  --name <your-resource-group> \
  --location <your-azure-region>
```

### Deploy a test VM

Follow the per-skill README for specific VM configuration and fault injection:

- [disk-expansion/README.md](disk-expansion/) — VM with a nearly-full disk
- [high-cpu-vm-troubleshooting/README.md](high-cpu-vm-troubleshooting/) — VM running a CPU stress test
- [high-memory-oom-troubleshooting/README.md](high-memory-oom-troubleshooting/) — VM under memory pressure
- [vm-connectivity-troubleshooting/README.md](vm-connectivity-troubleshooting/) — VM with blocked SSH/RDP
- [service-crash-loop-detection/README.md](service-crash-loop-detection/) — VM with a crashing service
- [security-incident-triage/README.md](security-incident-triage/) — VM with simulated security events
- [vm-right-sizing/README.md](vm-right-sizing/) — Over-provisioned VM with low utilization
- [backup-health-verification/README.md](backup-health-verification/) — VM with Azure Backup configured
- [vm-extension-failure-remediation/README.md](vm-extension-failure-remediation/) — VM with a failed extension
- [disk-iops-throttling/README.md](disk-iops-throttling/) — VM with disk-intensive workload

### Cleanup

When you're done, delete the resource group to avoid ongoing costs:

```bash
az group delete \
  --name <your-resource-group> \
  --yes --no-wait
```

---

## Optional: Governance hooks

Hooks add guardrails to your agent's behavior. Try pairing them with skills to see how governance works in practice.

### Recommended hook sets

| Scenario | Hooks | Effect |
|----------|-------|--------|
| **Read-only mode** | `restrict-to-readonly` | Agent can diagnose but not change anything |
| **Safe remediation** | `allowlist-remediation` + `block-dangerous-commands` | Agent can fix things, but only approved operations |
| **Full governance** | All hooks | Complete audit trail, quality gates, and safety controls |
| **Quality enforcement** | `require-summary-section` + `enforce-structured-response` | Show how hooks enforce output quality |

### Skill-to-hook mapping

| Skill | Suggested hooks |
|-------|-----------------|
| `disk-expansion` | `allowlist-remediation`, `block-dangerous-commands` |
| `high-cpu-vm-troubleshooting` | `require-evidence-in-diagnostics`, `require-summary-section` |
| `high-memory-oom-troubleshooting` | `require-evidence-in-diagnostics`, `require-summary-section` |
| `vm-connectivity-troubleshooting` | `require-evidence-in-diagnostics`, `enforce-structured-response` |
| `service-crash-loop-detection` | `require-evidence-in-diagnostics`, `require-summary-section` |
| `security-incident-triage` | `audit-all-tool-usage`, `enforce-structured-response` |
| `vm-right-sizing` | `restrict-to-readonly`, `require-summary-section` |
| `backup-health-verification` | `restrict-to-readonly`, `require-evidence-in-diagnostics` |
| `vm-extension-failure-remediation` | `allowlist-remediation`, `block-dangerous-commands` |
| `disk-iops-throttling` | `require-evidence-in-diagnostics`, `restrict-to-readonly` |

See [`hooks/README.md`](../../hooks/README.md) for full hook documentation.

---

## Adding new VM skills

Want to add a new VM skill to this collection? Here's the quick guide:

1. **Create a folder** — `skills/vm/<your-skill-name>/`
2. **Write `SKILL.md`** — The prompt the agent will use. Follow the [key principles](../README.md#how-to-write-new-skills).
3. **Write `README.md`** — Human-facing documentation: what it does, how to set up a test VM, expected agent behavior.
4. **Test it** — Load the skill into your agent and test against a real VM.
5. **Update the tables** — Add your skill to the tables in this file and in the [root README](../../README.md).

### Skill template

Your `SKILL.md` should cover:

```markdown
# <Skill Name>

## Objective
What this skill does in one sentence.

## When to use
Trigger conditions — what kind of user question activates this skill.

## Diagnostic steps
1. Step one — exact CLI command
2. Step two — what to check in the output
3. ...

## Output format
What the agent's response should look like.

## Safety
What the agent must NOT do.
```

See **[Creating Skills and Hooks](../../docs/creating-skills-and-hooks-with-copilot.md)** for a detailed walkthrough.
