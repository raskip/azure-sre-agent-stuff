# Deploying Azure SRE Agent with Bicep

These Bicep templates automate the deployment of an [Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/) and its supporting infrastructure. They are based on the [official microsoft/sre-agent Bicep samples](https://github.com/microsoft/sre-agent/tree/main/samples/bicep-deployment).

## What Gets Created

| Resource | Purpose |
|----------|---------|
| **SRE Agent** (`Microsoft.App/agents`) | The agent itself |
| **User-Assigned Managed Identity** | Identity the agent uses to access Azure resources |
| **Log Analytics Workspace** | Stores agent logs and diagnostics |
| **Application Insights** | Monitors agent performance and failures |
| **RBAC Role Assignments** | Reader + Contributor (High) or Reader-only (Low) on target resource groups |
| **SRE Agent Administrator** | Grants the deploying user admin access to manage the agent in the portal |

## Prerequisites

- **Azure CLI** installed and logged in (`az login`)
- **Azure subscription** with **Contributor** role (needed to create resource groups and assign roles)
- One or more **target resource groups** the agent should manage (they will be created if they don't exist)

## Quick Start (Deploy Script)

The `Deploy-SreAgent.ps1` script handles resource group creation, instance numbering, and deployment:

```powershell
# Deploy with auto-detected instance number
.\Deploy-SreAgent.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -TargetResourceGroups @("rg-my-app-eastus2") `
    -Location "eastus2" `
    -AccessLevel "High"

# Deploy a specific instance number
.\Deploy-SreAgent.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -TargetResourceGroups @("rg-my-app-eastus2", "rg-my-other-app-eastus2") `
    -InstanceNumber 3
```

The script will:
1. Check for existing agent instances and auto-increment the instance number
2. Create the deployment resource group if it doesn't exist
3. Create target resource groups if they don't exist
4. Deploy all resources via `az deployment sub create`
5. Output the portal URL and next steps

## Direct Deployment (az CLI)

If you prefer to deploy directly without the script:

```bash
az deployment sub create \
    --subscription "<your-subscription-id>" \
    --location "eastus2" \
    --template-file minimal-sre-agent.bicep \
    --parameters \
        agentName="sre-agent-001-eastus2" \
        subscriptionId="<your-subscription-id>" \
        deploymentResourceGroupName="rg-sre-agent-001-eastus2" \
        location="eastus2" \
        accessLevel="High" \
        'targetResourceGroups=["rg-my-app-eastus2"]' \
        'targetSubscriptions=["<your-subscription-id>"]'
```

Or using the parameters file:

```bash
az deployment sub create \
    --subscription "<your-subscription-id>" \
    --location "eastus2" \
    --template-file minimal-sre-agent.bicep \
    --parameters @sre-agent.parameters.json
```

## Naming Convention

Resources follow a CAF-aligned naming pattern:

```
{abbreviation}-{purpose}-{instance}-{region}
```

| Component | Example | Description |
|-----------|---------|-------------|
| Agent | `sre-agent-001-eastus2` | The SRE Agent resource |
| Resource Group | `rg-sre-agent-001-eastus2` | Contains the agent and its supporting resources |
| Identity | `sre-agent-001-eastus2-{uniqueSuffix}` | Managed identity (suffix ensures global uniqueness) |
| Log Analytics | `workspace{uniqueSuffix}` | Log Analytics workspace |
| App Insights | `app-insights-{uniqueSuffix}` | Application Insights component |

The deploy script auto-increments the instance number (001, 002, 003...) based on existing deployments.

## Access Levels

| Level | Roles Assigned to Target RGs | Use Case |
|-------|------------------------------|----------|
| **High** | Reader + Contributor + Log Analytics Reader | Agent can read and modify resources (recommended for full SRE workflows) |
| **Low** | Reader + Log Analytics Reader | Agent can only read resources (suitable for monitoring and diagnostics only) |

Both levels also assign Log Analytics Reader, Application Insights Component Contributor, and Key Vault roles on the deployment resource group.

## Post-Deployment Steps

These steps must be completed in the Azure portal — they are not automatable via Bicep:

1. **Open the agent portal URL** (printed after deployment)
2. **Choose a model provider** — Azure OpenAI (EUDB-compliant) or Anthropic (Claude)
3. **Connect your GitHub repository** — the repo containing your skills and hooks
4. **Add skills** — Agent Canvas > Custom agents > Create > Skill
   - Paste the contents of each `SKILL.md` file
   - Attach tools: `RunAzCliReadCommands` and/or `RunAzCliWriteCommands`
5. **Add hooks** (optional) — paste hook definitions for governance guardrails
6. **Complete team onboarding** — run the onboarding conversation to teach the agent about your environment

## Adding Access to More Resource Groups

After deployment, you can grant the agent access to additional resource groups:

```bash
# Get the managed identity principal ID from deployment outputs
IDENTITY_PRINCIPAL_ID="<principal-id-from-deployment>"

# Assign Reader role
az role assignment create \
    --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Reader" \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"

# Assign Contributor role (for High access level)
az role assignment create \
    --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"
```

Alternatively, re-run the deployment with the additional resource groups included in the `targetResourceGroups` parameter.
