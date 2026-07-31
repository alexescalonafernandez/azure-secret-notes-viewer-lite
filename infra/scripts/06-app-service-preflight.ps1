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
        throw 'local-build-output-invalid'
    }
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

$null = & az version --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw 'azure-cli-unavailable' }

$null = & az bicep version 2>$null
if ($LASTEXITCODE -ne 0) { throw 'bicep-cli-unavailable' }

$subscriptionId = (& az account show --query id --output tsv --only-show-errors 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
    throw 'subscription-context-invalid'
}
$subscriptionId = $subscriptionId.Trim()
Write-Output 'subscription-context-valid'

$signedInUserObjectId = (& az ad signed-in-user show --query id --output tsv --only-show-errors 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($signedInUserObjectId)) {
    throw 'development-user-unavailable'
}
Write-Output 'identity-context-valid'

$mainTemplateLines = @(& az bicep build --file infra/main.bicep --stdout 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'bicep-build-failed' }
$mainTemplate = ConvertFrom-SanitizedJson -Json ($mainTemplateLines -join [Environment]::NewLine)
Write-Output 'bicep-build-valid'

$parameterDocumentLines = @(& az bicep build-params --file $parameterFile --stdout 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'bicepparam-build-failed' }
$parameterDocument = ConvertFrom-SanitizedJson -Json ($parameterDocumentLines -join [Environment]::NewLine)
Write-Output 'bicepparam-build-valid'

$locationDefinition = $mainTemplate.parameters.PSObject.Properties['location']
if (
    $null -eq $locationDefinition -or
    $locationDefinition.Value.defaultValue -cne 'westeurope' -or
    @($locationDefinition.Value.allowedValues).Count -ne 1 -or
    $locationDefinition.Value.allowedValues[0] -cne 'westeurope'
) { throw 'hosting-location-invalid' }

$hostingGate = Get-CompiledParameterValue -Document $parameterDocument -Name 'provisionAppServiceHosting'
if ($hostingGate -ne $true) { throw 'hosting-gate-disabled' }
Write-Output 'hosting-gate-valid'

$appServicePlanName = [string](Get-CompiledParameterValue -Document $parameterDocument -Name 'appServicePlanName')
$webAppName = [string](Get-CompiledParameterValue -Document $parameterDocument -Name 'webAppName')
if (
    $appServicePlanName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}[A-Za-z0-9]$' -or
    $webAppName -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,58}[A-Za-z0-9])$'
) { throw 'hosting-parameters-invalid' }
Write-Output 'hosting-parameters-valid'

$planTemplateLines = @(& az bicep build --file infra/modules/app-service-plan.bicep --stdout 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'app-service-plan-build-failed' }
$planTemplate = ConvertFrom-SanitizedJson -Json ($planTemplateLines -join [Environment]::NewLine)
$planResource = @($planTemplate.resources)[0]
if (
    $planResource.type -cne 'Microsoft.Web/serverfarms' -or
    $planResource.kind -cne 'linux' -or
    $planResource.sku.name -cne 'F1' -or
    $planResource.sku.tier -cne 'Free' -or
    [int] $planResource.sku.capacity -ne 1 -or
    $planResource.properties.reserved -ne $true
) { throw 'f1-sku-invalid' }
Write-Output 'f1-sku-valid'

Write-Output 'app-service-preflight-valid'
