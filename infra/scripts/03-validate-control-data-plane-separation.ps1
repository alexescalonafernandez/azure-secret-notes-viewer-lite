[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $VaultName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

try {
    if ([string]::IsNullOrWhiteSpace($VaultName)) {
        exit 1
    }

    $captured = @(
        & az keyvault secret list `
            --vault-name $VaultName `
            --maxresults 1 `
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
