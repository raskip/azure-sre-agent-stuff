---
name: vm-connectivity-troubleshooting
description: >
  Troubleshooting procedure for VM connectivity issues on Azure Virtual Machines.
  Covers both Linux and Windows VMs. Use when SSH or RDP connections fail,
  a VM is unreachable, connections time out, or ports appear blocked.
tools:
  - RunAzCliReadCommands
  - RunAzCliWriteCommands
---

> ⚠️ **Example skill** — designed as a starting point. Test and customize for your environment.

## When to use this skill

Use this skill when:
- SSH (port 22) or RDP (port 3389) connections to a VM fail or time out
- A VM is unreachable over the network (ping, HTTP, or custom ports)
- Connection attempts result in "connection refused", "connection timed out", or "no route to host"
- A port appears blocked despite being expected to be open
- A VM was previously accessible but is now unreachable after a change

## Overview

This skill guides you through a structured investigation:
1. Identify the VM and determine its OS (Linux or Windows)
2. Run Azure-level networking and VM health checks
3. Run OS-level diagnostics via `az vm run-command` (if VM agent is healthy)
4. Walk the decision tree to isolate the root cause
5. Produce a structured report

## Step 1: Identify the VM and its OS

Before running any commands, determine the target VM's details:

```
az vm show --resource-group {rg} --name {vm-name} --query "{os:storageProfile.osDisk.osType, size:hardwareProfile.vmSize, location:location}" -o json
```

This tells you whether to use Linux or Windows commands in the following steps.

## Step 2: Azure-level checks (using RunAzCliReadCommands)

### Check VM power state

A VM that is deallocated or stopped will not accept connections.

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv
```

If the VM is not in the `VM running` state, it must be started before connectivity is possible.

### Check VM agent health

```
az vm get-instance-view --resource-group {rg} --name {vm-name} --query "instanceView.vmAgent.statuses[0]" -o json
```

If the agent status is not "Ready", Run Command will not work. Fall back to boot diagnostics or serial console.

### Check NIC and IP configuration

List NICs attached to the VM:

```
az vm nic list --resource-group {rg} --vm-name {vm-name} -o json
```

Then get details for each NIC (IP address, subnet, NSG association):

```
az network nic show --resource-group {rg} --name {nic-name} --query "{ipConfigs:ipConfigurations[].{name:name, privateIp:privateIpAddress, publicIp:publicIpAddress.id, subnet:subnet.id}, nsg:networkSecurityGroup.id}" -o json
```

Verify the VM has the expected private/public IP and is attached to the correct subnet.

### Check effective NSG rules

```
az network nic list-effective-nsg --resource-group {rg} --name {nic-name}
```

Look for:
- **Deny rules** blocking SSH (port 22) or RDP (port 3389) inbound
- Missing allow rules for the required port
- Lower-priority allow rules being overridden by higher-priority deny rules
- NSG rules on both the NIC and the subnet level (both are evaluated)

### Check effective routes

```
az network nic show-effective-route-table --resource-group {rg} --name {nic-name}
```

Look for:
- **Black-hole routes** (nextHopType: None) that drop traffic
- Missing or incorrect default routes
- User-defined routes (UDRs) that redirect traffic through an NVA that may be down
- Unexpected route overrides from BGP or VPN gateways
- Routes pointing to a **Virtual WAN hub** or **Azure Firewall** — if present, check the firewall rules (see below)

### Check Azure Firewall rules (if traffic routes through a firewall)

If the effective route table shows traffic being routed through an Azure Firewall (either via VWAN routing intent or a UDR pointing to a firewall private IP), check whether the firewall is allowing the required traffic:

**Find the firewall in the connectivity subscription:**
```
az network firewall list --subscription {connectivity-subscription-id} --query "[].{name:name, rg:resourceGroup, policy:firewallPolicy.id}" -o json
```

**Get the firewall policy and list rule collection groups:**
```
az network firewall policy rule-collection-group list --policy-name {firewall-policy-name} --resource-group {firewall-rg} --subscription {connectivity-subscription-id} --query "[].{name:name, priority:priority}" -o json
```

**Check specific rule collection group for allow/deny rules:**
```
az network firewall policy rule-collection-group show --policy-name {firewall-policy-name} --resource-group {firewall-rg} --name {rule-collection-group-name} --subscription {connectivity-subscription-id}
```

Look for:
- **Missing allow rules** for the required port/protocol (e.g., SSH port 22, RDP port 3389)
- **Explicit deny rules** that match the traffic
- **Network rules vs application rules** — SSH/RDP are network-layer traffic, so they need network rules (not application rules)
- **Source/destination address filtering** — rules may only allow traffic from specific source ranges

> **Note:** If your environment routes outbound traffic through a hub firewall (e.g., Azure Firewall with VWAN routing intent), outbound TCP 80/443 may already be allowed by default. Inbound SSH/RDP from the internet is typically blocked — use Azure Bastion instead.

### Check boot diagnostics

```
az vm boot-diagnostics get-boot-log --resource-group {rg} --name {vm-name}
```

Look for:
- Kernel panic or crash traces
- GRUB boot failures or filesystem mount errors
- Network interface initialization failures
- Hung boot process (no login prompt)

### Check serial console log

If boot diagnostics show issues or the VM agent is unhealthy, review the serial console output for additional clues. Serial console provides direct access to the VM's serial port output and can reveal boot-time networking issues that are not captured elsewhere.

## Step 3: OS-level checks via Run Command

> **Important:** `az vm run-command invoke` is a **write operation** and requires the `RunAzCliWriteCommands` tool, not `RunAzCliReadCommands`.

Only proceed with Run Command if the VM agent is healthy (Step 2). If the agent is unhealthy, skip to the decision tree and rely on Azure-level findings.

### Linux VMs

**Check SSH service and port 22 listener:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "systemctl status sshd && ss -tlnp | grep :22"
```

