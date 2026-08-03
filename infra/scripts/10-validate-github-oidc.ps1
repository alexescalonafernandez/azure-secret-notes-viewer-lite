#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $WebAppName,

    [Parameter(Mandatory)]
    [string] $DeploymentAppRegistrationName,

    [Parameter(Mandatory)]
    [string] $LocalDevelopmentAppClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$federatedCredentialName = 'github-dev-environment'
$expectedIssuer = 'https://token.actions.githubusercontent.com'
$expectedSubject = 'repo:alexescalonafernandez/azure-secret-notes-viewer-lite:environment:dev'
$expectedAudience = 'api://AzureADTokenExchange'
$deploymentRoleName = 'Website Contributor'

function ConvertFrom-SanitizedJsonObject {
    param(
        [Parameter(Mandatory)][string[]] $Lines,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $json = $Lines -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) { throw $FailureReason }

    try {
        $result = ConvertFrom-Json -InputObject $json -DateKind String -NoEnumerate
    }
    catch {
        throw $FailureReason
    }

    if (
        $null -eq $result -or
        $result -is [System.Array] -or
        $result -isnot [psobject]
    ) { throw $FailureReason }

    return $result
}

function ConvertFrom-SanitizedJsonArray {
    param(
        [Parameter(Mandatory)][string[]] $Lines,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $json = $Lines -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) { throw $FailureReason }

    try {
        $result = ConvertFrom-Json -InputObject $json -DateKind String -NoEnumerate
    }
    catch {
        throw $FailureReason
    }

    if ($null -eq $result -or $result -isnot [System.Array]) {
        throw $FailureReason
    }

    Write-Output -NoEnumerate $result
}

function Invoke-AzureJsonObject {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $lines = @(& az @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw $FailureReason }
    return ConvertFrom-SanitizedJsonObject -Lines $lines -FailureReason $FailureReason
}

function Invoke-AzureJsonArray {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $lines = @(& az @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw $FailureReason }
    return ConvertFrom-SanitizedJsonArray -Lines $lines -FailureReason $FailureReason
}

function Get-RequiredStringProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $property = $Object.PSObject.Properties[$Name]
    if (
        $null -eq $property -or
        $property.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string] $property.Value)
    ) { throw $FailureReason }

    return [string] $property.Value
}

function Assert-PrivateInputs {
    if (
        $ResourceGroupName -notmatch '^[A-Za-z0-9_.()-]{1,90}$' -or
        $WebAppName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{1,58}[A-Za-z0-9]$' -or
        $DeploymentAppRegistrationName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{1,118}[A-Za-z0-9]$'
    ) { throw 'private-input-invalid' }

    $parsedClientId = [Guid]::Empty
    if (-not [Guid]::TryParse($LocalDevelopmentAppClientId, [ref] $parsedClientId)) {
        throw 'local-development-identity-input-invalid'
    }
}

