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
$secretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'
$secretsOfficerRoleDefinitionId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$syntheticContentType = 'text/plain; purpose=synthetic-demo'
$publicLogicalNoteIds = @(
    'demo-operations-note'
    'demo-integration-note'
    'demo-recovery-note'
)
$validationFailureReason = $null

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

function Get-VaultRoleAssignments {
    param(
        [Parameter(Mandatory)]
        [string] $VaultScope,

        [string] $PrincipalId,

        [switch] $IncludeInherited
    )

    $arguments = @(
        'role', 'assignment', 'list',
        '--scope', $VaultScope,
        '--fill-principal-name', 'false',
        '--fill-role-definition-name', 'false',
        '--query', '[].{roleDefinitionId:roleDefinitionId,principalId:principalId,principalType:principalType,scope:scope}',
        '--subscription', $script:subscriptionId,
        '--output', 'json',
        '--only-show-errors'
    )
    if ($IncludeInherited) {
        if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
            throw 'principal-input-invalid'
        }

        $arguments += @(
            '--assignee-object-id', $PrincipalId,
            '--include-groups',
            '--include-inherited'
        )
    }

    $jsonLines = @(& az @arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'role-assignment-query-failed'
    }
    $json = $jsonLines -join [Environment]::NewLine
    return @(ConvertFrom-SanitizedJson -Json $json)
}

