[CmdletBinding()]
param(
    [switch] $ApproveDeployment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$parameterFile = 'infra/environments/development.bicepparam'
$deploymentName = 'b4-d9-app-service-hosting'
$preflightScript = Join-Path $PSScriptRoot '06-app-service-preflight.ps1'

function ConvertFrom-SanitizedJson {
    param([Parameter(Mandatory)][string] $Json)

    try {
        return $Json | ConvertFrom-Json -DateKind String
    }
    catch {
        throw 'azure-response-invalid'
    }
}

function Get-WhatIfResourceType {
    param([Parameter(Mandatory)][psobject] $Change)

    foreach ($propertyName in @('after', 'before', 'delta')) {
        $property = $Change.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        $candidate = $property.Value
        if ($null -ne $candidate -and $null -ne $candidate.PSObject.Properties['type']) {
            $typeValue = [string] $candidate.type
            if (-not [string]::IsNullOrWhiteSpace($typeValue)) { return $typeValue }
        }
    }

    return ''
}

& $preflightScript
if ($LASTEXITCODE -ne 0) { throw 'app-service-preflight-failed' }

$subscriptionId = (& az account show --query id --output tsv --only-show-errors 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'subscription-context-invalid'
}
$subscriptionId = $subscriptionId.Trim()

$null = & az deployment sub validate `
    --name $deploymentName `
    --location westeurope `
    --subscription $subscriptionId `
    --parameters $parameterFile `
    --only-show-errors `
    --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw 'subscription-deployment-validate-failed' }
Write-Output 'subscription-deployment-validate-valid'

$whatIfLines = @(
    & az deployment sub what-if `
        --name $deploymentName `
        --location westeurope `
        --subscription $subscriptionId `
        --parameters $parameterFile `
        --result-format FullResourcePayloads `
        --no-pretty-print `
        --only-show-errors `
        --output json 2>$null
)
if ($LASTEXITCODE -ne 0) { throw 'app-service-what-if-failed' }
$whatIf = ConvertFrom-SanitizedJson -Json ($whatIfLines -join [Environment]::NewLine)

$allowedHostingTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$null = $allowedHostingTypes.Add('Microsoft.Web/serverfarms')
$null = $allowedHostingTypes.Add('Microsoft.Web/sites')
$null = $allowedHostingTypes.Add('Microsoft.Web/sites/basicPublishingCredentialsPolicies')

$expectedNoChangeTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$null = $expectedNoChangeTypes.Add('Microsoft.Resources/resourceGroups')
$null = $expectedNoChangeTypes.Add('Microsoft.KeyVault/vaults')
$null = $expectedNoChangeTypes.Add('Microsoft.Authorization/roleAssignments')
$null = $expectedNoChangeTypes.Add('Microsoft.Resources/deployments')

$changedHostingTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($change in @($whatIf.changes)) {
    $changeType = [string] $change.changeType
    $resourceType = Get-WhatIfResourceType -Change $change

    if ($changeType -ieq 'Delete') { throw 'destructive-change-detected' }
    if ($changeType -iin @('NoChange', 'Ignore')) { continue }
    if (
        $changeType -ieq 'Deploy' -and
        $resourceType -ieq 'Microsoft.Resources/deployments'
    ) { continue }
    if ([string]::IsNullOrWhiteSpace($resourceType)) { throw 'what-if-resource-type-missing' }
    if (-not $allowedHostingTypes.Contains($resourceType)) {
        if ($expectedNoChangeTypes.Contains($resourceType)) { throw 'existing-resource-change-detected' }
        throw 'unexpected-resource-type-detected'
    }

    $null = $changedHostingTypes.Add($resourceType)
}

foreach ($resourceType in @($changedHostingTypes | Sort-Object)) {
    Write-Output ('what-if-category:{0}' -f $resourceType)
}
Write-Output 'what-if-scope-valid'

if (-not $ApproveDeployment) {
    Write-Output 'deployment-approval-required'
    return
}

$null = & az deployment sub create `
    --name $deploymentName `
    --location westeurope `
    --subscription $subscriptionId `
    --parameters $parameterFile `
    --only-show-errors `
    --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw 'app-service-deployment-failed' }
Write-Output 'app-service-deployment-valid'