try {
    Assert-PrivateInputs
    if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'azure-cli-unavailable'
    }

    $account = Invoke-AzureJsonObject `
        -FailureReason 'subscription-context-invalid' `
        -Arguments @(
            'account', 'show',
            '--query', '{id:id,tenantId:tenantId}',
            '--output', 'json',
            '--only-show-errors'
        )
    $subscriptionId = Get-RequiredStringProperty $account 'id' 'subscription-context-invalid'
    $tenantId = Get-RequiredStringProperty $account 'tenantId' 'subscription-context-invalid'
    $parsedSubscriptionId = [Guid]::Empty
    $parsedTenantId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($subscriptionId, [ref] $parsedSubscriptionId) -or
        -not [Guid]::TryParse($tenantId, [ref] $parsedTenantId)
    ) { throw 'subscription-context-invalid' }

    $expectedWebAppScope = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}' -f `
        $subscriptionId, $ResourceGroupName, $WebAppName
    $webApp = Invoke-AzureJsonObject `
        -FailureReason 'web-app-response-invalid' `
        -Arguments @(
            'webapp', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $WebAppName,
            '--subscription', $subscriptionId,
            '--query', '{id:id,type:type,identityType:identity.type,principalId:identity.principalId}',
            '--output', 'json',
            '--only-show-errors'
        )
    $webAppScope = Get-RequiredStringProperty $webApp 'id' 'web-app-response-invalid'
    $webAppType = Get-RequiredStringProperty $webApp 'type' 'web-app-response-invalid'
    $webAppIdentityType = Get-RequiredStringProperty $webApp 'identityType' 'web-app-response-invalid'
    $webAppPrincipalId = Get-RequiredStringProperty $webApp 'principalId' 'web-app-response-invalid'
    $parsedWebAppPrincipalId = [Guid]::Empty
    if (
        -not [string]::Equals($webAppScope, $expectedWebAppScope, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($webAppType, 'Microsoft.Web/sites', [StringComparison]::OrdinalIgnoreCase) -or
        $webAppIdentityType -notmatch '(^|,)SystemAssigned($|,)' -or
        -not [Guid]::TryParse($webAppPrincipalId, [ref] $parsedWebAppPrincipalId)
    ) { throw 'web-app-response-invalid' }

    $applications = Invoke-AzureJsonArray `
        -FailureReason 'application-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'list',
            '--display-name', $DeploymentAppRegistrationName,
            '--query', '[].{id:id,appId:appId,displayName:displayName}',
            '--output', 'json',
            '--only-show-errors'
        )
    $applicationMatches = @()
    foreach ($application in $applications) {
        if ($null -eq $application -or $application -isnot [psobject]) {
            throw 'application-list-response-invalid'
        }
        $id = Get-RequiredStringProperty $application 'id' 'application-list-response-invalid'
        $appId = Get-RequiredStringProperty $application 'appId' 'application-list-response-invalid'
        $displayName = Get-RequiredStringProperty $application 'displayName' 'application-list-response-invalid'
        $parsedId = [Guid]::Empty
        $parsedAppId = [Guid]::Empty
        if (
            -not [Guid]::TryParse($id, [ref] $parsedId) -or
            -not [Guid]::TryParse($appId, [ref] $parsedAppId)
        ) { throw 'application-list-response-invalid' }
        if ([string]::Equals(
            $displayName,
            $DeploymentAppRegistrationName,
            [StringComparison]::Ordinal
        )) { $applicationMatches += $application }
    }
    if ($applicationMatches.Count -ne 1) { throw 'deployment-application-count-invalid' }

    $applicationObjectId = Get-RequiredStringProperty `
        $applicationMatches[0] 'id' 'application-response-invalid'
    $appId = Get-RequiredStringProperty `
        $applicationMatches[0] 'appId' 'application-response-invalid'
    if ([string]::Equals(
        $appId,
        $LocalDevelopmentAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'local-development-identity-reused' }

    $applicationState = Invoke-AzureJsonObject `
        -FailureReason 'application-response-invalid' `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $appId,
            '--query', '{id:id,appId:appId,displayName:displayName,passwordCredentials:passwordCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )
    $resolvedAppId = Get-RequiredStringProperty $applicationState 'appId' 'application-response-invalid'
    $resolvedDisplayName = Get-RequiredStringProperty $applicationState 'displayName' 'application-response-invalid'
    $passwordCredentialsProperty = $applicationState.PSObject.Properties['passwordCredentials']
    if (
        -not [string]::Equals($resolvedAppId, $appId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($resolvedDisplayName, $DeploymentAppRegistrationName, [StringComparison]::Ordinal) -or
        $null -eq $passwordCredentialsProperty -or
        $passwordCredentialsProperty.Value -isnot [System.Array]
    ) { throw 'application-response-invalid' }
    if (@($passwordCredentialsProperty.Value).Count -ne 0) {
        throw 'deployment-client-secret-present'
    }
    Write-Output 'github-deployment-app-valid'
    Write-Output 'deployment-client-secret-absent'

    $servicePrincipals = Invoke-AzureJsonArray `
        -FailureReason 'service-principal-list-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'list',
            '--filter', "appId eq '$appId'",
            '--query', '[].{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($servicePrincipals.Count -ne 1) { throw 'deployment-service-principal-count-invalid' }
    $servicePrincipalObjectId = Get-RequiredStringProperty `
        $servicePrincipals[0] 'id' 'service-principal-response-invalid'
    $servicePrincipalAppId = Get-RequiredStringProperty `
        $servicePrincipals[0] 'appId' 'service-principal-response-invalid'
    $servicePrincipalType = Get-RequiredStringProperty `
        $servicePrincipals[0] 'servicePrincipalType' 'service-principal-response-invalid'
    $parsedServicePrincipalId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($servicePrincipalObjectId, [ref] $parsedServicePrincipalId) -or
        -not [string]::Equals($servicePrincipalAppId, $appId, [StringComparison]::OrdinalIgnoreCase) -or
        $servicePrincipalType -cne 'Application' -or
        [string]::Equals($servicePrincipalObjectId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'deployment-service-principal-invalid' }
    Write-Output 'github-deployment-service-principal-valid'
    Write-Output 'deployment-runtime-identity-separation-valid'

    $credentials = Invoke-AzureJsonArray `
        -FailureReason 'federated-credential-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'federated-credential', 'list',
            '--id', $applicationObjectId,
            '--query', '[].{name:name,issuer:issuer,subject:subject,audiences:audiences}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($credentials.Count -ne 1) { throw 'federated-credential-count-invalid' }
    $credential = $credentials[0]
    $credentialName = Get-RequiredStringProperty $credential 'name' 'federated-credential-response-invalid'
    $issuer = Get-RequiredStringProperty $credential 'issuer' 'federated-credential-response-invalid'
    $subject = Get-RequiredStringProperty $credential 'subject' 'federated-credential-response-invalid'
    $audiencesProperty = $credential.PSObject.Properties['audiences']
    if (
        $null -eq $audiencesProperty -or
        $audiencesProperty.Value -isnot [System.Array]
    ) { throw 'federated-credential-response-invalid' }
    $audiences = @($audiencesProperty.Value)
    if (
        $credentialName -cne $federatedCredentialName -or
        $issuer -cne $expectedIssuer -or
        $subject -cne $expectedSubject -or
        $audiences.Count -ne 1 -or
        $audiences[0] -isnot [string] -or
        $audiences[0] -cne $expectedAudience
    ) { throw 'federated-credential-mismatch' }
    Write-Output 'github-federated-credential-valid'
    Write-Output 'github-oidc-subject-valid'

    $roles = Invoke-AzureJsonArray `
        -FailureReason 'role-definition-response-invalid' `
        -Arguments @(
            'role', 'definition', 'list',
            '--name', $deploymentRoleName,
            '--query', '[].{id:id,roleName:roleName}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($roles.Count -ne 1) { throw 'website-contributor-role-invalid' }
    $roleDefinitionId = Get-RequiredStringProperty $roles[0] 'id' 'role-definition-response-invalid'
    $roleName = Get-RequiredStringProperty $roles[0] 'roleName' 'role-definition-response-invalid'
    if ($roleName -cne $deploymentRoleName) { throw 'website-contributor-role-invalid' }

    $assignments = Invoke-AzureJsonArray `
        -FailureReason 'role-assignment-response-invalid' `
        -Arguments @(
            'role', 'assignment', 'list',
            '--assignee-object-id', $servicePrincipalObjectId,
            '--all',
            '--fill-principal-name', 'false',
            '--fill-role-definition-name', 'false',
            '--subscription', $subscriptionId,
            '--query', '[].{principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($assignments.Count -ne 1) { throw 'deployment-role-state-invalid' }
    $assignmentPrincipalId = Get-RequiredStringProperty `
        $assignments[0] 'principalId' 'role-assignment-response-invalid'
    $assignmentRoleDefinitionId = Get-RequiredStringProperty `
        $assignments[0] 'roleDefinitionId' 'role-assignment-response-invalid'
    $assignmentScope = Get-RequiredStringProperty `
        $assignments[0] 'scope' 'role-assignment-response-invalid'
    if (
        -not [string]::Equals($assignmentPrincipalId, $servicePrincipalObjectId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($assignmentRoleDefinitionId, $roleDefinitionId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($assignmentScope, $webAppScope, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'deployment-role-state-invalid' }

    Write-Output 'website-contributor-valid'
    Write-Output 'deployment-scope-valid'
    Write-Output 'deployment-broader-rbac-absent'
    Write-Output 'deployment-key-vault-rbac-absent'
    Write-Output 'github-oidc-validation-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'validation-operation-failed' }
    Write-Output "github-oidc-validation-failure-reason:$reason"
    Write-Output 'github-oidc-validation-failed'
    exit 1
}
