[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$parameterFile = 'infra/environments/development.bicepparam'

if (-not (Test-Path -LiteralPath $parameterFile)) { throw 'local-parameter-file-missing' }
if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) { throw 'azure-cli-unavailable' }

$null = & az version --output none 2>$null
if ($LASTEXITCODE -ne 0) { throw 'azure-cli-unavailable' }

$null = & az bicep version 2>$null
if ($LASTEXITCODE -ne 0) { throw 'bicep-cli-unavailable' }

$subscriptionId = (
  & az account show `
    --query id `
    --output tsv `
    --only-show-errors 2>$null
)
if (
  $LASTEXITCODE -ne 0 -or
  [string]::IsNullOrWhiteSpace($subscriptionId)
) { throw 'subscription-context-invalid' }
$subscriptionId = $subscriptionId.Trim()
Write-Output 'subscription-context-valid'

$developmentReaderPrincipalId = (
  & az ad signed-in-user show `
    --query id `
    --output tsv `
    --only-show-errors 2>$null
)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($developmentReaderPrincipalId)) {
  throw 'development-user-unavailable'
}
Write-Output 'identity-context-valid'

$null = & az bicep build --file infra/main.bicep --stdout 2>$null
if ($LASTEXITCODE -ne 0) { throw 'bicep-build-failed' }
Write-Output 'bicep-build-valid'

Write-Output 'preflight-valid'