function Test-RoleHasKeyVaultDataActions {
    param(
        [Parameter(Mandatory)]
        [string] $RoleDefinitionId
    )

    if ([string]::IsNullOrWhiteSpace($RoleDefinitionId)) {
        throw 'role-definition-invalid'
    }

    $roleDefinitionName = $RoleDefinitionId.TrimEnd('/').Split('/')[-1]
    $jsonLines = @(
        & az role definition list `
            --name $roleDefinitionName `
            --query '[0].permissions[].dataActions[]' `
            --subscription $script:subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'role-definition-query-failed'
    }
    $json = $jsonLines -join [Environment]::NewLine
    $dataActions = @(ConvertFrom-SanitizedJson -Json $json)

    return @(
        $dataActions | Where-Object {
            $_ -eq '*' -or $_ -like 'Microsoft.KeyVault/*'
        }
    ).Count -gt 0
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

    $vaultJsonLines = @(
        & az keyvault show `
            --resource-group $ResourceGroupName `
            --name $VaultName `
            --query '{sku:properties.sku.name,rbac:properties.enableRbacAuthorization,purge:properties.enablePurgeProtection,retention:properties.softDeleteRetentionInDays,publicNetworkAccess:properties.publicNetworkAccess,scope:id}' `
            --subscription $subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'vault-query-failed'
    }
    $vaultJson = $vaultJsonLines -join [Environment]::NewLine
    $vault = ConvertFrom-SanitizedJson -Json $vaultJson
    if (
        $vault.sku -ine 'standard' -or
        $vault.rbac -ne $true -or
        $vault.purge -ne $true -or
        $vault.retention -ne 7 -or
        $vault.publicNetworkAccess -ine 'Enabled' -or
        [string]::IsNullOrWhiteSpace($vault.scope)
    ) {
        throw 'vault-configuration-invalid'
    }
    Write-Output 'vault-configuration-valid'

    $readerReady = $false
    for ($attempt = 1; $attempt -le $PropagationMaxAttempts; $attempt++) {
        $null = & az keyvault secret list `
            --vault-name $VaultName `
            --maxresults 1 `
            --subscription $subscriptionId `
            --output none `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0) {
            $readerReady = $true
            break
        }

        if ($attempt -lt $PropagationMaxAttempts) {
            Start-Sleep -Seconds $PropagationDelaySeconds
        }
    }
    if (-not $readerReady) {
        throw 'reader-propagation-timeout'
    }
    Write-Output 'reader-access-propagated'

    $listedSecretsJsonLines = @(
        & az keyvault secret list `
            --vault-name $VaultName `
            --query '[].{name:name,enabled:attributes.enabled,expires:attributes.expires}' `
            --subscription $subscriptionId `
            --output json `
            --only-show-errors 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'secret-list-failed'
    }
    $listedSecretsJson = $listedSecretsJsonLines -join [Environment]::NewLine
    $listedSecrets = @(ConvertFrom-SanitizedJson -Json $listedSecretsJson)
    if ($listedSecrets.Count -ne 3) {
        throw 'synthetic-secret-count-invalid'
    }

    foreach ($fixture in $fixtures) {
        $listedSecret = @(
            $listedSecrets | Where-Object {
                [string]::Equals(
                    $_.name,
                    $fixture.Name,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
        )
        if ($listedSecret.Count -ne 1) {
            throw 'synthetic-secret-name-set-invalid'
        }

        $secretJsonLines = @(
            & az keyvault secret show `
                --vault-name $VaultName `
                --name $fixture.Name `
                --query '{value:value,enabled:attributes.enabled,created:attributes.created,expires:attributes.expires,contentType:contentType}' `
                --subscription $subscriptionId `
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
            $secret.value -cne $fixture.Value
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
            $secret.contentType -cne $syntheticContentType
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

        $versionCount = (
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
        if (
            [string]::IsNullOrWhiteSpace([string] $versionCount) -or
            ([string] $versionCount).Trim() -ne '1'
        ) {
            throw 'synthetic-secret-version-validation-failed'
        }
    }
    Write-Output 'synthetic-secrets-valid'

    $exactVaultAssignments = @(
        Get-VaultRoleAssignments -VaultScope $vault.scope |
            Where-Object {
                [string]::Equals(
                    $_.scope,
                    $vault.scope,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    $readerAssignments = @(
        $exactVaultAssignments | Where-Object {
            $_.principalId -eq $principalId -and
            $_.principalType -eq 'User' -and
            $_.roleDefinitionId.EndsWith(
                $secretsUserRoleDefinitionId,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    $officerAssignments = @(
        $exactVaultAssignments | Where-Object {
            $_.roleDefinitionId.EndsWith(
                $secretsOfficerRoleDefinitionId,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    $applicationIdentityAssignments = @(
        $exactVaultAssignments | Where-Object {
            $_.principalType -in @('ServicePrincipal', 'ManagedIdentity')
        }
    )

    if (
        $readerAssignments.Count -ne 1 -or
        $officerAssignments.Count -ne 0 -or
        $applicationIdentityAssignments.Count -ne 0
    ) {
        throw 'vault-role-state-invalid'
    }

    $effectiveVaultAssignments = @(
        Get-VaultRoleAssignments `
            -VaultScope $vault.scope `
            -PrincipalId $principalId `
            -IncludeInherited
    )
    $inheritedAssignments = @(
        $effectiveVaultAssignments | Where-Object {
            -not [string]::Equals(
                $_.scope,
                $vault.scope,
                [StringComparison]::OrdinalIgnoreCase
            )
        }
    )
    $inheritedRoleDefinitionIds = @(
        $inheritedAssignments |
            ForEach-Object { $_.roleDefinitionId } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
    foreach ($inheritedRoleDefinitionId in $inheritedRoleDefinitionIds) {
        if (Test-RoleHasKeyVaultDataActions -RoleDefinitionId $inheritedRoleDefinitionId) {
            throw 'inherited-data-plane-permission-unsupported'
        }
    }
    Write-Output 'vault-role-state-valid'

    Write-Output 'development-key-vault-valid'
}
catch {
    $validationFailureReason = $_.Exception.Message
    if ($validationFailureReason -notmatch '^[a-z0-9-]+$') {
        $validationFailureReason = 'validation-operation-failed'
    }

    if (-not [string]::IsNullOrWhiteSpace($validationFailureReason)) {
        Write-Output "development-key-vault-failure-reason:$validationFailureReason"
    }

    Write-Output 'development-key-vault-validation-failed'
    exit 1
}
