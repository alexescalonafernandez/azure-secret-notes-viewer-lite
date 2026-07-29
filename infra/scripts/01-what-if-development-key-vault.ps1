[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Review the sanitized change types and resource types before deploying.
$parameterFile = 'infra/environments/development.bicepparam'
$deploymentName = 'development-key-vault-review'

if (-not (Test-Path -LiteralPath $parameterFile)) { throw 'local-parameter-file-missing' }
if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) { throw 'azure-cli-unavailable' }

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

& az deployment sub what-if `
  --name $deploymentName `
  --location westeurope `
  --subscription $subscriptionId `
  --parameters $parameterFile `
  --only-show-errors `
  --query "changes[].{changeType:changeType, resourceType:after.type}" `
  --output table

if ($LASTEXITCODE -ne 0) { throw 'development-key-vault-what-if-failed' }
