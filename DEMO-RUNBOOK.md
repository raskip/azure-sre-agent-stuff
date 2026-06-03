# DEMO-RUNBOOK

This sample runbook is for a fictional infrastructure team operating shared application VMs in Azure. Use it as a neutral knowledge document for walkthroughs, uploads, and citation demos.

## Naming conventions

Production virtual machines use the pattern `vm-<workload>-<instance>` such as `vm-app-001` and `vm-api-002`. Shared resource groups follow `rg-<environment>` such as `rg-prod` or `rg-dr`. Disks, NICs, and alerts should reuse the same workload token so operators can correlate assets quickly during an incident.

## On-call escalation

Primary on-call handles the first 15 minutes of triage. If customer impact is confirmed or a Sev2 incident is declared, page the secondary engineer and notify the platform lead. Escalate to the infrastructure manager if restoration is expected to exceed 30 minutes. Every incident update should capture the affected VM name, current mitigation, and next checkpoint time.

## Common failure patterns

The most common issues are CPU spikes caused by runaway background jobs, disk saturation on data volumes, and SSH access failures caused by NSG drift. Treat repeated restarts as a symptom, not a fix. Check recent changes, backup health, and the last successful maintenance activity before making configuration changes.

## Safe restart procedure

Before restarting a workload, confirm whether the VM is part of an active maintenance window. Validate recent backup status, note the current health indicators, and inform the incident channel. Restart only the affected service first. Reboot the full VM only if the service restart fails or the OS is unresponsive. After recovery, verify application health checks, confirm monitoring has stabilized, and record the suspected root cause plus follow-up actions.