**Check OS-level firewall rules:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "iptables -L -n 2>/dev/null; ufw status 2>/dev/null; firewall-cmd --list-all 2>/dev/null"
```

**Check DNS resolution:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "cat /etc/resolv.conf && nslookup google.com 2>/dev/null || host google.com"
```

**Check network interfaces and routing:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunShellScript --scripts "ip addr show && ip route show"
```

### Windows VMs

**Check RDP service and registry settings:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-Service TermService | Select-Object Status, StartType; Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections"
```

If `fDenyTSConnections` is `1`, RDP is disabled at the OS level.

**Check Windows Firewall for RDP rules:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-NetFirewallRule -Direction Inbound | Where-Object {$_.LocalPort -eq 3389 -or $_.DisplayName -match 'Remote Desktop'} | Select-Object DisplayName, Enabled, Action"
```

**Check DNS resolution:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-DnsClientServerAddress | Format-Table; Resolve-DnsName google.com"
```

**Check network configuration:**
```
az vm run-command invoke --resource-group {rg} --name {vm-name} --command-id RunPowerShellScript --scripts "Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway"
```

## Step 4: Decision tree

Work through the following causes in order. Stop at the first match:

1. **VM not running** — Power state is not `VM running`.
   → Start the VM: `az vm start --resource-group {rg} --name {vm-name}`

2. **NSG blocking traffic** — Effective NSG rules show a deny for the target port, or no allow rule exists.
   → Add or update the NSG rule to allow inbound traffic on the required port.

3. **Route issue** — Effective route table shows a black-hole route or traffic is being sent to a non-functional NVA.
   → Fix or remove the problematic UDR, or restore the NVA.

4. **Firewall blocking traffic** — Routes go through an Azure Firewall (VWAN or NVA) but the firewall policy does not allow the required port/protocol.
   → Add a network rule to the firewall policy to allow the required traffic, or use Azure Bastion to bypass the firewall for management access.

5. **Service not running inside the VM** — SSH (sshd) or RDP (TermService) is stopped or not listening on the expected port.
   → Start the service via Run Command or serial console.

5. **OS-level firewall blocking** — iptables/ufw/firewalld (Linux) or Windows Firewall is dropping traffic on the target port.
   → Add a firewall rule to allow the port, or disable the blocking rule.

6. **Boot failure** — Boot diagnostics show kernel panic, GRUB issues, or the VM failed to boot.
   → Use serial console to recover, or repair the OS disk by attaching it to a rescue VM.

7. **No public IP / wrong IP** — The VM has no public IP assigned, or the client is connecting to a stale IP.
   → Assign a public IP or update DNS/client configuration.

If none of the above match, escalate to deeper network tracing (Network Watcher packet capture, connection troubleshoot).

## Step 5: Produce structured report

After gathering evidence, produce a report in this format:

```
## VM Connectivity Investigation Report

**VM**: {vm-name}
**Resource Group**: {rg}
**OS**: {Linux/Windows}
**VM Size**: {size}
**Investigation Time**: {timestamp}

### Symptoms
- Connection type: {SSH/RDP/HTTP/custom port}
- Error observed: {timeout/refused/no route/other}
- Client source: {IP or network}

### Findings

**VM State**: {running/stopped/deallocated}
**VM Agent**: {healthy/unhealthy}
**Public IP**: {IP or none}
**NSG Rules**: {allow/deny on port {port}}
**Effective Routes**: {normal/black-hole/NVA redirect/firewall route}
**Firewall**: {not in path/allowing traffic/blocking - rule details}
**Boot Diagnostics**: {normal/errors detected}
**OS Service**: {running/stopped/not listening}
**OS Firewall**: {allowing/blocking port {port}}

### Root Cause
{Description of what is blocking connectivity and why}

### Recommendation
{One of the following, with justification:}
- **Start the VM** — VM is in a stopped/deallocated state
- **Fix NSG rule** — inbound rule for port {port} is missing or denied
- **Fix route table** — black-hole or NVA route is dropping traffic
- **Fix firewall rule** — Azure Firewall is blocking port {port}, add a network rule to allow it
- **Start the service** — {sshd/TermService} is not running inside the VM
- **Fix OS firewall** — {iptables/Windows Firewall} is blocking port {port}
- **Repair boot** — VM failed to boot, use serial console or rescue VM
- **Assign public IP** — VM has no public IP for external access
- **Escalate** — root cause not identified, recommend Network Watcher or support ticket

### Next Steps
{Specific actions the operator should take}
```

## Important notes

- **Run Command has a timeout of ~90 seconds** — if a command hangs, it will fail. The commands above are designed to complete quickly.
- **Run Command executes as root/SYSTEM** — the commands have full access but treat this as read-only investigation.
- **Serial console is your fallback** — if the VM agent is unhealthy and Run Command fails, use the Azure Serial Console to interact with the VM directly.
- **Azure Bastion is an alternative access method** — if NSG rules or network configuration prevent direct SSH/RDP, Azure Bastion provides browser-based access that bypasses public internet routing. Consider recommending Bastion if the VM has no public IP or is in a locked-down subnet.
- **Do NOT modify NSG rules or network config** unless the operator explicitly asks. This skill is diagnostic only.
