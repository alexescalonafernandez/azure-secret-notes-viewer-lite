[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Set assignDevelopmentReaderRole in the ignored parameter file:
# false for the initial deployment, then true for the final reader deployment.
$parameterFile = 'infra/environments/development.bicepparam'
$deploymentName = 'development-key-vault'

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

& az deployment sub create `
  --name $deploymentName `
  --location westeurope `
  --subscription $subscriptionId `
  --parameters $parameterFile `
  --only-show-errors `
  --output none

if ($LASTEXITCODE -ne 0) { throw 'development-key-vault-deployment-failed' }
Write-Output 'development-key-vault-deployed'
