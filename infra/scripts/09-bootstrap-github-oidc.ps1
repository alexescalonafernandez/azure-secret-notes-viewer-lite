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
    [string] $LocalDevelopmentAppClientId,

    [switch] $Apply
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

function Invoke-AzureMutation {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $null = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw $FailureReason }
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

function Get-ApplicationMatches {
    $applications = Invoke-AzureJsonArray `
        -FailureReason 'application-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'list',
            '--display-name', $DeploymentAppRegistrationName,
            '--query', '[].{id:id,appId:appId,displayName:displayName}',
            '--output', 'json',
            '--only-show-errors'
        )

    $matches = @()
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
        )) { $matches += $application }
    }

    Write-Output -NoEnumerate $matches
}

function Get-ApplicationState {
    param([Parameter(Mandatory)][string] $AppId)

    $application = Invoke-AzureJsonObject `
        -FailureReason 'application-response-invalid' `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $AppId,
            '--query', '{id:id,appId:appId,displayName:displayName,passwordCredentials:passwordCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )

    $resolvedAppId = Get-RequiredStringProperty $application 'appId' 'application-response-invalid'
    $displayName = Get-RequiredStringProperty $application 'displayName' 'application-response-invalid'
    $passwordCredentialsProperty = $application.PSObject.Properties['passwordCredentials']
    if (
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($displayName, $DeploymentAppRegistrationName, [StringComparison]::Ordinal) -or
        $null -eq $passwordCredentialsProperty -or
        $passwordCredentialsProperty.Value -isnot [System.Array]
    ) { throw 'application-response-invalid' }

    if (@($passwordCredentialsProperty.Value).Count -ne 0) {
        throw 'deployment-client-secret-present'
    }

    return $application
}

function Get-ServicePrincipalMatches {
    param([Parameter(Mandatory)][string] $AppId)

    $servicePrincipals = Invoke-AzureJsonArray `
        -FailureReason 'service-principal-list-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'list',
            '--filter', "appId eq '$AppId'",
            '--query', '[].{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
            '--output', 'json',
            '--only-show-errors'
        )

    $matches = @()
    foreach ($servicePrincipal in $servicePrincipals) {
        if ($null -eq $servicePrincipal -or $servicePrincipal -isnot [psobject]) {
            throw 'service-principal-list-response-invalid'
        }

        $id = Get-RequiredStringProperty $servicePrincipal 'id' 'service-principal-list-response-invalid'
        $resolvedAppId = Get-RequiredStringProperty $servicePrincipal 'appId' 'service-principal-list-response-invalid'
        $type = Get-RequiredStringProperty $servicePrincipal 'servicePrincipalType' 'service-principal-list-response-invalid'
        $parsedId = [Guid]::Empty
        if (
            -not [Guid]::TryParse($id, [ref] $parsedId) -or
            -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
            $type -cne 'Application'
        ) { throw 'service-principal-list-response-invalid' }

        $matches += $servicePrincipal
    }

    Write-Output -NoEnumerate $matches
}

