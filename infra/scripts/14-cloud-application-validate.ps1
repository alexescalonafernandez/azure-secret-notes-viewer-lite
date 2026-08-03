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
    [string] $DeploymentAppClientId
)

. (Join-Path $PSScriptRoot 'cloud-entra-common.ps1')

function Invoke-BoundedHttpCheck {
    param(
        [Parameter(Mandatory)][System.Net.Http.HttpClient] $Client,
        [Parameter(Mandatory)][uri] $Uri,
        [Parameter(Mandatory)][scriptblock] $Accept,
        [Parameter(Mandatory)][string] $FailureReason,
        [ValidateRange(1, 10)][int] $MaxAttempts = 4
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $response = $null
        try {
            $response = $Client.GetAsync($Uri).GetAwaiter().GetResult()
            if (& $Accept $response) { return }
        }
        catch {
            # Raw network exceptions can contain the private hostname; suppress them.
        }
        finally {
            if ($null -ne $response) { $response.Dispose() }
        }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 5 }
    }
    throw $FailureReason
}

try {
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

    $webApp = Get-ExistingWebAppState $ResourceGroupName $WebAppName $subscriptionId
    $webAppId = Get-RequiredStringProperty $webApp 'id' 'web-app-response-invalid'
    $webAppPrincipalId = Get-RequiredStringProperty $webApp 'principalId' 'web-app-response-invalid'
    $hostName = Get-RequiredStringProperty $webApp 'defaultHostName' 'web-app-response-invalid'
    Write-Output 'system-assigned-identity-valid'

    $siteConfig = Invoke-AzureJsonObject `
        -FailureReason 'site-config-response-invalid' `
        -Arguments @(
            'webapp', 'config', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $WebAppName,
            '--subscription', $subscriptionId,
            '--query', '{linuxFxVersion:linuxFxVersion,ftpsState:ftpsState}',
            '--output', 'json',
            '--only-show-errors'
        )
    if (
        (Get-RequiredStringProperty $siteConfig 'linuxFxVersion' 'site-config-response-invalid') -cne 'DOTNETCORE|10.0' -or
        (Get-RequiredStringProperty $siteConfig 'ftpsState' 'site-config-response-invalid') -cne 'Disabled'
    ) { throw 'site-config-invalid' }
    Write-Output 'dotnet-runtime-valid'

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

    $cloudApplication = Invoke-AzureJsonObject `
        -FailureReason 'cloud-application-response-invalid' `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $CloudAppClientId,
            '--query', '{appId:appId,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )
    $resolvedCloudAppId = Get-RequiredStringProperty `
        $cloudApplication 'appId' 'cloud-application-response-invalid'
    if (-not [string]::Equals(
        $resolvedCloudAppId,
        $CloudAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'cloud-application-response-invalid' }
    Assert-EmptyArrayProperty $cloudApplication 'passwordCredentials' 'cloud-password-credential-present'
    Assert-EmptyArrayProperty $cloudApplication 'keyCredentials' 'cloud-key-credential-present'
    Write-Output 'cloud-client-secret-absent'
    Write-Output 'cloud-certificate-absent'

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

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    try {
        $homeUri = [uri] "https://$hostName/"
        $healthUri = [uri] "https://$hostName/health"
        $notesUri = [uri] "https://$hostName/Notes"

        Invoke-BoundedHttpCheck `
            $client `
            $homeUri `
            { param($response) $response.StatusCode -eq [Net.HttpStatusCode]::OK } `
            'public-home-validation-failed'
        Write-Output 'public-home-valid'

        Invoke-BoundedHttpCheck `
            $client `
            $healthUri `
            { param($response) $response.StatusCode -eq [Net.HttpStatusCode]::OK } `
            'public-health-validation-failed'
        Write-Output 'public-health-valid'

        Invoke-BoundedHttpCheck `
            $client `
            $notesUri `
            {
                param($response)
                if ($response.StatusCode -ne [Net.HttpStatusCode]::Redirect) { return $false }
                $location = $response.Headers.Location
                if ($null -eq $location -or -not $location.IsAbsoluteUri) { return $false }
                return (
                    $location.Scheme -ceq 'https' -and
                    $location.Host -ceq 'login.microsoftonline.com' -and
                    $location.AbsolutePath -match '/oauth2/v2\.0/authorize$'
                )
            } `
            'anonymous-notes-challenge-validation-failed'
        Write-Output 'anonymous-notes-challenge-valid'
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }

    Write-Output 'cloud-application-validation-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'cloud-application-validation-operation-failed' }
    Write-Output "cloud-application-validation-failure-reason:$reason"
    Write-Output 'cloud-application-validation-failed'
    exit 1
}
