[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $VaultName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

try {
    $subscriptionId = $env:AZURE_SUBSCRIPTION_ID
    if (
        [string]::IsNullOrWhiteSpace($VaultName) -or
        [string]::IsNullOrWhiteSpace($subscriptionId)
    ) {
        exit 1
    }

    $verifiedSubscriptionId = @(
        & az account show `
            --subscription $subscriptionId `
            --query id `
            --output tsv `
            --only-show-errors 2>$null
    )
    if (
        $LASTEXITCODE -ne 0 -or
        $verifiedSubscriptionId.Count -ne 1 -or
        -not [string]::Equals(
            $verifiedSubscriptionId[0].Trim(),
            $subscriptionId.Trim(),
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        exit 1
    }

    $developmentReaderPrincipalId = @(
        & az ad signed-in-user show `
            --subscription $subscriptionId `
            --query id `
            --output tsv `
            --only-show-errors 2>$null
    )
    if (
        $LASTEXITCODE -ne 0 -or
        $developmentReaderPrincipalId.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace($developmentReaderPrincipalId[0])
    ) {
        exit 1
    }

    $captured = @(
        & az keyvault secret list `
            --vault-name $VaultName `
            --maxresults 1 `
            --subscription $subscriptionId `
            --only-show-errors `
            --output none 2>&1
    )
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        exit 1
    }

    $sanitizedInspection = ($captured | ForEach-Object { $_.ToString() }) -join ' '
    if ($sanitizedInspection -notmatch '(?i)(403|forbidden|accessdenied)') {
        exit 1
    }

    Write-Output 'data-plane-denied-before-assignment'
}
catch {
    exit 1
}
