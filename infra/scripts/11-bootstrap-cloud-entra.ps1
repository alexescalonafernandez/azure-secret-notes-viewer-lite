#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $WebAppName,

    [Parameter(Mandatory)]
    [string] $CloudAppRegistrationName,

    [Parameter(Mandatory)]
    [string] $LocalDevelopmentAppClientId,

    [Parameter(Mandatory)]
    [string] $DeploymentAppClientId,

    [switch] $Apply
)

. (Join-Path $PSScriptRoot 'cloud-entra-common.ps1')

function Invoke-JsonMutation {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Url,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Document,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $temporaryFile = New-TemporaryFile
    try {
        $json = $Document | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText(
            $temporaryFile.FullName,
            $json,
            [Text.UTF8Encoding]::new($false)
        )
        Invoke-AzureMutation `
            -FailureReason $FailureReason `
            -Arguments @(
                'rest',
                '--method', $Method,
                '--url', $Url,
                '--headers', 'Content-Type=application/json',
                '--body', "@$($temporaryFile.FullName)",
                '--output', 'none',
                '--only-show-errors'
            )
    }
    finally {
        Remove-Item -LiteralPath $temporaryFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

try {
    Assert-PrivateCloudInputs `
        $ResourceGroupName `
        $WebAppName `
        $CloudAppRegistrationName `
        $LocalDevelopmentAppClientId `
        $DeploymentAppClientId
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
    if (
        [string]::Equals($webAppPrincipalId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($webAppPrincipalId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'managed-identity-application-id-reused' }

    $expectedSignInUri = "https://$hostName/signin-oidc"
    $expectedSignOutCallbackUri = "https://$hostName/signout-callback-oidc"
    $expectedFrontChannelLogoutUri = "https://$hostName/signout-oidc"
    $expectedIssuer = "https://login.microsoftonline.com/$tenantId/v2.0"

    $applications = @(Get-CloudApplicationMatches $CloudAppRegistrationName)
    if ($applications.Count -gt 1) { throw 'cloud-application-duplicate' }
    if ($applications.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $roleId = [Guid]::NewGuid().ToString()
        $applicationDocument = [ordered]@{
            displayName = $CloudAppRegistrationName
            signInAudience = 'AzureADMyOrg'
            isFallbackPublicClient = $false
            requiredResourceAccess = @()
            passwordCredentials = @()
            keyCredentials = @()
            appRoles = @(
                [ordered]@{
                    id = $roleId
                    displayName = 'SecretNotes.Reader'
                    description = 'Read the synthetic secret notes catalog.'
                    value = 'SecretNotes.Reader'
                    allowedMemberTypes = @('User')
                    isEnabled = $true
                }
            )
            web = [ordered]@{
                redirectUris = @($expectedSignInUri, $expectedSignOutCallbackUri)
                logoutUrl = $expectedFrontChannelLogoutUri
                implicitGrantSettings = [ordered]@{
                    enableAccessTokenIssuance = $false
                    enableIdTokenIssuance = $false
                }
            }
            spa = [ordered]@{ redirectUris = @() }
            publicClient = [ordered]@{ redirectUris = @() }
        }
        Invoke-JsonMutation `
            -Method 'POST' `
            -Url 'https://graph.microsoft.com/v1.0/applications' `
            -Document $applicationDocument `
            -FailureReason 'cloud-application-create-failed'
        $applications = @(Invoke-BoundedDiscovery `
            -FailureReason 'cloud-application-create-invalid' `
            -Discovery { Get-CloudApplicationMatches $CloudAppRegistrationName } `
            -IsReady { param($state) @($state).Count -eq 1 })
    }

    $applicationObjectId = Get-RequiredStringProperty `
        $applications[0] 'id' 'cloud-application-response-invalid'
    $cloudAppClientId = Get-RequiredStringProperty `
        $applications[0] 'appId' 'cloud-application-response-invalid'
    if (
        [string]::Equals($cloudAppClientId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudAppClientId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudAppClientId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'cloud-identity-reused' }
    $null = Assert-CloudApplicationState `
        $cloudAppClientId `
        $CloudAppRegistrationName `
        $expectedSignInUri `
        $expectedSignOutCallbackUri `
        $expectedFrontChannelLogoutUri
    Write-Output 'cloud-app-registration-valid'
    Write-Output 'cloud-redirect-uris-valid'
    Write-Output 'cloud-app-role-valid'
    Write-Output 'cloud-client-secret-absent'
    Write-Output 'cloud-certificate-absent'

    $servicePrincipals = @(Get-CloudServicePrincipalMatches $cloudAppClientId)
    if ($servicePrincipals.Count -gt 1) { throw 'cloud-service-principal-duplicate' }
    if ($servicePrincipals.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $servicePrincipalDocument = [ordered]@{
            appId = $cloudAppClientId
            accountEnabled = $true
            appRoleAssignmentRequired = $true
            passwordCredentials = @()
            keyCredentials = @()
        }
        Invoke-JsonMutation `
            -Method 'POST' `
            -Url 'https://graph.microsoft.com/v1.0/servicePrincipals' `
            -Document $servicePrincipalDocument `
            -FailureReason 'cloud-service-principal-create-failed'
        $servicePrincipals = @(Invoke-BoundedDiscovery `
            -FailureReason 'cloud-service-principal-create-invalid' `
            -Discovery { Get-CloudServicePrincipalMatches $cloudAppClientId } `
            -IsReady { param($state) @($state).Count -eq 1 })
    }

    $cloudServicePrincipal = Assert-CloudServicePrincipalState $cloudAppClientId
    $cloudServicePrincipalId = Get-RequiredStringProperty `
        $cloudServicePrincipal 'id' 'cloud-service-principal-response-invalid'
    if (
        [string]::Equals($cloudServicePrincipalId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudServicePrincipalId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($cloudServicePrincipalId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'cloud-service-principal-identity-reused' }
    Write-Output 'cloud-enterprise-application-valid'
    Write-Output 'cloud-assignment-required-valid'

    $credentials = @(Get-CloudFederatedCredentials $applicationObjectId)
    if ($credentials.Count -gt 1) { throw 'cloud-federated-credential-count-invalid' }
    if ($credentials.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $credentialFile = New-TemporaryFile
        try {
            $credentialDocument = [ordered]@{
                name = 'web-app-system-assigned-managed-identity'
                issuer = $expectedIssuer
                subject = $webAppPrincipalId
                audiences = @('api://AzureADTokenExchange')
            } | ConvertTo-Json -Depth 5
            [IO.File]::WriteAllText(
                $credentialFile.FullName,
                $credentialDocument,
                [Text.UTF8Encoding]::new($false)
            )
            Invoke-AzureMutation `
                -FailureReason 'cloud-federated-credential-create-failed' `
                -Arguments @(
                    'ad', 'app', 'federated-credential', 'create',
                    '--id', $applicationObjectId,
                    '--parameters', $credentialFile.FullName,
                    '--output', 'none',
                    '--only-show-errors'
                )
        }
        finally {
            Remove-Item -LiteralPath $credentialFile.FullName -Force -ErrorAction SilentlyContinue
        }
        $credentials = @(Invoke-BoundedDiscovery `
            -FailureReason 'cloud-federated-credential-create-invalid' `
            -Discovery { Get-CloudFederatedCredentials $applicationObjectId } `
            -IsReady { param($state) @($state).Count -eq 1 })
    }

    Assert-ExactManagedIdentityFederation $credentials $expectedIssuer $webAppPrincipalId
    Write-Output 'cloud-managed-identity-federation-valid'
    Write-Output 'cloud-identity-separation-valid'
    Write-Output 'cloud-entra-bootstrap-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'cloud-entra-bootstrap-operation-failed' }
    Write-Output "cloud-entra-bootstrap-failure-reason:$reason"
    Write-Output 'cloud-entra-bootstrap-failed'
    exit 1
}
