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

$secretsOfficerRoleDefinitionId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
$syntheticContentType = 'text/plain; purpose=synthetic-demo'
$temporaryRoleAssignmentId = $null
$temporaryRoleCreated = $false
$bootstrapSucceeded = $false
$cleanupSucceeded = $true

function Invoke-AzCli {
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

function Invoke-AzCliRequired {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $result = Invoke-AzCli -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw 'azure-command-failed'
    }

    return $result.Output
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

function Get-ExactVaultRoleAssignments {
    param(
        [Parameter(Mandatory)]
        [string] $PrincipalId,

        [Parameter(Mandatory)]
        [string] $VaultScope,

        [Parameter(Mandatory)]
        [string] $RoleDefinitionId
    )

    $json = Invoke-AzCliRequired -Arguments @(
        'role', 'assignment', 'list',
        '--assignee-object-id', $PrincipalId,
        '--scope', $VaultScope,
        '--role', $RoleDefinitionId,
        '--query', '[].{roleDefinitionId:roleDefinitionId,scope:scope}',
        '--output', 'json',
        '--only-show-errors'
    )
    $assignments = @(ConvertFrom-SanitizedJson -Json $json)

    return @(
        $assignments | Where-Object {
            $_.scope -eq $VaultScope -and
            $_.roleDefinitionId.EndsWith($RoleDefinitionId, [StringComparison]::OrdinalIgnoreCase)
        }
    )
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

    $vaultScope = (
        Invoke-AzCliRequired -Arguments @(
            'keyvault', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $VaultName,
            '--query', 'id',
            '--output', 'tsv',
            '--only-show-errors'
        )
    ).Trim()
    if ([string]::IsNullOrWhiteSpace($vaultScope)) {
        throw 'vault-scope-unavailable'
    }

    $existingOfficerAssignments = @(
        Get-ExactVaultRoleAssignments `
            -PrincipalId $principalId `
            -VaultScope $vaultScope `
            -RoleDefinitionId $secretsOfficerRoleDefinitionId
    )
    if ($existingOfficerAssignments.Count -ne 0) {
        throw 'preexisting-officer-assignment'
    }

    $temporaryRoleAssignmentId = (
        Invoke-AzCliRequired -Arguments @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $principalId,
            '--assignee-principal-type', 'User',
            '--role', $secretsOfficerRoleDefinitionId,
            '--scope', $vaultScope,
            '--query', 'id',
            '--output', 'tsv',
            '--only-show-errors'
        )
    ).Trim()
    if ([string]::IsNullOrWhiteSpace($temporaryRoleAssignmentId)) {
        throw 'temporary-officer-assignment-failed'
    }

    $temporaryRoleCreated = $true
    Write-Output 'temporary-officer-assigned'

    $rbacReady = $false
    for ($attempt = 1; $attempt -le $PropagationMaxAttempts; $attempt++) {
        $probe = Invoke-AzCli -Arguments @(
            'keyvault', 'secret', 'list',
            '--vault-name', $VaultName,
            '--maxresults', '1',
            '--output', 'none',
            '--only-show-errors'
        )
        if ($probe.ExitCode -eq 0) {
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

    $existingSecretNamesJson = Invoke-AzCliRequired -Arguments @(
        'keyvault', 'secret', 'list',
        '--vault-name', $VaultName,
        '--query', '[].name',
        '--output', 'json',
        '--only-show-errors'
    )
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
        $null = Invoke-AzCliRequired -Arguments @(
            'keyvault', 'secret', 'set',
            '--vault-name', $VaultName,
            '--name', $fixture.Name,
            '--value', $fixture.Value,
            '--content-type', $syntheticContentType,
            '--expires', $expirationArgument,
            '--disabled', 'false',
            '--output', 'none',
            '--only-show-errors'
        )
    }
    Write-Output 'synthetic-secrets-created'

    foreach ($fixture in $fixtures) {
        $secretJson = Invoke-AzCliRequired -Arguments @(
            'keyvault', 'secret', 'show',
            '--vault-name', $VaultName,
            '--name', $fixture.Name,
            '--query', '{value:value,enabled:attributes.enabled,expires:attributes.expires,contentType:contentType}',
            '--output', 'json',
            '--only-show-errors'
        )
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
            Invoke-AzCliRequired -Arguments @(
                'keyvault', 'secret', 'list-versions',
                '--vault-name', $VaultName,
                '--name', $fixture.Name,
                '--query', 'length(@)',
                '--output', 'tsv',
                '--only-show-errors'
            )
        ).Trim()
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
    if ($temporaryRoleCreated) {
        $cleanupSucceeded = $false
        for ($attempt = 1; $attempt -le $PropagationMaxAttempts; $attempt++) {
            $null = Invoke-AzCli -Arguments @(
                'role', 'assignment', 'delete',
                '--ids', $temporaryRoleAssignmentId,
                '--output', 'none',
                '--only-show-errors'
            )

            try {
                $remainingAssignments = @(
                    Get-ExactVaultRoleAssignments `
                        -PrincipalId $principalId `
                        -VaultScope $vaultScope `
                        -RoleDefinitionId $secretsOfficerRoleDefinitionId
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
