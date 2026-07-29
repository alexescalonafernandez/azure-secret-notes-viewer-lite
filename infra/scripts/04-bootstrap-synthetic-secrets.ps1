[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $VaultName,

    [Parameter(Mandatory)]
    [string] $OperationsSecretName,

    [Parameter(Mandatory)]
    [string] $IntegrationSecretName,

    [Parameter(Mandatory)]
    [string] $RecoverySecretName,

    [ValidateRange(1, 60)]
    [int] $PropagationMaxAttempts = 12,

    [ValidateRange(1, 60)]
    [int] $PropagationDelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$subscriptionId = $null
$secretsOfficerRoleDefinitionId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$syntheticContentType = 'text/plain; purpose=synthetic-demo'
$publicLogicalNoteIds = @(
    'demo-operations-note'
    'demo-integration-note'
    'demo-recovery-note'
)
$temporaryRoleAssignmentName = [Guid]::NewGuid().ToString()
$temporaryRoleAssignmentId = $null
$temporaryRoleCreationAttempted = $false
$bootstrapSucceeded = $false
$cleanupSucceeded = $true

function ConvertFrom-SanitizedJson {
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    try {
        return $Json | ConvertFrom-Json
    }
    catch {
        throw 'azure-response-invalid'
    }
}

function Get-DirectVaultRoleAssignments {
    param(
        [Parameter(Mandatory)]
        [string] $VaultScope
    )

    $jsonLines = @(
        & az role assignment list `
            --all `
            --scope $VaultScope `
            --fill-principal-name false `
            --query '[].{roleDefinitionId:roleDefinitionId,principalId:principalId,principalType:principalType,scope:scope}' `
            --subscription $script:subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'role-assignment-query-failed'
    }
    $json = $jsonLines -join [Environment]::NewLine
    $assignments = @(ConvertFrom-SanitizedJson -Json $json)

    return @(
        $assignments | Where-Object {
            [string]::Equals(
                $_.scope,
                $VaultScope,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
}

function Assert-PrivateInput {
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    if (
        [string]::IsNullOrWhiteSpace($Value) -or
        $Value -notmatch '^[A-Za-z0-9-]{1,127}$' -or
        $script:publicLogicalNoteIds -icontains $Value
    ) {
        throw 'private-input-invalid'
    }
}

try {
    if (
        [string]::IsNullOrWhiteSpace($ResourceGroupName) -or
        [string]::IsNullOrWhiteSpace($VaultName)
    ) {
        throw 'resource-input-invalid'
    }

    $subscriptionId = (
        & az account show `
            --query id `
            --output tsv `
            --only-show-errors 2>$null
    )
    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($subscriptionId)
    ) {
        throw 'subscription-context-invalid'
    }
    $subscriptionId = $subscriptionId.Trim()

    $fixtures = @(
        [pscustomobject]@{
            Name = $OperationsSecretName
            Value = 'Synthetic operations note content.'
        },
        [pscustomobject]@{
            Name = $IntegrationSecretName
            Value = 'Synthetic integration note content.'
        },
        [pscustomobject]@{
            Name = $RecoverySecretName
            Value = 'Synthetic recovery note content.'
        }
    )

    $uniqueSecretNames = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($fixture in $fixtures) {
        Assert-PrivateInput -Value $fixture.Name
        if (-not $uniqueSecretNames.Add($fixture.Name)) {
            throw 'private-input-invalid'
        }
    }

    $principalId = (
        & az ad signed-in-user show `
            --query id `
            --output tsv `
            --only-show-errors 2>$null
    )
    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($principalId)
    ) {
        throw 'signed-in-user-unavailable'
    }
    $principalId = $principalId.Trim()

    $vaultScope = (
        & az keyvault show `
            --resource-group $ResourceGroupName `
            --name $VaultName `
            --query id `
            --subscription $subscriptionId `
            --output tsv `
            --only-show-errors 2>$null
    )
    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($vaultScope)
    ) {
        throw 'vault-scope-unavailable'
    }
    $vaultScope = $vaultScope.Trim()

    $existingOfficerAssignments = @(
        Get-DirectVaultRoleAssignments -VaultScope $vaultScope |
            Where-Object {
                $_.principalId -eq $principalId -and
                $_.roleDefinitionId.EndsWith(
                    $secretsOfficerRoleDefinitionId,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    if ($existingOfficerAssignments.Count -ne 0) {
        throw 'preexisting-officer-assignment'
    }

    $temporaryRoleAssignmentId = '{0}/providers/Microsoft.Authorization/roleAssignments/{1}' -f (
        $vaultScope.TrimEnd('/'),
        $temporaryRoleAssignmentName
    )
    $temporaryRoleCreationAttempted = $true
    $null = & az role assignment create `
        --name $temporaryRoleAssignmentName `
        --assignee-object-id $principalId `
        --assignee-principal-type User `
        --role $secretsOfficerRoleDefinitionId `
        --scope $vaultScope `
        --subscription $subscriptionId `
        --output none `
        --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'temporary-officer-assignment-failed'
    }

    Write-Output 'temporary-officer-assigned'

    $rbacReady = $false
    for ($attempt = 1; $attempt -le $PropagationMaxAttempts; $attempt++) {
        $null = & az keyvault secret list `
            --vault-name $VaultName `
            --maxresults 1 `
            --subscription $subscriptionId `
            --output none `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0) {
            $rbacReady = $true
            break
        }

        if ($attempt -lt $PropagationMaxAttempts) {
            Start-Sleep -Seconds $PropagationDelaySeconds
        }
    }
    if (-not $rbacReady) {
        throw 'rbac-propagation-timeout'
    }
    Write-Output 'temporary-officer-propagated'

    $existingSecretNamesJsonLines = @(
        & az keyvault secret list `
            --vault-name $VaultName `
            --query '[].name' `
            --subscription $subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'secret-list-failed'
    }
    $existingSecretNamesJson = $existingSecretNamesJsonLines -join [Environment]::NewLine
    $existingSecretNames = @(ConvertFrom-SanitizedJson -Json $existingSecretNamesJson)
    if ($existingSecretNames.Count -ne 0) {
        throw 'vault-not-empty'
    }

    $expirationUtc = [DateTimeOffset]::UtcNow.AddDays(90)
    $expirationArgument = $expirationUtc.ToString(
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )

    foreach ($fixture in $fixtures) {
        $null = & az keyvault secret set `
            --vault-name $VaultName `
            --name $fixture.Name `
            --value $fixture.Value `
            --content-type $syntheticContentType `
            --expires $expirationArgument `
            --disabled false `
            --subscription $subscriptionId `
            --output none `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'synthetic-secret-creation-failed'
        }
    }
    Write-Output 'synthetic-secrets-created'

    foreach ($fixture in $fixtures) {
        $secretJsonLines = @(
            & az keyvault secret show `
                --vault-name $VaultName `
                --name $fixture.Name `
                --query '{value:value,enabled:attributes.enabled,expires:attributes.expires,contentType:contentType}' `
                --subscription $subscriptionId `
                --output json `
                --only-show-errors 2>$null
        )
        if ($LASTEXITCODE -ne 0) {
            throw 'synthetic-secret-read-failed'
        }
        $secretJson = $secretJsonLines -join [Environment]::NewLine
        $secret = ConvertFrom-SanitizedJson -Json $secretJson
        $actualExpiration = [DateTimeOffset]::Parse(
            $secret.expires,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()

        if (
            $secret.value -cne $fixture.Value -or
            $secret.enabled -ne $true -or
            $secret.contentType -cne $syntheticContentType -or
            [Math]::Abs(($actualExpiration - $expirationUtc).TotalSeconds) -gt 2
        ) {
            throw 'synthetic-secret-validation-failed'
        }

        $versionCountText = (
            & az keyvault secret list-versions `
                --vault-name $VaultName `
                --name $fixture.Name `
                --query 'length(@)' `
                --subscription $subscriptionId `
                --output tsv `
                --only-show-errors 2>$null
        )
        if ($LASTEXITCODE -ne 0) {
            throw 'synthetic-secret-version-query-failed'
        }
        $versionCountText = $versionCountText.Trim()
        if ($versionCountText -ne '1') {
            throw 'synthetic-secret-version-validation-failed'
        }
    }
    Write-Output 'synthetic-secrets-validated'

    $bootstrapSucceeded = $true
}
catch {
    $bootstrapSucceeded = $false
}
finally {
    if ($temporaryRoleCreationAttempted) {
        $cleanupSucceeded = $false
        for ($attempt = 1; $attempt -le $PropagationMaxAttempts; $attempt++) {
            $null = & az role assignment delete `
                --ids $temporaryRoleAssignmentId `
                --subscription $subscriptionId `
                --output none `
                --only-show-errors 2>$null

            try {
                $remainingAssignments = @(
                    Get-DirectVaultRoleAssignments -VaultScope $vaultScope |
                        Where-Object {
                            $_.principalId -eq $principalId -and
                            $_.roleDefinitionId.EndsWith(
                                $secretsOfficerRoleDefinitionId,
                                [StringComparison]::OrdinalIgnoreCase
                            )
                        }
                )
                if ($remainingAssignments.Count -eq 0) {
                    $cleanupSucceeded = $true
                    break
                }
            }
            catch {
                $cleanupSucceeded = $false
            }

            if ($attempt -lt $PropagationMaxAttempts) {
                Start-Sleep -Seconds $PropagationDelaySeconds
            }
        }

        if ($cleanupSucceeded) {
            Write-Output 'temporary-officer-removed'
        }
    }
}

if (-not $bootstrapSucceeded -or -not $cleanupSucceeded) {
    Write-Output 'bootstrap-failed'
    exit 1
}

Write-Output 'bootstrap-complete'
