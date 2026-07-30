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

    [switch] $ResumeExistingSecrets,

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
$bootstrapFailureReason = $null
$cleanupFailureReason = $null

function ConvertFrom-SanitizedJson {
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    try {
        return $Json | ConvertFrom-Json -DateKind String
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
            --scope $VaultScope `
            --fill-principal-name false `
            --fill-role-definition-name false `
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

function Assert-SyntheticSecretFixture {
    param(
        [Parameter(Mandatory)]
        [string] $VaultName,

        [Parameter(Mandatory)]
        [psobject] $Fixture
    )

    $secretJsonLines = @(
        & az keyvault secret show `
            --vault-name $VaultName `
            --name $Fixture.Name `
            --query '{value:value,enabled:attributes.enabled,created:attributes.created,expires:attributes.expires,contentType:contentType}' `
            --subscription $script:subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'synthetic-secret-read-failed'
    }
    $secretJson = $secretJsonLines -join [Environment]::NewLine
    $secret = ConvertFrom-SanitizedJson -Json $secretJson

    if (
        $null -eq $secret -or
        $null -eq $secret.PSObject.Properties['value'] -or
        $secret.value -cne $Fixture.Value
    ) {
        throw 'synthetic-secret-value-invalid'
    }
    if (
        $null -eq $secret.PSObject.Properties['enabled'] -or
        $secret.enabled -ne $true
    ) {
        throw 'synthetic-secret-enabled-invalid'
    }
    if (
        $null -eq $secret.PSObject.Properties['contentType'] -or
        $secret.contentType -cne $script:syntheticContentType
    ) {
        throw 'synthetic-secret-content-type-invalid'
    }

    $createdUtc = [DateTimeOffset]::MinValue
    if (
        $null -eq $secret.PSObject.Properties['created'] -or
        [string]::IsNullOrWhiteSpace([string] $secret.created) -or
        -not [DateTimeOffset]::TryParse(
            [string] $secret.created,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $createdUtc
        )
    ) {
        throw 'synthetic-secret-created-invalid'
    }

    $expiresUtc = [DateTimeOffset]::MinValue
    if (
        $null -eq $secret.PSObject.Properties['expires'] -or
        [string]::IsNullOrWhiteSpace([string] $secret.expires) -or
        -not [DateTimeOffset]::TryParse(
            [string] $secret.expires,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $expiresUtc
        )
    ) {
        throw 'synthetic-secret-expiration-invalid'
    }

    $lifetimeDays = (
        $expiresUtc.ToUniversalTime() - $createdUtc.ToUniversalTime()
    ).TotalDays
    if ([Math]::Abs($lifetimeDays - 90) -gt 0.001) {
        throw 'synthetic-secret-expiration-invalid'
    }

    $versionsJsonLines = @(
        & az keyvault secret list-versions `
            --vault-name $VaultName `
            --name $Fixture.Name `
            --subscription $script:subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'synthetic-secret-version-query-failed'
    }
    $versionsJson = $versionsJsonLines -join [Environment]::NewLine
    $versions = @(ConvertFrom-SanitizedJson -Json $versionsJson)
    if ($versions.Count -ne 1) {
        throw 'synthetic-secret-version-validation-failed'
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

    if ($ResumeExistingSecrets) {
        if ($existingSecretNames.Count -ne 3) {
            throw 'recovery-secret-count-invalid'
        }

        $existingSecretNameSet = [System.Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($existingSecretName in $existingSecretNames) {
            if (
                [string]::IsNullOrWhiteSpace([string] $existingSecretName) -or
                -not $existingSecretNameSet.Add([string] $existingSecretName)
            ) {
                throw 'recovery-secret-name-set-invalid'
            }
        }
        if (-not $existingSecretNameSet.SetEquals($uniqueSecretNames)) {
            throw 'recovery-secret-name-set-invalid'
        }

        Write-Output 'synthetic-secrets-resume-state-valid'
    }
    else {
        if ($existingSecretNames.Count -ne 0) {
            throw 'vault-not-empty'
        }

        $expirationArgument = [DateTimeOffset]::UtcNow.AddDays(90).ToString(
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
    }

    foreach ($fixture in $fixtures) {
        Assert-SyntheticSecretFixture -VaultName $VaultName -Fixture $fixture
    }
    Write-Output 'synthetic-secrets-validated'

    $bootstrapSucceeded = $true
}
catch {
    $bootstrapSucceeded = $false
    $bootstrapFailureReason = $_.Exception.Message
    if ($bootstrapFailureReason -notmatch '^[a-z0-9-]+$') {
        $bootstrapFailureReason = 'bootstrap-operation-failed'
    }
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
                    $cleanupFailureReason = $null
                    break
                }
                $cleanupFailureReason = 'temporary-officer-cleanup-unverified'
            }
            catch {
                $cleanupSucceeded = $false
                $cleanupFailureReason = $_.Exception.Message
                if ($cleanupFailureReason -notmatch '^[a-z0-9-]+$') {
                    $cleanupFailureReason = 'temporary-officer-cleanup-unverified'
                }
            }

            if ($attempt -lt $PropagationMaxAttempts) {
                Start-Sleep -Seconds $PropagationDelaySeconds
            }
        }

        if ($cleanupSucceeded) {
            Write-Output 'temporary-officer-removed'
        }
        elseif ([string]::IsNullOrWhiteSpace($cleanupFailureReason)) {
            $cleanupFailureReason = 'temporary-officer-cleanup-unverified'
        }
    }
}

if (-not $bootstrapSucceeded -or -not $cleanupSucceeded) {
    if (-not [string]::IsNullOrWhiteSpace($bootstrapFailureReason)) {
        Write-Output "bootstrap-failure-reason:$bootstrapFailureReason"
    }

    if (
        -not $cleanupSucceeded -and
        -not [string]::IsNullOrWhiteSpace($cleanupFailureReason)
    ) {
        Write-Output "bootstrap-cleanup-failure-reason:$cleanupFailureReason"
    }

    Write-Output 'bootstrap-failed'
    exit 1
}

Write-Output 'bootstrap-complete'
