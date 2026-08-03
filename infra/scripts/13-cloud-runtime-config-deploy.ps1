#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $WebAppName,

    [Parameter(Mandatory)]
    [string] $KeyVaultName,

    [Parameter(Mandatory)]
    [string] $CloudTenantId,

    [Parameter(Mandatory)]
    [string] $CloudAppClientId,

    [Parameter(Mandatory)]
    [string] $DeploymentAppClientId,

    [switch] $WhatIf,

    [switch] $Apply
)

. (Join-Path $PSScriptRoot 'cloud-entra-common.ps1')

try {
    if ($WhatIf -and $Apply) { throw 'execution-mode-invalid' }
    if (
        $ResourceGroupName -notmatch '^[A-Za-z0-9_.()-]{1,90}$' -or
        $WebAppName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{1,58}[A-Za-z0-9]$' -or
        $KeyVaultName -notmatch '^[A-Za-z0-9-]{3,24}$'
    ) { throw 'private-input-invalid' }
    Assert-GuidString $CloudTenantId 'cloud-tenant-input-invalid'
    Assert-GuidString $CloudAppClientId 'cloud-application-input-invalid'
    Assert-GuidString $DeploymentAppClientId 'deployment-identity-input-invalid'
    if ([string]::Equals(
        $CloudAppClientId,
        $DeploymentAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'cloud-deployment-identity-reused' }
    if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'azure-cli-unavailable'
    }

    $context = Get-AzureContext
    $subscriptionId = Get-RequiredStringProperty $context 'id' 'subscription-context-invalid'
    $activeTenantId = Get-RequiredStringProperty $context 'tenantId' 'subscription-context-invalid'
    if (-not [string]::Equals(
        $activeTenantId,
        $CloudTenantId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'cloud-tenant-context-mismatch' }

    $templateFile = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '../modules/web-app-runtime-config.bicep')
    )
    if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
        throw 'runtime-template-missing'
    }

    $null = & az bicep build `
        --file $templateFile `
        --stdout `
        2>$null
    if ($LASTEXITCODE -ne 0) { throw 'runtime-template-build-failed' }
    Write-Output 'cloud-runtime-template-build-valid'

    $parametersFile = New-TemporaryFile
    try {
        $parametersDocument = [ordered]@{
            '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters = [ordered]@{
                webAppName = @{ value = $WebAppName }
                cloudTenantId = @{ value = $CloudTenantId }
                cloudAppClientId = @{ value = $CloudAppClientId }
            }
        } | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText(
            $parametersFile.FullName,
            $parametersDocument,
            [Text.UTF8Encoding]::new($false)
        )

        Invoke-AzureMutation `
            -FailureReason 'cloud-runtime-template-validation-failed' `
            -Arguments @(
                'deployment', 'group', 'validate',
                '--resource-group', $ResourceGroupName,
                '--subscription', $subscriptionId,
                '--template-file', $templateFile,
                '--parameters', "@$($parametersFile.FullName)",
                '--output', 'none',
                '--only-show-errors'
            )
        Write-Output 'cloud-runtime-template-validation-valid'

        if ($WhatIf) {
            Invoke-AzureMutation `
                -FailureReason 'cloud-runtime-what-if-failed' `
                -Arguments @(
                    'deployment', 'group', 'what-if',
                    '--resource-group', $ResourceGroupName,
                    '--subscription', $subscriptionId,
                    '--template-file', $templateFile,
                    '--parameters', "@$($parametersFile.FullName)",
                    '--result-format', 'ResourceIdOnly',
                    '--no-pretty-print',
                    '--output', 'none',
                    '--only-show-errors'
                )
            Write-Output 'cloud-runtime-what-if-valid'
            Write-Output 'cloud-runtime-apply-required'
            return
        }

        if (-not $Apply) {
            Write-Output 'cloud-runtime-apply-required'
            return
        }

        Invoke-AzureMutation `
            -FailureReason 'cloud-runtime-deployment-failed' `
            -Arguments @(
                'deployment', 'group', 'create',
                '--name', 'cloud-runtime-config',
                '--resource-group', $ResourceGroupName,
                '--subscription', $subscriptionId,
                '--template-file', $templateFile,
                '--parameters', "@$($parametersFile.FullName)",
                '--output', 'none',
                '--only-show-errors'
            )
    }
    finally {
        Remove-Item -LiteralPath $parametersFile.FullName -Force -ErrorAction SilentlyContinue
    }

    $webApp = Get-ExistingWebAppState $ResourceGroupName $WebAppName $subscriptionId
    $webAppId = Get-RequiredStringProperty $webApp 'id' 'web-app-response-invalid'
    $webAppPrincipalId = Get-RequiredStringProperty $webApp 'principalId' 'web-app-response-invalid'
    $settings = Invoke-AzureJsonArray `
        -FailureReason 'cloud-runtime-settings-response-invalid' `
        -Arguments @(
            'webapp', 'config', 'appsettings', 'list',
            '--resource-group', $ResourceGroupName,
            '--name', $WebAppName,
            '--subscription', $subscriptionId,
            '--query', '[].{name:name,value:value}',
            '--output', 'json',
            '--only-show-errors'
        )
    $expectedSettings = [ordered]@{
        ASPNETCORE_ENVIRONMENT = 'Production'
        AzureAd__TenantId = $CloudTenantId
        AzureAd__ClientId = $CloudAppClientId
        AzureAd__ClientCredentials__0__SourceType = 'SignedAssertionFromManagedIdentity'
        NoteContent__Provider = 'InMemory'
    }
    if ($settings.Count -ne $expectedSettings.Count) { throw 'cloud-runtime-settings-mismatch' }
    foreach ($setting in $settings) {
        $name = Get-RequiredStringProperty $setting 'name' 'cloud-runtime-settings-response-invalid'
        $value = Get-RequiredStringProperty $setting 'value' 'cloud-runtime-settings-response-invalid'
        if (-not $expectedSettings.Contains($name) -or $value -cne [string] $expectedSettings[$name]) {
            throw 'cloud-runtime-settings-mismatch'
        }
        if (
            $name -match '(?i)(ClientSecret|Certificate|ManagedIdentityClientId)' -or
            $value -match '(?i)@Microsoft\.KeyVault\('
        ) { throw 'cloud-runtime-credential-setting-present' }
    }
    Write-Output 'cloud-runtime-settings-valid'
    Write-Output 'in-memory-provider-valid'
    Write-Output 'cloud-runtime-credentials-secretless'

    $connectionStrings = Invoke-AzureJsonArray `
        -FailureReason 'connection-strings-response-invalid' `
        -Arguments @(
            'webapp', 'config', 'connection-string', 'list',
            '--resource-group', $ResourceGroupName,
            '--name', $WebAppName,
            '--subscription', $subscriptionId,
            '--query', '[].{name:name}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($connectionStrings.Count -ne 0) { throw 'connection-string-present' }

    foreach ($policyName in @('scm', 'ftp')) {
        $policy = Invoke-AzureJsonObject `
            -FailureReason 'publishing-policy-response-invalid' `
            -Arguments @(
                'resource', 'show',
                '--ids', "$webAppId/basicPublishingCredentialsPolicies/$policyName",
                '--api-version', '2025-03-01',
                '--subscription', $subscriptionId,
                '--query', '{allow:properties.allow}',
                '--output', 'json',
                '--only-show-errors'
            )
        if ((Get-RequiredBooleanProperty $policy 'allow' 'publishing-policy-response-invalid')) {
            throw 'publishing-credentials-enabled'
        }
    }
    Write-Output 'publishing-credentials-disabled'

    $vault = Invoke-AzureJsonObject `
        -FailureReason 'key-vault-response-invalid' `
        -Arguments @(
            'keyvault', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $KeyVaultName,
            '--subscription', $subscriptionId,
            '--query', '{id:id}',
            '--output', 'json',
            '--only-show-errors'
        )
    $vaultId = Get-RequiredStringProperty $vault 'id' 'key-vault-response-invalid'
    $deploymentSp = Invoke-AzureJsonObject `
        -FailureReason 'deployment-service-principal-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $DeploymentAppClientId,
            '--query', '{id:id}',
            '--output', 'json',
            '--only-show-errors'
        )
    $deploymentPrincipalId = Get-RequiredStringProperty `
        $deploymentSp 'id' 'deployment-service-principal-response-invalid'
    Assert-NoDirectKeyVaultRole `
        $webAppPrincipalId $vaultId $subscriptionId 'web-app-key-vault-rbac-present'
    Assert-NoDirectKeyVaultRole `
        $deploymentPrincipalId $vaultId $subscriptionId 'deployment-key-vault-rbac-present'
    Write-Output 'key-vault-rbac-absent'
    Write-Output 'cloud-runtime-config-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'cloud-runtime-operation-failed' }
    Write-Output "cloud-runtime-failure-reason:$reason"
    Write-Output 'cloud-runtime-config-failed'
    exit 1
}
