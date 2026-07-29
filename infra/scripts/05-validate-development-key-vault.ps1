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

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$secretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'
$secretsOfficerRoleDefinitionId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$syntheticContentType = 'text/plain; purpose=synthetic-demo'
$publicLogicalNoteIds = @(
    'demo-operations-note'
    'demo-integration-note'
    'demo-recovery-note'
)

function Invoke-AzCliUnscoped {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $captured = @(& az @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $capturedText = ($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $capturedText
    }
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $effectiveArguments = @($Arguments) + @('--subscription', $script:subscriptionId)
    return Invoke-AzCliUnscoped -Arguments $effectiveArguments
}

function Invoke-AzCliRequired {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $result = Invoke-AzCli -Arguments $Arguments
    $exitCode = $result.ExitCode
    if ($exitCode -ne 0) {
        throw 'azure-command-failed'
    }

    return $result.Output
}

function Get-SignedInUserObjectId {
    $result = Invoke-AzCliUnscoped -Arguments @(
        'ad', 'signed-in-user', 'show',
        '--query', 'id',
        '--output', 'tsv',
        '--only-show-errors'
    )
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        throw 'signed-in-user-unavailable'
    }

    return $result.Output.Trim()
}

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
        '--all',
        '--scope', $VaultScope,
        '--fill-principal-name', 'false',
        '--fill-role-definition-name', 'false',
        '--query', '[].{roleDefinitionId:roleDefinitionId,principalId:principalId,principalType:principalType,scope:scope}',
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

    $json = Invoke-AzCliRequired -Arguments $arguments
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
    $json = Invoke-AzCliRequired -Arguments @(
        'role', 'definition', 'list',
        '--name', $roleDefinitionName,
        '--query', '[0].permissions[].dataActions[]',
        '--output', 'json',
        '--only-show-errors'
    )
    $dataActions = @(ConvertFrom-SanitizedJson -Json $json)

    return @(
        $dataActions | Where-Object {
            $_ -eq '*' -or $_ -like 'Microsoft.KeyVault/*'
        }
    ).Count -gt 0
}

try {
    if (
        [string]::IsNullOrWhiteSpace($subscriptionId) -or
        [string]::IsNullOrWhiteSpace($ResourceGroupName) -or
        [string]::IsNullOrWhiteSpace($VaultName)
    ) {
        throw 'resource-input-invalid'
    }

    $availableSubscriptionId = (
        Invoke-AzCliRequired -Arguments @(
            'account', 'show',
            '--query', 'id',
            '--output', 'tsv',
            '--only-show-errors'
        )
    ).Trim()
    if (
        -not [string]::Equals(
            $availableSubscriptionId,
            $subscriptionId.Trim(),
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'subscription-context-invalid'
    }

    $setSubscriptionResult = Invoke-AzCliUnscoped -Arguments @(
        'account', 'set',
        '--subscription', $subscriptionId,
        '--only-show-errors',
        '--output', 'none'
    )
    if ($setSubscriptionResult.ExitCode -ne 0) {
        throw 'subscription-context-invalid'
    }

    $activeSubscriptionId = (
        Invoke-AzCliRequired -Arguments @(
            'account', 'show',
            '--query', 'id',
            '--output', 'tsv',
            '--only-show-errors'
        )
    ).Trim()
    if (
        -not [string]::Equals(
            $activeSubscriptionId,
            $subscriptionId.Trim(),
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'subscription-context-invalid'
    }

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

    $principalId = Get-SignedInUserObjectId
    if ([string]::IsNullOrWhiteSpace($principalId)) {
        throw 'signed-in-user-unavailable'
    }

    $vaultJson = Invoke-AzCliRequired -Arguments @(
        'keyvault', 'show',
        '--resource-group', $ResourceGroupName,
        '--name', $VaultName,
        '--query', '{sku:properties.sku.name,rbac:properties.enableRbacAuthorization,purge:properties.enablePurgeProtection,retention:properties.softDeleteRetentionInDays,publicNetworkAccess:properties.publicNetworkAccess,scope:id}',
        '--output', 'json',
        '--only-show-errors'
    )
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
        $probe = Invoke-AzCli -Arguments @(
            'keyvault', 'secret', 'list',
            '--vault-name', $VaultName,
            '--maxresults', '1',
            '--output', 'none',
            '--only-show-errors'
        )
        if ($probe.ExitCode -eq 0) {
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

    $listedSecretsJson = Invoke-AzCliRequired -Arguments @(
        'keyvault', 'secret', 'list',
        '--vault-name', $VaultName,
        '--query', '[].{name:name,enabled:attributes.enabled,expires:attributes.expires}',
        '--output', 'json',
        '--only-show-errors'
    )
    $listedSecrets = @(ConvertFrom-SanitizedJson -Json $listedSecretsJson)
    if ($listedSecrets.Count -ne 3) {
        throw 'synthetic-secret-count-invalid'
    }

    foreach ($fixture in $fixtures) {
        $listedSecret = @(
            $listedSecrets | Where-Object { $_.name -ceq $fixture.Name }
        )
        if (
            $listedSecret.Count -ne 1 -or
            $listedSecret[0].enabled -ne $true -or
            [string]::IsNullOrWhiteSpace($listedSecret[0].expires)
        ) {
            throw 'synthetic-secret-metadata-invalid'
        }

        $secretJson = Invoke-AzCliRequired -Arguments @(
            'keyvault', 'secret', 'show',
            '--vault-name', $VaultName,
            '--name', $fixture.Name,
            '--query', '{value:value,enabled:attributes.enabled,created:attributes.created,expires:attributes.expires,contentType:contentType}',
            '--output', 'json',
            '--only-show-errors'
        )
        $secret = ConvertFrom-SanitizedJson -Json $secretJson
        $createdUtc = [DateTimeOffset]::Parse(
            $secret.created,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()
        $expiresUtc = [DateTimeOffset]::Parse(
            $secret.expires,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal
        ).ToUniversalTime()

        if (
            $secret.value -cne $fixture.Value -or
            $secret.enabled -ne $true -or
            $secret.contentType -cne $syntheticContentType -or
            [Math]::Abs((($expiresUtc - $createdUtc).TotalDays) - 90) -gt 0.001
        ) {
            throw 'synthetic-secret-validation-failed'
        }

        $versionCount = (
            Invoke-AzCliRequired -Arguments @(
                'keyvault', 'secret', 'list-versions',
                '--vault-name', $VaultName,
                '--name', $fixture.Name,
                '--query', 'length(@)',
                '--output', 'tsv',
                '--only-show-errors'
            )
        ).Trim()
        if ($versionCount -ne '1') {
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
    Write-Output 'development-key-vault-validation-failed'
    exit 1
}
