[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$parameterFile = 'infra/environments/development.bicepparam'

function ConvertFrom-SanitizedJson {
    param(
        [Parameter(Mandatory)][string] $Json,
        [Parameter(Mandatory)][string] $FailureReason
    )

    try {
        return $Json | ConvertFrom-Json -DateKind String
    }
    catch {
        throw $FailureReason
    }
}

function Invoke-AzureJson {
    param([Parameter(Mandatory)][scriptblock] $Command)

    $lines = @(& $Command 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'azure-read-failed' }
    return ConvertFrom-SanitizedJson `
        -Json ($lines -join [Environment]::NewLine) `
        -FailureReason 'azure-response-invalid'
}

function Get-CompiledParameterValue {
    param(
        [Parameter(Mandatory)][psobject] $Document,
        [Parameter(Mandatory)][string] $Name
    )

    $parametersProperty = $Document.PSObject.Properties['parameters']
    if ($null -eq $parametersProperty -or $null -eq $parametersProperty.Value) {
        throw 'compiled-parameters-invalid'
    }

    $parameter = $parametersProperty.Value.PSObject.Properties[$Name]
    if ($null -eq $parameter -or $null -eq $parameter.Value) {
        throw 'hosting-parameters-invalid'
    }

    $valueProperty = $parameter.Value.PSObject.Properties['value']
    if ($null -eq $valueProperty) {
        throw 'hosting-parameters-invalid'
    }
    return $valueProperty.Value
}

if (-not (Test-Path -LiteralPath $parameterFile)) { throw 'local-parameter-file-missing' }
if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) { throw 'azure-cli-unavailable' }

$buildParamsEnvelopeLines = @(& az bicep build-params --file $parameterFile --stdout 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'bicepparam-build-failed' }
$buildParamsEnvelope = ConvertFrom-SanitizedJson `
    -Json ($buildParamsEnvelopeLines -join [Environment]::NewLine) `
    -FailureReason 'bicepparam-envelope-invalid'
if ($null -eq $buildParamsEnvelope) { throw 'bicepparam-envelope-invalid' }

$parametersJsonProperty = $buildParamsEnvelope.PSObject.Properties['parametersJson']
$templateJsonProperty = $buildParamsEnvelope.PSObject.Properties['templateJson']
if (
    $null -eq $parametersJsonProperty -or
    [string]::IsNullOrWhiteSpace([string] $parametersJsonProperty.Value) -or
    $null -eq $templateJsonProperty -or
    [string]::IsNullOrWhiteSpace([string] $templateJsonProperty.Value)
) { throw 'bicepparam-envelope-invalid' }

$compiledParametersDocument = ConvertFrom-SanitizedJson `
    -Json ([string] $parametersJsonProperty.Value) `
    -FailureReason 'compiled-parameters-json-invalid'
$compiledTemplateDocument = ConvertFrom-SanitizedJson `
    -Json ([string] $templateJsonProperty.Value) `
    -FailureReason 'compiled-template-json-invalid'

if ($null -eq $compiledParametersDocument) { throw 'compiled-parameters-invalid' }
$compiledParametersRoot = $compiledParametersDocument.PSObject.Properties['parameters']
if ($null -eq $compiledParametersRoot -or $null -eq $compiledParametersRoot.Value) {
    throw 'compiled-parameters-invalid'
}
if ($null -eq $compiledTemplateDocument) { throw 'compiled-template-invalid' }
$compiledTemplateRoot = $compiledTemplateDocument.PSObject.Properties['parameters']
if ($null -eq $compiledTemplateRoot -or $null -eq $compiledTemplateRoot.Value) {
    throw 'compiled-template-invalid'
}

$resourceGroupName = [string](Get-CompiledParameterValue `
    -Document $compiledParametersDocument `
    -Name 'resourceGroupName')
$keyVaultName = [string](Get-CompiledParameterValue `
    -Document $compiledParametersDocument `
    -Name 'keyVaultName')
$appServicePlanName = [string](Get-CompiledParameterValue `
    -Document $compiledParametersDocument `
    -Name 'appServicePlanName')
$webAppName = [string](Get-CompiledParameterValue `
    -Document $compiledParametersDocument `
    -Name 'webAppName')
$hostingGate = Get-CompiledParameterValue `
    -Document $compiledParametersDocument `
    -Name 'provisionAppServiceHosting'
