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

function Invoke-BoundedDiscovery {
    param(
        [Parameter(Mandatory)][scriptblock] $Discovery,
        [Parameter(Mandatory)][scriptblock] $IsReady,
        [Parameter(Mandatory)][string] $FailureReason,
        [ValidateRange(1, 20)][int] $MaxAttempts = 6,
        [ValidateRange(1, 60)][int] $DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $state = & $Discovery
            if (& $IsReady $state) {
                Write-Output $state
                return
            }
        }
        catch {
            if ($attempt -eq $MaxAttempts) { throw $FailureReason }
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    throw $FailureReason
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
            '--query', '{id:id,appId:appId,displayName:displayName,signInAudience:signInAudience,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials,requiredResourceAccess:requiredResourceAccess,web:web,spa:spa,publicClient:publicClient}',
            '--output', 'json',
            '--only-show-errors'
        )

    $objectId = Get-RequiredStringProperty $application 'id' 'application-response-invalid'
    $resolvedAppId = Get-RequiredStringProperty $application 'appId' 'application-response-invalid'
    $displayName = Get-RequiredStringProperty $application 'displayName' 'application-response-invalid'
    $signInAudience = Get-RequiredStringProperty `
        $application 'signInAudience' 'deployment-application-configuration-invalid'
    $parsedObjectId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($objectId, [ref] $parsedObjectId) -or
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($displayName, $DeploymentAppRegistrationName, [StringComparison]::Ordinal) -or
        $signInAudience -cne 'AzureADMyOrg'
    ) { throw 'application-response-invalid' }

    Assert-EmptyArrayProperty $application 'passwordCredentials' `
        'deployment-application-password-credentials-invalid' `
        'deployment-application-password-credential-present'
    Assert-EmptyArrayProperty $application 'keyCredentials' `
        'deployment-application-key-credentials-invalid' `
        'deployment-application-key-credential-present'
    Assert-EmptyArrayProperty $application 'requiredResourceAccess' `
        'deployment-required-resource-access-invalid' `
        'deployment-required-resource-access-present'

    $web = Get-RequiredObjectProperty `
        $application 'web' 'deployment-web-configuration-invalid'
    $spa = Get-RequiredObjectProperty `
        $application 'spa' 'deployment-spa-configuration-invalid'
    $publicClient = Get-RequiredObjectProperty `
        $application 'publicClient' 'deployment-public-client-configuration-invalid'
    Assert-EmptyArrayProperty $web 'redirectUris' `
        'deployment-web-redirect-uris-invalid' 'deployment-web-redirect-uri-present'
    Assert-EmptyArrayProperty $spa 'redirectUris' `
        'deployment-spa-redirect-uris-invalid' 'deployment-spa-redirect-uri-present'
    Assert-EmptyArrayProperty $publicClient 'redirectUris' `
        'deployment-public-client-redirect-uris-invalid' `
        'deployment-public-client-redirect-uri-present'

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

function Get-ServicePrincipalState {
    param([Parameter(Mandatory)][string] $AppId)

    $servicePrincipal = Invoke-AzureJsonObject `
        -FailureReason 'service-principal-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $AppId,
            '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType,accountEnabled:accountEnabled,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )

    $objectId = Get-RequiredStringProperty `
        $servicePrincipal 'id' 'service-principal-response-invalid'
    $resolvedAppId = Get-RequiredStringProperty `
        $servicePrincipal 'appId' 'service-principal-response-invalid'
    $type = Get-RequiredStringProperty `
        $servicePrincipal 'servicePrincipalType' 'service-principal-response-invalid'
    $accountEnabled = Get-RequiredBooleanProperty `
        $servicePrincipal 'accountEnabled' 'service-principal-response-invalid'
    $parsedObjectId = [Guid]::Empty
    if (
        -not [Guid]::TryParse($objectId, [ref] $parsedObjectId) -or
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        $type -cne 'Application' -or
        -not $accountEnabled
    ) { throw 'deployment-service-principal-invalid' }

    Assert-EmptyArrayProperty $servicePrincipal 'passwordCredentials' `
        'service-principal-password-credentials-invalid' `
        'service-principal-password-credential-present'
    Assert-EmptyArrayProperty $servicePrincipal 'keyCredentials' `
        'service-principal-key-credentials-invalid' `
        'service-principal-key-credential-present'

    return $servicePrincipal
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
        $applications = @(Invoke-BoundedDiscovery `
            -FailureReason 'deployment-application-create-invalid' `
            -Discovery { Get-ApplicationMatches } `
            -IsReady { param($state) $state.Count -eq 1 })
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
        $servicePrincipals = @(Invoke-BoundedDiscovery `
            -FailureReason 'deployment-service-principal-create-invalid' `
            -Discovery { Get-ServicePrincipalMatches -AppId $appId } `
            -IsReady { param($state) $state.Count -eq 1 })
    }

    $servicePrincipalState = Get-ServicePrincipalState -AppId $appId
    $servicePrincipalObjectId = Get-RequiredStringProperty `
        $servicePrincipalState 'id' 'service-principal-response-invalid'
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

        $credentials = @(Invoke-BoundedDiscovery `
            -FailureReason 'federated-credential-create-invalid' `
            -Discovery {
                Get-FederatedCredentials -ApplicationObjectId $applicationObjectId
            } `
            -IsReady {
                param($state)
                $namedState = @($state | Where-Object {
                    $_.name -ceq $federatedCredentialName
                })
                $state.Count -eq 1 -and $namedState.Count -eq 1
            })
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

        $assignments = @(Invoke-BoundedDiscovery `
            -FailureReason 'deployment-role-assignment-create-invalid' `
            -Discovery {
                Get-DeploymentRoleAssignments `
                    -ServicePrincipalObjectId $servicePrincipalObjectId
            } `
            -IsReady {
                param($state)
                $expectedState = @($state | Where-Object {
                    Test-ExpectedRoleAssignment $_ $roleDefinitionId $webAppScope
                })
                $expectedState.Count -eq 1
            })
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
