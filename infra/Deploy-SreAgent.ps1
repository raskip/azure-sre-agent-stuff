<#
.SYNOPSIS
    Deploy an Azure SRE Agent using Bicep.

.DESCRIPTION
    Checks for existing SRE Agent instances, auto-increments the instance number,
    creates the resource group if needed, and deploys via az deployment sub create.

.PARAMETER InstanceNumber
    Override the auto-detected instance number (e.g., 2 for sre-agent-002-eastus2).
    If not provided, the script finds the next available number automatically.

.PARAMETER AgentName
    Override the full agent name. If provided, InstanceNumber is ignored.

.PARAMETER Location
    Azure region. Default: eastus2.

.PARAMETER SubscriptionId
    Azure subscription ID. Required.

.PARAMETER AccessLevel
    High (Reader + Contributor) or Low (Reader only). Default: High.

.PARAMETER TargetResourceGroups
    Resource groups the agent should manage. Required.

.EXAMPLE
    .\Deploy-SreAgent.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -TargetResourceGroups @("rg-my-app-eastus2")
    # Auto-detects next instance number, deploys sre-agent-001-eastus2 (or 002, 003...)

.EXAMPLE
    .\Deploy-SreAgent.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -TargetResourceGroups @("rg-my-app-eastus2") -InstanceNumber 3
    # Deploys sre-agent-003-eastus2
#>

[CmdletBinding()]
param(
    [int]$InstanceNumber = 0,
    [string]$AgentName = "",
    [string]$Location = "eastus2",
    [string]$SubscriptionId = "",
    [ValidateSet("High", "Low")]
    [string]$AccessLevel = "High",
    [string[]]$TargetResourceGroups = @()
)

$ErrorActionPreference = "Stop"
$InfraDir = $PSScriptRoot

# --- Parameter validation ---
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    Write-Host "Error: -SubscriptionId is required" -ForegroundColor Red
    exit 1
}

if ($TargetResourceGroups.Count -eq 0) {
    Write-Host "Error: -TargetResourceGroups is required" -ForegroundColor Red
    exit 1
}

# --- Check Azure CLI login ---
Write-Host "`n=== Azure SRE Agent Deployment ===" -ForegroundColor Cyan
Write-Host "Checking Azure CLI login..." -ForegroundColor Gray
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

# --- Set subscription ---
Write-Host "Setting subscription to $SubscriptionId..." -ForegroundColor Gray
az account set --subscription $SubscriptionId

# --- Auto-detect instance number ---
if (-not $AgentName) {
    if ($InstanceNumber -eq 0) {
        Write-Host "Checking for existing SRE Agent instances..." -ForegroundColor Gray

        # List resource groups matching the naming pattern
        $existingRgs = az group list --subscription $SubscriptionId --query "[?starts_with(name, 'rg-sre-agent-') && ends_with(name, '-$Location')].name" --output json 2>$null | ConvertFrom-Json

        $maxNum = 0
        foreach ($rg in $existingRgs) {
            if ($rg -match "rg-sre-agent-(\d{3})-$Location") {
                $num = [int]$Matches[1]
                if ($num -gt $maxNum) { $maxNum = $num }
            }
        }

        $InstanceNumber = $maxNum + 1
        Write-Host "Next available instance number: $($InstanceNumber.ToString('D3'))" -ForegroundColor Green
    }

    $num = $InstanceNumber.ToString("D3")
    $AgentName = "sre-agent-$num-$Location"
}

$DeploymentRg = "rg-sre-agent-$($InstanceNumber.ToString('D3'))-$Location"

Write-Host "`nDeployment summary:" -ForegroundColor Cyan
Write-Host "  Agent name:     $AgentName"
Write-Host "  Resource group: $DeploymentRg"
Write-Host "  Location:       $Location"
Write-Host "  Access level:   $AccessLevel"
Write-Host "  Target RGs:     $($TargetResourceGroups -join ', ')"
Write-Host ""

$confirm = Read-Host "Proceed? (y/N)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# --- Create resource group if needed ---
$rgExists = az group exists --name $DeploymentRg --subscription $SubscriptionId 2>$null
if ($rgExists -eq "false") {
    Write-Host "`nCreating resource group $DeploymentRg..." -ForegroundColor Gray
    az group create --name $DeploymentRg --location $Location --subscription $SubscriptionId --output none
    Write-Host "Created." -ForegroundColor Green
} else {
    Write-Host "`nResource group $DeploymentRg already exists." -ForegroundColor Gray
}

# --- Create target resource groups if needed ---
foreach ($trg in $TargetResourceGroups) {
    $trgExists = az group exists --name $trg --subscription $SubscriptionId 2>$null
    if ($trgExists -eq "false") {
        Write-Host "Creating target resource group $trg..." -ForegroundColor Gray
        az group create --name $trg --location $Location --subscription $SubscriptionId --output none
    }
}

# --- Deploy ---
Write-Host "`nDeploying SRE Agent via Bicep..." -ForegroundColor Cyan
$targetRgsJson = ($TargetResourceGroups | ForEach-Object { "`"$_`"" }) -join ","
$targetSubsJson = ($TargetResourceGroups | ForEach-Object { "`"$SubscriptionId`"" }) -join ","

$result = az deployment sub create `
    --subscription $SubscriptionId `
    --location $Location `
    --template-file "$InfraDir\minimal-sre-agent.bicep" `
    --parameters `
        agentName=$AgentName `
        subscriptionId=$SubscriptionId `
        deploymentResourceGroupName=$DeploymentRg `
        location=$Location `
        accessLevel=$AccessLevel `
        "targetResourceGroups=[$targetRgsJson]" `
        "targetSubscriptions=[$targetSubsJson]" `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nDeployment failed:" -ForegroundColor Red
    Write-Host $result
    exit 1
}

$output = $result | ConvertFrom-Json

Write-Host "`n=== Deployment succeeded! ===" -ForegroundColor Green
Write-Host "Agent name:  $($output.properties.outputs.agentName.value)"
Write-Host "Agent ID:    $($output.properties.outputs.agentId.value)"
Write-Host "Portal URL:  $($output.properties.outputs.agentPortalUrl.value)"
Write-Host "Identity ID: $($output.properties.outputs.userAssignedIdentityId.value)"

Write-Host "`n=== Next steps (portal only) ===" -ForegroundColor Yellow
Write-Host "1. Open the portal URL above"
Write-Host "2. Choose model provider: Azure OpenAI (EUDB) or Anthropic (Claude)"
Write-Host "3. Connect GitHub repo: <your-github-org/repo>"
Write-Host "4. Add skills: Builder > Subagent builder > Create > Skill"
Write-Host "   - Paste SKILL.md from skills/<domain>/<skill-name>/SKILL.md"
Write-Host "   - Attach tools: RunAzCliReadCommands + RunAzCliWriteCommands"
Write-Host "5. Complete team onboarding conversation"
Write-Host ""