if ($hostingGate -ne $true) { throw 'hosting-gate-disabled' }

$subscriptionIdLines = @(& az account show --query id --output json --only-show-errors 2>$null)
if (
    $LASTEXITCODE -ne 0 -or
    [string]::IsNullOrWhiteSpace(
        $subscriptionIdLines -join [Environment]::NewLine
    )
) {
    throw 'subscription-context-invalid'
}
$subscriptionId = ConvertFrom-SanitizedJson `
    -Json ($subscriptionIdLines -join [Environment]::NewLine) `
    -FailureReason 'subscription-context-invalid'
if ([string]::IsNullOrWhiteSpace([string] $subscriptionId)) {
    throw 'subscription-context-invalid'
}
$subscriptionId = ([string] $subscriptionId).Trim()

$plan = Invoke-AzureJson {
    & az appservice plan show `
        --resource-group $resourceGroupName `
        --name $appServicePlanName `
        --subscription $subscriptionId `
        --query '{id:id,kind:kind,skuName:sku.name,skuTier:sku.tier}' `
        --output json `
        --only-show-errors
}
if (
    [string]::IsNullOrWhiteSpace([string] $plan.id) -or
    $plan.kind -notmatch '(?i)linux' -or
    $plan.skuName -cne 'F1' -or
    $plan.skuTier -cne 'Free'
) { throw 'app-service-plan-invalid' }

$planArmState = Invoke-AzureJson {
    & az resource show `
        --ids $plan.id `
        --api-version 2025-03-01 `
        --subscription $subscriptionId `
        --query '{type:type,reserved:properties.reserved}' `
        --output json `
        --only-show-errors
}
if ($null -eq $planArmState) {
    throw 'app-service-plan-linux-reservation-invalid'
}
$planTypeProperty = $planArmState.PSObject.Properties['type']
$planReservedProperty = $planArmState.PSObject.Properties['reserved']
if (
    $null -eq $planTypeProperty -or
    $null -eq $planReservedProperty -or
    -not [string]::Equals(
        [string] $planTypeProperty.Value,
        'Microsoft.Web/serverfarms',
        [StringComparison]::OrdinalIgnoreCase
    ) -or
    $planReservedProperty.Value -isnot [bool] -or
    $planReservedProperty.Value -ne $true
) { throw 'app-service-plan-linux-reservation-invalid' }
Write-Output 'app-service-plan-valid'

