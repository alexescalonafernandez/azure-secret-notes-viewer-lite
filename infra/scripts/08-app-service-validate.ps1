[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$parameterFile = 'infra/environments/development.bicepparam'

function ConvertFrom-SanitizedJson {
    param([Parameter(Mandatory)][string] $Json)

    try {
        return $Json | ConvertFrom-Json -DateKind String
    }
    catch {
        throw 'azure-response-invalid'
    }
}

function Invoke-AzureJson {
    param([Parameter(Mandatory)][scriptblock] $Command)

    $lines = @(& $Command 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'azure-read-failed' }
    return ConvertFrom-SanitizedJson -Json ($lines -join [Environment]::NewLine)
}

function Get-CompiledParameterValue {
    param(
        [Parameter(Mandatory)][psobject] $Document,
        [Parameter(Mandatory)][string] $Name
    )

    $parameter = $Document.parameters.PSObject.Properties[$Name]
    if ($null -eq $parameter -or $null -eq $parameter.Value.PSObject.Properties['value']) {
        throw 'hosting-parameters-invalid'
    }
    return $parameter.Value.value
}

if (-not (Test-Path -LiteralPath $parameterFile)) { throw 'local-parameter-file-missing' }
if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) { throw 'azure-cli-unavailable' }

$parameterLines = @(& az bicep build-params --file $parameterFile --stdout 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'bicepparam-build-failed' }
$parameters = ConvertFrom-SanitizedJson -Json ($parameterLines -join [Environment]::NewLine)

$resourceGroupName = [string](Get-CompiledParameterValue -Document $parameters -Name 'resourceGroupName')
$keyVaultName = [string](Get-CompiledParameterValue -Document $parameters -Name 'keyVaultName')
$appServicePlanName = [string](Get-CompiledParameterValue -Document $parameters -Name 'appServicePlanName')
$webAppName = [string](Get-CompiledParameterValue -Document $parameters -Name 'webAppName')
$hostingGate = Get-CompiledParameterValue -Document $parameters -Name 'provisionAppServiceHosting'
if ($hostingGate -ne $true) { throw 'hosting-gate-disabled' }

$subscriptionId = (& az account show --query id --output tsv --only-show-errors 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'subscription-context-invalid'
}
$subscriptionId = $subscriptionId.Trim()

$plan = Invoke-AzureJson {
    & az appservice plan show `
        --resource-group $resourceGroupName `
        --name $appServicePlanName `
        --subscription $subscriptionId `
        --query '{id:id,kind:kind,reserved:reserved,skuName:sku.name,skuTier:sku.tier}' `
        --output json `
        --only-show-errors
}
if (
    [string]::IsNullOrWhiteSpace([string] $plan.id) -or
    $plan.kind -notmatch '(?i)linux' -or
    $plan.reserved -ne $true -or
    $plan.skuName -cne 'F1' -or
    $plan.skuTier -cne 'Free'
) { throw 'app-service-plan-invalid' }
Write-Output 'app-service-plan-valid'

$webApp = Invoke-AzureJson {
    & az webapp show `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '{id:id,kind:kind,serverFarmId:serverFarmId,httpsOnly:httpsOnly,identityType:identity.type,principalId:identity.principalId,keyVaultReferenceIdentity:keyVaultReferenceIdentity}' `
        --output json `
        --only-show-errors
}
if (
    [string]::IsNullOrWhiteSpace([string] $webApp.id) -or
    $webApp.kind -notmatch '(?i)(^|,)linux($|,)' -or
    -not [string]::Equals([string] $webApp.serverFarmId, [string] $plan.id, [StringComparison]::OrdinalIgnoreCase)
) { throw 'linux-web-app-invalid' }
Write-Output 'linux-web-app-valid'

$siteConfig = Invoke-AzureJson {
    & az webapp config show `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '{linuxFxVersion:linuxFxVersion,minTlsVersion:minTlsVersion,scmMinTlsVersion:scmMinTlsVersion,ftpsState:ftpsState}' `
        --output json `
        --only-show-errors
}
if ($siteConfig.linuxFxVersion -cne 'DOTNETCORE|10.0') { throw 'dotnet-runtime-invalid' }
Write-Output 'dotnet-runtime-valid'

if ($webApp.httpsOnly -ne $true) { throw 'https-only-invalid' }
Write-Output 'https-only-valid'