function Get-FederatedCredentials {
    param([Parameter(Mandatory)][string] $ApplicationObjectId)

    $credentials = Invoke-AzureJsonArray `
        -FailureReason 'federated-credential-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'federated-credential', 'list',
            '--id', $ApplicationObjectId,
            '--query', '[].{name:name,issuer:issuer,subject:subject,audiences:audiences}',
            '--output', 'json',
            '--only-show-errors'
        )

    foreach ($credential in $credentials) {
        if ($null -eq $credential -or $credential -isnot [psobject]) {
            throw 'federated-credential-list-response-invalid'
        }

        $null = Get-RequiredStringProperty $credential 'name' 'federated-credential-list-response-invalid'
        $null = Get-RequiredStringProperty $credential 'issuer' 'federated-credential-list-response-invalid'
        $null = Get-RequiredStringProperty $credential 'subject' 'federated-credential-list-response-invalid'
        $audiencesProperty = $credential.PSObject.Properties['audiences']
        if (
            $null -eq $audiencesProperty -or
            $audiencesProperty.Value -isnot [System.Array]
        ) { throw 'federated-credential-list-response-invalid' }
        foreach ($audience in @($audiencesProperty.Value)) {
            if ($audience -isnot [string] -or [string]::IsNullOrWhiteSpace($audience)) {
                throw 'federated-credential-list-response-invalid'
            }
        }
    }

    Write-Output -NoEnumerate $credentials
}

function Assert-FederatedCredential {
    param([Parameter(Mandatory)][psobject] $Credential)

    $name = Get-RequiredStringProperty $Credential 'name' 'federated-credential-invalid'
    $issuer = Get-RequiredStringProperty $Credential 'issuer' 'federated-credential-invalid'
    $subject = Get-RequiredStringProperty $Credential 'subject' 'federated-credential-invalid'
    $audiences = @($Credential.PSObject.Properties['audiences'].Value)
    if (
        $name -cne $federatedCredentialName -or
        $issuer -cne $expectedIssuer -or
        $subject -cne $expectedSubject -or
        $audiences.Count -ne 1 -or
        $audiences[0] -cne $expectedAudience
    ) { throw 'federated-credential-mismatch' }
}

function Get-DeploymentRoleDefinition {
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
    $role = $roles[0]
    $null = Get-RequiredStringProperty $role 'id' 'role-definition-response-invalid'
    $roleName = Get-RequiredStringProperty $role 'roleName' 'role-definition-response-invalid'
    if ($roleName -cne $deploymentRoleName) { throw 'website-contributor-role-invalid' }
    return $role
}

function Get-DeploymentRoleAssignments {
    param([Parameter(Mandatory)][string] $ServicePrincipalObjectId)

    $assignments = Invoke-AzureJsonArray `
        -FailureReason 'role-assignment-response-invalid' `
        -Arguments @(
            'role', 'assignment', 'list',
            '--assignee-object-id', $ServicePrincipalObjectId,
            '--all',
            '--fill-principal-name', 'false',
            '--fill-role-definition-name', 'false',
            '--subscription', $script:subscriptionId,
            '--query', '[].{principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}',
            '--output', 'json',
            '--only-show-errors'
        )

    foreach ($assignment in $assignments) {
        if ($null -eq $assignment -or $assignment -isnot [psobject]) {
            throw 'role-assignment-response-invalid'
        }

        $principalId = Get-RequiredStringProperty $assignment 'principalId' 'role-assignment-response-invalid'
        $null = Get-RequiredStringProperty $assignment 'roleDefinitionId' 'role-assignment-response-invalid'
        $null = Get-RequiredStringProperty $assignment 'scope' 'role-assignment-response-invalid'
        if (-not [string]::Equals(
            $principalId,
            $ServicePrincipalObjectId,
            [StringComparison]::OrdinalIgnoreCase
        )) { throw 'role-assignment-response-invalid' }
    }

    Write-Output -NoEnumerate $assignments
}

function Test-ExpectedRoleAssignment {
    param(
        [Parameter(Mandatory)][psobject] $Assignment,
        [Parameter(Mandatory)][string] $RoleDefinitionId,
        [Parameter(Mandatory)][string] $WebAppScope
    )

    return (
        [string]::Equals(
            [string] $Assignment.roleDefinitionId,
            $RoleDefinitionId,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [string]::Equals(
            [string] $Assignment.scope,
            $WebAppScope,
            [StringComparison]::OrdinalIgnoreCase
        )
    )
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

    $applications = Get-ApplicationMatches
    if ($applications.Count -gt 1) { throw 'deployment-application-duplicate' }
    if ($applications.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'github-oidc-apply-required'
            return
        }

        Invoke-AzureMutation `
            -FailureReason 'deployment-application-create-failed' `
            -Arguments @(
                'ad', 'app', 'create',
                '--display-name', $DeploymentAppRegistrationName,
                '--sign-in-audience', 'AzureADMyOrg',
                '--output', 'none',
                '--only-show-errors'
            )
        $applications = Get-ApplicationMatches
        if ($applications.Count -ne 1) { throw 'deployment-application-create-invalid' }
    }

    $applicationObjectId = Get-RequiredStringProperty $applications[0] 'id' 'application-response-invalid'
    $appId = Get-RequiredStringProperty $applications[0] 'appId' 'application-response-invalid'
    $null = Get-ApplicationState -AppId $appId
    if ([string]::Equals(
        $appId,
        $LocalDevelopmentAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'local-development-identity-reused' }
    Write-Output 'github-deployment-app-valid'

    $servicePrincipals = Get-ServicePrincipalMatches -AppId $appId
    if ($servicePrincipals.Count -gt 1) { throw 'deployment-service-principal-duplicate' }
    if ($servicePrincipals.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'github-oidc-apply-required'
            return
        }

        Invoke-AzureMutation `
            -FailureReason 'deployment-service-principal-create-failed' `
            -Arguments @(
                'ad', 'sp', 'create',
                '--id', $appId,
                '--output', 'none',
                '--only-show-errors'
            )
        $servicePrincipals = Get-ServicePrincipalMatches -AppId $appId
        if ($servicePrincipals.Count -ne 1) {
            throw 'deployment-service-principal-create-invalid'
        }
    }

    $servicePrincipalObjectId = Get-RequiredStringProperty `
        $servicePrincipals[0] 'id' 'service-principal-response-invalid'
    if ([string]::Equals(
        $servicePrincipalObjectId,
        $webAppPrincipalId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'web-app-managed-identity-reused' }
    Write-Output 'github-deployment-service-principal-valid'

    $credentials = Get-FederatedCredentials -ApplicationObjectId $applicationObjectId
    $namedCredentials = @($credentials | Where-Object { $_.name -ceq $federatedCredentialName })
    if ($namedCredentials.Count -gt 1) { throw 'federated-credential-duplicate' }
    if ($namedCredentials.Count -eq 1) {
        Assert-FederatedCredential -Credential $namedCredentials[0]
    }
    else {
        if ($credentials.Count -ne 0) { throw 'unexpected-federated-credential-present' }
        if (-not $Apply) {
            Write-Output 'github-oidc-apply-required'
            return
        }

        $temporaryCredentialFile = New-TemporaryFile
        try {
            $credentialDocument = [ordered]@{
                name = $federatedCredentialName
                issuer = $expectedIssuer
                subject = $expectedSubject
                audiences = @($expectedAudience)
            } | ConvertTo-Json -Depth 4
            [IO.File]::WriteAllText(
                $temporaryCredentialFile.FullName,
                $credentialDocument,
                [Text.UTF8Encoding]::new($false)
            )

            Invoke-AzureMutation `
                -FailureReason 'federated-credential-create-failed' `
                -Arguments @(
                    'ad', 'app', 'federated-credential', 'create',
                    '--id', $applicationObjectId,
                    '--parameters', $temporaryCredentialFile.FullName,
                    '--output', 'none',
                    '--only-show-errors'
                )
        }
        finally {
            Remove-Item -LiteralPath $temporaryCredentialFile.FullName -Force -ErrorAction SilentlyContinue
        }

        $credentials = Get-FederatedCredentials -ApplicationObjectId $applicationObjectId
        if ($credentials.Count -ne 1) { throw 'federated-credential-create-invalid' }
        Assert-FederatedCredential -Credential $credentials[0]
    }
    if ($credentials.Count -ne 1) { throw 'federated-credential-set-invalid' }
    Write-Output 'github-federated-credential-valid'
    Write-Output 'github-oidc-subject-valid'

    $roleDefinition = Get-DeploymentRoleDefinition
    $roleDefinitionId = Get-RequiredStringProperty `
        $roleDefinition 'id' 'role-definition-response-invalid'
    $assignments = Get-DeploymentRoleAssignments `
        -ServicePrincipalObjectId $servicePrincipalObjectId
    $expectedAssignments = @($assignments | Where-Object {
        Test-ExpectedRoleAssignment $_ $roleDefinitionId $webAppScope
    })
    if ($expectedAssignments.Count -gt 1) { throw 'deployment-role-assignment-duplicate' }
    if ($assignments.Count -ne $expectedAssignments.Count) {
        throw 'unexpected-deployment-role-assignment-present'
    }

    if ($expectedAssignments.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'github-oidc-apply-required'
            return
        }

        Invoke-AzureMutation `
            -FailureReason 'deployment-role-assignment-create-failed' `
            -Arguments @(
                'role', 'assignment', 'create',
                '--assignee-object-id', $servicePrincipalObjectId,
                '--assignee-principal-type', 'ServicePrincipal',
                '--role', $roleDefinitionId,
                '--scope', $webAppScope,
                '--subscription', $subscriptionId,
                '--output', 'none',
                '--only-show-errors'
            )

        $assignments = Get-DeploymentRoleAssignments `
            -ServicePrincipalObjectId $servicePrincipalObjectId
        $expectedAssignments = @($assignments | Where-Object {
            Test-ExpectedRoleAssignment $_ $roleDefinitionId $webAppScope
        })
    }

    if ($assignments.Count -ne 1 -or $expectedAssignments.Count -ne 1) {
        throw 'deployment-role-state-invalid'
    }

    Write-Output 'website-contributor-valid'
    Write-Output 'deployment-scope-valid'
    Write-Output 'deployment-key-vault-rbac-absent'
    Write-Output 'github-oidc-bootstrap-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') { $reason = 'bootstrap-operation-failed' }
    Write-Output "github-oidc-bootstrap-failure-reason:$reason"
    Write-Output 'github-oidc-bootstrap-failed'
    exit 1
}