$webApp = Invoke-AzureJson {
    & az webapp show `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '{id:id,kind:kind,httpsOnly:httpsOnly,identityType:identity.type,principalId:identity.principalId}' `
        --output json `
        --only-show-errors
}
if (
    [string]::IsNullOrWhiteSpace([string] $webApp.id) -or
    $webApp.kind -notmatch '(?i)(^|,)app($|,)' -or
    $webApp.kind -notmatch '(?i)(^|,)linux($|,)'
) { throw 'linux-web-app-invalid' }

$webAppArmState = Invoke-AzureJson {
    & az resource show `
        --ids $webApp.id `
        --api-version 2025-03-01 `
        --subscription $subscriptionId `
        --query '{type:type,serverFarmId:properties.serverFarmId,publicNetworkAccess:properties.publicNetworkAccess,clientAffinityEnabled:properties.clientAffinityEnabled,keyVaultReferenceIdentity:properties.keyVaultReferenceIdentity}' `
        --output json `
        --only-show-errors
}
if ($null -eq $webAppArmState) { throw 'web-app-arm-state-invalid' }

$webAppTypeProperty = $webAppArmState.PSObject.Properties['type']
$serverFarmIdProperty = $webAppArmState.PSObject.Properties['serverFarmId']
$publicNetworkAccessProperty = $webAppArmState.PSObject.Properties['publicNetworkAccess']
$clientAffinityProperty = $webAppArmState.PSObject.Properties['clientAffinityEnabled']
$keyVaultReferenceIdentityProperty = $webAppArmState.PSObject.Properties['keyVaultReferenceIdentity']
if (
    $null -eq $webAppTypeProperty -or
    $null -eq $serverFarmIdProperty -or
    $null -eq $publicNetworkAccessProperty -or
    $null -eq $clientAffinityProperty -or
    $null -eq $keyVaultReferenceIdentityProperty -or
    $webAppTypeProperty.Value -isnot [string] -or
    -not [string]::Equals(
        [string] $webAppTypeProperty.Value,
        'Microsoft.Web/sites',
        [StringComparison]::OrdinalIgnoreCase
    )
) { throw 'web-app-arm-state-invalid' }

$serverFarmId = [string] $serverFarmIdProperty.Value
if (
    [string]::IsNullOrWhiteSpace($serverFarmId) -or
    -not [string]::Equals(
        $serverFarmId,
        [string] $plan.id,
        [StringComparison]::OrdinalIgnoreCase
    )
) { throw 'web-app-plan-association-invalid' }

if (
    $publicNetworkAccessProperty.Value -isnot [string] -or
    -not [string]::Equals(
        [string] $publicNetworkAccessProperty.Value,
        'Enabled',
        [StringComparison]::Ordinal
    )
) { throw 'public-network-access-invalid' }

if (
    $clientAffinityProperty.Value -isnot [bool] -or
    $clientAffinityProperty.Value -ne $false
) { throw 'client-affinity-invalid' }

$keyVaultReferenceIdentity = [string] $keyVaultReferenceIdentityProperty.Value
if (
    -not [string]::IsNullOrWhiteSpace($keyVaultReferenceIdentity) -and
    -not [string]::Equals(
        $keyVaultReferenceIdentity,
        'SystemAssigned',
        [StringComparison]::Ordinal
    )
) { throw 'unexpected-key-vault-reference-identity' }

Write-Output 'linux-web-app-valid'
Write-Output 'public-network-access-valid'
Write-Output 'client-affinity-disabled'

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

if ($webApp.httpsOnly -isnot [bool] -or $webApp.httpsOnly -ne $true) {
    throw 'https-only-invalid'
}
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

$appSettingNames = Invoke-AzureJson {
    & az webapp config appsettings list `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '[].name' `
        --output json `
        --only-show-errors
}
$appSettingsCount = @(
    $appSettingNames | Where-Object { $null -ne $_ }
).Count

$connectionStringNames = Invoke-AzureJson {
    & az webapp config connection-string list `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '[].name' `
        --output json `
        --only-show-errors
}
$connectionStringCount = @(
    $connectionStringNames | Where-Object { $null -ne $_ }
).Count
if (
    $appSettingsCount -ne 0 -or
    $connectionStringCount -ne 0
) { throw 'private-settings-present' }
Write-Output 'private-settings-absent'

$resourceSummaries = Invoke-AzureJson {
    & az resource list `
        --resource-group $resourceGroupName `
        --subscription $subscriptionId `
        --query '[].{id:id,type:type}' `
        --output json `
        --only-show-errors
}

$webAppChildPrefix = '{0}/' -f ([string] $webApp.id).TrimEnd('/')
$deploymentArtifacts = @(
    $resourceSummaries |
        Where-Object {
            $resourceId = [string] $_.id
            $resourceType = [string] $_.type
            $isDeploymentArtifactType =
                [string]::Equals(
                    $resourceType,
                    'Microsoft.Web/sites/deployments',
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                [string]::Equals(
                    $resourceType,
                    'Microsoft.Web/sites/sourcecontrols',
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                [string]::Equals(
                    $resourceType,
                    'Microsoft.Web/sites/siteextensions',
                    [StringComparison]::OrdinalIgnoreCase
                )

            $isDeploymentArtifactType -and
                -not [string]::IsNullOrWhiteSpace($resourceId) -and
                $resourceId.StartsWith(
                    $webAppChildPrefix,
                    [StringComparison]::OrdinalIgnoreCase
                )
        }
)
$deploymentArtifactCount = $deploymentArtifacts.Count

$deploymentRecords = Invoke-AzureJson {
    & az webapp log deployment list `
        --resource-group $resourceGroupName `
        --name $webAppName `
        --subscription $subscriptionId `
        --query '[].{id:id}' `
        --output json `
        --only-show-errors
}
$deploymentRecordCount = @(
    $deploymentRecords | Where-Object { $null -ne $_ }
).Count
if (
    $deploymentRecordCount -ne 0 -or
    $deploymentArtifactCount -ne 0 -or
    $appSettingsCount -ne 0 -or
    $connectionStringCount -ne 0
) { throw 'application-package-present' }
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
