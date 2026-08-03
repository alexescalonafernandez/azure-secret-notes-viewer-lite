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

function Get-RequiredObjectProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $property = $Object.PSObject.Properties[$Name]
    if (
        $null -eq $property -or
        $null -eq $property.Value -or
        $property.Value -is [System.Array] -or
        $property.Value -isnot [psobject]
    ) { throw $FailureReason }

    return $property.Value
}

function Get-RequiredBooleanProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [bool]) {
        throw $FailureReason
    }

    return [bool] $property.Value
}

function Assert-EmptyArrayProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason,
        [Parameter(Mandatory)][string] $NonEmptyFailureReason
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [System.Array]) {
        throw $FailureReason
    }
    if (@($property.Value).Count -ne 0) { throw $NonEmptyFailureReason }
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

function Assert-LocalDevelopmentApplication {
    $application = Invoke-AzureJsonObject `
        -FailureReason 'local-development-application-response-invalid' `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $LocalDevelopmentAppClientId,
            '--query', '{appId:appId}',
            '--output', 'json',
            '--only-show-errors'
        )

    $resolvedAppId = Get-RequiredStringProperty `
        $application 'appId' 'local-development-application-response-invalid'
    $parsedAppId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($resolvedAppId, [ref] $parsedAppId) -or
        -not [string]::Equals(
            $resolvedAppId,
            $LocalDevelopmentAppClientId,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) { throw 'local-development-application-response-invalid' }
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

    Assert-LocalDevelopmentApplication

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
            '--query', '{id:id,appId:appId,displayName:displayName,signInAudience:signInAudience,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials,requiredResourceAccess:requiredResourceAccess,web:web,spa:spa,publicClient:publicClient}',
            '--output', 'json',
            '--only-show-errors'
        )
    $resolvedObjectId = Get-RequiredStringProperty `
        $applicationState 'id' 'application-response-invalid'
    $resolvedAppId = Get-RequiredStringProperty $applicationState 'appId' 'application-response-invalid'
    $resolvedDisplayName = Get-RequiredStringProperty $applicationState 'displayName' 'application-response-invalid'
    $signInAudience = Get-RequiredStringProperty `
        $applicationState 'signInAudience' 'deployment-application-configuration-invalid'
    $parsedResolvedObjectId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($resolvedObjectId, [ref] $parsedResolvedObjectId) -or
        -not [string]::Equals($resolvedObjectId, $applicationObjectId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($resolvedAppId, $appId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($resolvedDisplayName, $DeploymentAppRegistrationName, [StringComparison]::Ordinal) -or
        $signInAudience -cne 'AzureADMyOrg'
    ) { throw 'application-response-invalid' }
    Assert-EmptyArrayProperty $applicationState 'passwordCredentials' `
        'deployment-application-password-credentials-invalid' `
        'deployment-application-password-credential-present'
    Assert-EmptyArrayProperty $applicationState 'keyCredentials' `
        'deployment-application-key-credentials-invalid' `
        'deployment-application-key-credential-present'
    Assert-EmptyArrayProperty $applicationState 'requiredResourceAccess' `
        'deployment-required-resource-access-invalid' `
        'deployment-required-resource-access-present'

    $web = Get-RequiredObjectProperty `
        $applicationState 'web' 'deployment-web-configuration-invalid'
    $spa = Get-RequiredObjectProperty `
        $applicationState 'spa' 'deployment-spa-configuration-invalid'
    $publicClient = Get-RequiredObjectProperty `
        $applicationState 'publicClient' 'deployment-public-client-configuration-invalid'
    Assert-EmptyArrayProperty $web 'redirectUris' `
        'deployment-web-redirect-uris-invalid' 'deployment-web-redirect-uri-present'
    Assert-EmptyArrayProperty $spa 'redirectUris' `
        'deployment-spa-redirect-uris-invalid' 'deployment-spa-redirect-uri-present'
    Assert-EmptyArrayProperty $publicClient 'redirectUris' `
        'deployment-public-client-redirect-uris-invalid' `
        'deployment-public-client-redirect-uri-present'
    Write-Output 'github-deployment-app-valid'
    Write-Output 'deployment-application-credentials-absent'

    $servicePrincipals = Invoke-AzureJsonArray `
        -FailureReason 'service-principal-list-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'list',
            '--filter', "appId eq '$appId'",
            '--query', '[].{id:id,appId:appId}',
            '--output', 'json',
            '--only-show-errors'
        )
    if ($servicePrincipals.Count -ne 1) { throw 'deployment-service-principal-count-invalid' }

    $servicePrincipalState = Invoke-AzureJsonObject `
        -FailureReason 'service-principal-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $appId,
            '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType,accountEnabled:accountEnabled,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )
    $servicePrincipalObjectId = Get-RequiredStringProperty `
        $servicePrincipalState 'id' 'service-principal-response-invalid'
    $servicePrincipalAppId = Get-RequiredStringProperty `
        $servicePrincipalState 'appId' 'service-principal-response-invalid'
    $servicePrincipalType = Get-RequiredStringProperty `
        $servicePrincipalState 'servicePrincipalType' 'service-principal-response-invalid'
    $servicePrincipalAccountEnabled = Get-RequiredBooleanProperty `
        $servicePrincipalState 'accountEnabled' 'service-principal-response-invalid'
    $parsedServicePrincipalId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($servicePrincipalObjectId, [ref] $parsedServicePrincipalId) -or
        -not [string]::Equals($servicePrincipalAppId, $appId, [StringComparison]::OrdinalIgnoreCase) -or
        $servicePrincipalType -cne 'Application' -or
        -not $servicePrincipalAccountEnabled -or
        [string]::Equals($servicePrincipalObjectId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'deployment-service-principal-invalid' }
    Assert-EmptyArrayProperty $servicePrincipalState 'passwordCredentials' `
        'service-principal-password-credentials-invalid' `
        'service-principal-password-credential-present'
    Assert-EmptyArrayProperty $servicePrincipalState 'keyCredentials' `
        'service-principal-key-credentials-invalid' `
        'service-principal-key-credential-present'
    Write-Output 'github-deployment-service-principal-valid'
    Write-Output 'deployment-service-principal-credentials-absent'
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
