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
    [string] $CloudAppRegistrationName,

    [Parameter(Mandatory)]
    [string] $LocalDevelopmentAppClientId,

    [Parameter(Mandatory)]
    [string] $DeploymentAppClientId
)

. (Join-Path $PSScriptRoot 'cloud-entra-common.ps1')

try {
    Assert-PrivateCloudInputs `
        $ResourceGroupName `
        $WebAppName `
        $CloudAppRegistrationName `
        $LocalDevelopmentAppClientId `
        $DeploymentAppClientId
    if ($KeyVaultName -notmatch '^[A-Za-z0-9-]{3,24}$') {
        throw 'key-vault-input-invalid'
    }
    if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'azure-cli-unavailable'
    }

    $context = Get-AzureContext
    $subscriptionId = Get-RequiredStringProperty $context 'id' 'subscription-context-invalid'
    $tenantId = Get-RequiredStringProperty $context 'tenantId' 'subscription-context-invalid'
    $webApp = Get-ExistingWebAppState $ResourceGroupName $WebAppName $subscriptionId
    $webAppPrincipalId = Get-RequiredStringProperty $webApp 'principalId' 'web-app-response-invalid'
    $hostName = Get-RequiredStringProperty $webApp 'defaultHostName' 'web-app-response-invalid'

    Assert-IdentityApplication `
        $LocalDevelopmentAppClientId `
        'local-development-application-response-invalid'
    Assert-IdentityApplication `
        $DeploymentAppClientId `
        'deployment-application-response-invalid'

    $applications = @(Get-CloudApplicationMatches $CloudAppRegistrationName)
    if ($applications.Count -ne 1) { throw 'cloud-application-count-invalid' }
    $applicationObjectId = Get-RequiredStringProperty `
        $applications[0] 'id' 'cloud-application-response-invalid'
    $cloudAppClientId = Get-RequiredStringProperty `
        $applications[0] 'appId' 'cloud-application-response-invalid'
    if (
        [string]::Equals($cloudAppClientId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudAppClientId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudAppClientId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($webAppPrincipalId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($webAppPrincipalId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'cloud-identity-reused' }

    $expectedSignInUri = "https://$hostName/signin-oidc"
    $expectedSignOutCallbackUri = "https://$hostName/signout-callback-oidc"
    $expectedFrontChannelLogoutUri = "https://$hostName/signout-oidc"
    $expectedIssuer = "https://login.microsoftonline.com/$tenantId/v2.0"
    $null = Assert-CloudApplicationState `
        $cloudAppClientId `
        $CloudAppRegistrationName `
        $expectedSignInUri `
        $expectedSignOutCallbackUri `
        $expectedFrontChannelLogoutUri
    Write-Output 'cloud-app-registration-valid'
    Write-Output 'cloud-redirect-uris-valid'
    Write-Output 'cloud-logout-valid'
    Write-Output 'cloud-app-role-valid'
    Write-Output 'cloud-client-secret-absent'
    Write-Output 'cloud-certificate-absent'
    Write-Output 'cloud-api-permissions-absent'

    $servicePrincipals = @(Get-CloudServicePrincipalMatches $cloudAppClientId)
    if ($servicePrincipals.Count -ne 1) { throw 'cloud-service-principal-count-invalid' }
    $cloudServicePrincipal = Assert-CloudServicePrincipalState $cloudAppClientId
    $cloudServicePrincipalId = Get-RequiredStringProperty `
        $cloudServicePrincipal 'id' 'cloud-service-principal-response-invalid'
    if ([string]::Equals(
        $cloudServicePrincipalId,
        $webAppPrincipalId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'cloud-service-principal-managed-identity-reused' }
    Write-Output 'cloud-enterprise-application-valid'
    Write-Output 'cloud-assignment-required-valid'

    $credentials = @(Get-CloudFederatedCredentials $applicationObjectId)
    Assert-ExactManagedIdentityFederation $credentials $expectedIssuer $webAppPrincipalId
    Write-Output 'cloud-managed-identity-federation-valid'
    Write-Output 'cloud-identity-separation-valid'

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
    Assert-NoDirectKeyVaultRole `
        $webAppPrincipalId `
        $vaultId `
        $subscriptionId `
        'web-app-key-vault-rbac-present'
    Write-Output 'web-app-key-vault-rbac-absent'
    Write-Output 'cloud-entra-validation-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'cloud-entra-validation-operation-failed' }
    Write-Output "cloud-entra-validation-failure-reason:$reason"
    Write-Output 'cloud-entra-validation-failed'
    exit 1
}
