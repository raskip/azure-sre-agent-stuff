# Scenario 13 — VM Extension Failure Remediation

> **Duration:** 5 minutes | **Skill:** `vm-extension-failure-remediation` | **Impact:** Medium — DevOps-flavoured audience

---

## Goal

Show the agent diagnosing **a failed VM extension** (CSE, AzureMonitorLinuxAgent, MDE.Linux, etc.) — read the provisioning state, pull the extension's actual error message from `extension status`, identify the cause (manifest, network, sudoers, package conflict), and remediate by reinstalling or correcting configuration.

**Why this works:** Failed extensions are the silent killer of Azure VM operations. They block Defender visibility, monitoring, patching — but the failure isn't loud. The agent surfacing extension health in 30 seconds is a story every Azure DevOps team recognises.

---

## Setup (do this 5–10 minutes before the demo)

### Step 1: Deploy

```bash
pwsh ./examples/sre-agent/scripts/Deploy-DemoVMs-Az.ps1 -Scenario ext -NoWait
```

### Step 2: Force an extension failure

```bash
./examples/sre-agent/scripts/simulate-issues.sh extension-fail
```

This deploys a deliberately-broken `CustomScript` extension (with an invalid SAS URL or a syntactically-broken inline script) — installs as `Failed` state on the VM.

### Step 3: Verify the failure exists before demo time

```bash
az vm extension list -g <ext-rg> --vm-name vm-sre-demo-ext \
  --query "[?provisioningState != 'Succeeded'].{name:name, state:provisioningState}" -o table
```

Should show at least one extension in `Failed`.

---

## Minute-by-minute script

### 0:00 — Frame (45 s)

> *"Extensions in Azure are the things that quietly stop working. CSE for bootstrap, AMA for telemetry, MDE for Defender. When one fails, the symptom is a missing feature — slower Defender visibility, missing logs, broken auto-patching — but no alert fires. Let's see if the agent can find these before the next compliance audit does."*

### 0:45 — Paste the prompt (15 s)

```
Audit the VM extensions on vm-sre-demo-ext in <ext-rg>
(subscription <your-subscription-id>). Are any of them unhealthy?
If so, diagnose and fix.
```

### 1:00–4:00 — The investigation (~3 min)

| Step | Agent action | Talking point |
|---|---|---|
| 1 | `az vm extension list -g ...` | *"Lists all extensions. One in `Failed` state — `CustomScript`"* |
| 2 | `az vm extension show -n CustomScript ...` | *"Reads the full status. Look at `instanceView.statuses[0]` — there's the actual error message the portal doesn't surface well"* |
| 3 | Classification of the failure type | **Branch: bad SAS URL** (vs Branch B: sudoers permission, Branch C: package conflict, Branch D: network egress block) |
| 4 | `az vm run-command invoke` → `sudo cat /var/log/azure/Microsoft.Azure.Extensions.CustomScript/.../handler.log | tail -50` | *"Goes inside the VM and reads the extension's handler log. This is where the *real* error lives — ARM only surfaces a summary"* |
| 5 | Cross-references: the SAS URL points to a non-existent blob → 404 | *"Found it. The SAS URL has expired or the blob was deleted. The script never downloaded"* |
| 6 | Proposes a fix | **Option A**: re-deploy the extension with a corrected `--script-uri` pointing to a valid blob with valid SAS. **Option B**: delete + redeploy the extension fresh. Each with downtime estimate (none — extensions don't restart the VM) |

### 4:00–5:00 — Approve + verify (1 min)

Approve Option B (delete + redeploy). Agent runs:

```
az vm extension delete -n CustomScript ...
az vm extension set --publisher Microsoft.Azure.Extensions --name CustomScript --settings '{"script":"echo hello"}' ...
```

Then verifies — extension goes `Succeeded`. `## Summary` heading at the end.

---

## Expected agent behaviour

| Skill loaded | `vm-extension-failure-remediation` |
| Tools used | RunAzCliReadCommands (extension list/show), RunAzCliWriteCommands (run-command, extension delete + set) |
| Cross-source correlation | ARM extension state + in-guest handler logs (where the real error is) |
| Classification | Bad SAS / sudoers / package / network — different remediation per branch |
| Remediation | Delete + recreate, or extension settings patch |
| Stop hook | Summary section enforced |

---

## Fallback prompts

```
Use the vm-extension-failure-remediation skill on vm-sre-demo-ext in <ext-rg>.
```

```
Check the health of all VM extensions on vm-sre-demo-ext.
```

---

## Talking points

- **"ARM lies (a little)."** The `provisioningState: Failed` is true but minimal. The actual error is in the handler log inside the VM. The skill knows to go look there.
- **"Audit pattern, not alert pattern."** This isn't reactive incident response — it's a hygiene check the agent can run on a schedule (`scheduled-tasks/01-daily-vm-inventory.md` is a natural pair).
- **"Same skill, multiple extensions."** It works for AzureMonitorLinuxAgent, MDE.Linux, CustomScript, DependencyAgent — anything that publishes handler logs in `/var/log/azure/`.

---

## Cleanup

```bash
# Reset the simulated failure
./examples/sre-agent/scripts/simulate-issues.sh extension-fail --stop

# Or full reset:
az group delete -n <ext-rg> --yes --no-wait
```

---

## Variants

- **Pair with scheduled tasks**: run `scheduled-tasks/01-daily-vm-inventory.md` — the agent will report this failed extension every morning until you fix it. Compounding governance value.
- **MDE.Linux Failed**: artificially fail MDE.Linux (the one we saw failing at session start) — agent identifies + re-pushes via Defender for Cloud auto-provisioning.
- **Multi-extension audit**: run on a VM with 5+ extensions to show the agent walking through each, prioritising the failed ones.
