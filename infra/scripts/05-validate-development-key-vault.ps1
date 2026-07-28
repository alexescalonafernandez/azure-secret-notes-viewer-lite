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
    [string] $RecoverySecretName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$secretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'
$secretsOfficerRoleDefinitionId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$syntheticContentType = 'text/plain; purpose=synthetic-demo'

function Invoke-AzCliRequired {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $captured = @(& az @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw 'azure-command-failed'
    }

    return ($captured | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
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

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9-]{1,127}$') {
        throw 'private-input-invalid'
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($VaultName)) {
        throw 'resource-input-invalid'
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

    $principalId = (
        Invoke-AzCliRequired -Arguments @(
            'ad', 'signed-in-user', 'show',
            '--query', 'id',
            '--output', 'tsv',
            '--only-show-errors'
        )
    ).Trim()
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

    $roleAssignmentsJson = Invoke-AzCliRequired -Arguments @(
        'role', 'assignment', 'list',
        '--scope', $vault.scope,
        '--query', '[].{roleDefinitionId:roleDefinitionId,principalId:principalId,principalType:principalType,scope:scope}',
        '--output', 'json',
        '--only-show-errors'
    )
    $exactVaultAssignments = @(
        @(ConvertFrom-SanitizedJson -Json $roleAssignmentsJson) |
            Where-Object { $_.scope -eq $vault.scope }
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
    Write-Output 'vault-role-state-valid'

    Write-Output 'development-key-vault-valid'
}
catch {
    Write-Output 'development-key-vault-validation-failed'
    exit 1
}