if ($siteConfig.minTlsVersion -cne '1.2') { throw 'minimum-tls-invalid' }
Write-Output 'minimum-tls-valid'

if ($siteConfig.scmMinTlsVersion -cne '1.2') { throw 'scm-minimum-tls-invalid' }
Write-Output 'scm-minimum-tls-valid'

if ($siteConfig.ftpsState -cne 'Disabled') { throw 'ftp-state-invalid' }
Write-Output 'ftp-disabled'

$scmPolicyId = '{0}/basicPublishingCredentialsPolicies/scm' -f ([string] $webApp.id).TrimEnd('/')
$ftpPolicyId = '{0}/basicPublishingCredentialsPolicies/ftp' -f ([string] $webApp.id).TrimEnd('/')
$scmPolicy = Invoke-AzureJson {
    & az resource show --ids $scmPolicyId --api-version 2025-03-01 --subscription $subscriptionId --query '{allow:properties.allow}' --output json --only-show-errors
}
$ftpPolicy = Invoke-AzureJson {
    & az resource show --ids $ftpPolicyId --api-version 2025-03-01 --subscription $subscriptionId --query '{allow:properties.allow}' --output json --only-show-errors
}
if ($scmPolicy.allow -ne $false -or $ftpPolicy.allow -ne $false) {
    throw 'publishing-credentials-enabled'
}
Write-Output 'publishing-credentials-disabled'

if (
    $webApp.identityType -cne 'SystemAssigned' -or
    [string]::IsNullOrWhiteSpace([string] $webApp.principalId)
) { throw 'system-assigned-identity-invalid' }
Write-Output 'system-assigned-identity-valid'

$vault = Invoke-AzureJson {
    & az keyvault show --resource-group $resourceGroupName --name $keyVaultName --subscription $subscriptionId --query '{id:id}' --output json --only-show-errors
}
$vaultAssignments = Invoke-AzureJson {
    & az role assignment list `
        --scope $vault.id `
        --assignee-object-id $webApp.principalId `
        --fill-principal-name false `
        --fill-role-definition-name false `
        --subscription $subscriptionId `
        --query '[].{scope:scope}' `
        --output json `
        --only-show-errors
}
$directVaultAssignments = @($vaultAssignments | Where-Object {
    [string]::Equals([string] $_.scope, [string] $vault.id, [StringComparison]::OrdinalIgnoreCase)
})
if ($directVaultAssignments.Count -ne 0) { throw 'key-vault-rbac-present' }
Write-Output 'key-vault-rbac-absent'

$appSettings = Invoke-AzureJson {
    & az webapp config appsettings list --resource-group $resourceGroupName --name $webAppName --subscription $subscriptionId --query '[].{name:name,value:value}' --output json --only-show-errors
}
$connectionStrings = Invoke-AzureJson {
    & az webapp config connection-string list --resource-group $resourceGroupName --name $webAppName --subscription $subscriptionId --query '[].{name:name,type:type}' --output json --only-show-errors
}
if (
    @($appSettings).Count -ne 0 -or
    @($connectionStrings).Count -ne 0 -or
    -not [string]::IsNullOrWhiteSpace([string] $webApp.keyVaultReferenceIdentity)
) { throw 'private-settings-present' }
Write-Output 'private-settings-absent'

$deploymentArtifacts = Invoke-AzureJson {
    & az resource list `
        --resource-group $resourceGroupName `
        --subscription $subscriptionId `
        --query "[?starts_with(id, '$($webApp.id)/') && (type == 'Microsoft.Web/sites/deployments' || type == 'Microsoft.Web/sites/sourcecontrols' || type == 'Microsoft.Web/sites/siteextensions')].{type:type}" `
        --output json `
        --only-show-errors
}
if (@($deploymentArtifacts).Count -ne 0) { throw 'application-package-present' }
Write-Output 'application-package-absent'

$telemetryResources = Invoke-AzureJson {
    & az resource list `
        --resource-group $resourceGroupName `
        --subscription $subscriptionId `
        --query "[?type == 'Microsoft.Insights/components' || type == 'Microsoft.OperationalInsights/workspaces'].{type:type}" `
        --output json `
        --only-show-errors
}
if (@($telemetryResources).Count -ne 0) { throw 'telemetry-resources-present' }
Write-Output 'telemetry-resources-absent'

Write-Output 'app-service-validation-valid'
