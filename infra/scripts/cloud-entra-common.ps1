Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

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

    if ($null -eq $result -or $result -is [System.Array] -or $result -isnot [psobject]) {
        throw $FailureReason
    }

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

function Get-RequiredArrayProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $property.Value -isnot [System.Array]) {
        throw $FailureReason
    }

    Write-Output -NoEnumerate @($property.Value)
}

function Assert-EmptyArrayProperty {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $values = @(Get-RequiredArrayProperty $Object $Name $FailureReason)
    if ($values.Count -ne 0) { throw $FailureReason }
}

function Assert-GuidString {
    param(
        [Parameter(Mandatory)][string] $Value,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Value, [ref] $parsed) -or $parsed -eq [Guid]::Empty) {
        throw $FailureReason
    }
}

function Assert-PrivateCloudInputs {
    param(
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $WebAppName,
        [Parameter(Mandatory)][string] $CloudAppRegistrationName,
        [Parameter(Mandatory)][string] $LocalDevelopmentAppClientId,
        [Parameter(Mandatory)][string] $DeploymentAppClientId
    )

    if (
        $ResourceGroupName -notmatch '^[A-Za-z0-9_.()-]{1,90}$' -or
        $WebAppName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{1,58}[A-Za-z0-9]$' -or
        $CloudAppRegistrationName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{1,118}[A-Za-z0-9]$'
    ) { throw 'private-input-invalid' }

    Assert-GuidString $LocalDevelopmentAppClientId 'local-development-identity-input-invalid'
    Assert-GuidString $DeploymentAppClientId 'deployment-identity-input-invalid'
    if ([string]::Equals(
        $LocalDevelopmentAppClientId,
        $DeploymentAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'local-deployment-identity-reused' }
}

function Get-AzureContext {
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
    Assert-GuidString $subscriptionId 'subscription-context-invalid'
    Assert-GuidString $tenantId 'subscription-context-invalid'
    return $account
}

function Get-ExistingWebAppState {
    param(
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $WebAppName,
        [Parameter(Mandatory)][string] $SubscriptionId
    )

    $webApp = Invoke-AzureJsonObject `
        -FailureReason 'web-app-response-invalid' `
        -Arguments @(
            'webapp', 'show',
            '--resource-group', $ResourceGroupName,
            '--name', $WebAppName,
            '--subscription', $SubscriptionId,
            '--query', '{id:id,type:type,kind:kind,defaultHostName:defaultHostName,identityType:identity.type,principalId:identity.principalId}',
            '--output', 'json',
            '--only-show-errors'
        )

    $resourceId = Get-RequiredStringProperty $webApp 'id' 'web-app-response-invalid'
    $type = Get-RequiredStringProperty $webApp 'type' 'web-app-response-invalid'
    $kind = Get-RequiredStringProperty $webApp 'kind' 'web-app-response-invalid'
    $hostName = Get-RequiredStringProperty $webApp 'defaultHostName' 'web-app-response-invalid'
    $identityType = Get-RequiredStringProperty $webApp 'identityType' 'web-app-response-invalid'
    $principalId = Get-RequiredStringProperty $webApp 'principalId' 'web-app-response-invalid'
    Assert-GuidString $principalId 'web-app-response-invalid'

    $expectedId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}' -f `
        $SubscriptionId, $ResourceGroupName, $WebAppName
    if (
        -not [string]::Equals($resourceId, $expectedId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($type, 'Microsoft.Web/sites', [StringComparison]::OrdinalIgnoreCase) -or
        $kind -notmatch '(?i)(^|,)app($|,)' -or
        $kind -notmatch '(?i)(^|,)linux($|,)' -or
        $identityType -notmatch '(^|,)SystemAssigned($|,)' -or
        $hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{1,251}[A-Za-z0-9]$'
    ) { throw 'web-app-response-invalid' }

    return $webApp
}

function Get-IdentityApplicationState {
    param(
        [Parameter(Mandatory)][string] $ClientId,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $application = Invoke-AzureJsonObject `
        -FailureReason $FailureReason `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $ClientId,
            '--query', '{id:id,appId:appId}',
            '--output', 'json',
            '--only-show-errors'
        )
    $objectId = Get-RequiredStringProperty $application 'id' $FailureReason
    $resolvedClientId = Get-RequiredStringProperty $application 'appId' $FailureReason
    Assert-GuidString $objectId $FailureReason
    Assert-GuidString $resolvedClientId $FailureReason
    if (-not [string]::Equals($resolvedClientId, $ClientId, [StringComparison]::OrdinalIgnoreCase)) {
        throw $FailureReason
    }
    return $application
}

function Get-ApplicationServicePrincipalState {
    param(
        [Parameter(Mandatory)][string] $AppId,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $servicePrincipal = Invoke-AzureJsonObject `
        -FailureReason $FailureReason `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $AppId,
            '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
            '--output', 'json',
            '--only-show-errors'
        )
    $objectId = Get-RequiredStringProperty $servicePrincipal 'id' $FailureReason
    $resolvedAppId = Get-RequiredStringProperty $servicePrincipal 'appId' $FailureReason
    $type = Get-RequiredStringProperty $servicePrincipal 'servicePrincipalType' $FailureReason
    Assert-GuidString $objectId $FailureReason
    Assert-GuidString $resolvedAppId $FailureReason
    if (
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        $type -cne 'Application'
    ) { throw $FailureReason }
    return $servicePrincipal
}

function Get-ManagedIdentityServicePrincipalState {
    param(
        [Parameter(Mandatory)][string] $PrincipalObjectId,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $servicePrincipal = Invoke-AzureJsonObject `
        -FailureReason $FailureReason `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $PrincipalObjectId,
            '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
            '--output', 'json',
            '--only-show-errors'
        )
    $objectId = Get-RequiredStringProperty $servicePrincipal 'id' $FailureReason
    $appId = Get-RequiredStringProperty $servicePrincipal 'appId' $FailureReason
    $type = Get-RequiredStringProperty $servicePrincipal 'servicePrincipalType' $FailureReason
    Assert-GuidString $objectId $FailureReason
    Assert-GuidString $appId $FailureReason
    if (
        -not [string]::Equals($objectId, $PrincipalObjectId, [StringComparison]::OrdinalIgnoreCase) -or
        $type -cne 'ManagedIdentity'
    ) { throw $FailureReason }
    return $servicePrincipal
}

function Assert-DistinctGuidValues {
    param(
        [Parameter(Mandatory)][string[]] $Values,
        [Parameter(Mandatory)][int] $ExpectedCount,
        [Parameter(Mandatory)][string] $FailureReason
    )

    if ($Values.Count -ne $ExpectedCount) { throw $FailureReason }
    $distinct = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Values) {
        Assert-GuidString $value $FailureReason
        if (-not $distinct.Add($value)) { throw $FailureReason }
    }
}

function Assert-CloudIdentitySeparation {
    param(
        [Parameter(Mandatory)][psobject] $LocalApplication,
        [Parameter(Mandatory)][psobject] $DeploymentApplication,
        [Parameter(Mandatory)][psobject] $CloudApplication,
        [Parameter(Mandatory)][psobject] $DeploymentServicePrincipal,
        [Parameter(Mandatory)][psobject] $CloudServicePrincipal,
        [Parameter(Mandatory)][psobject] $ManagedIdentityServicePrincipal,
        [Parameter(Mandatory)][string] $WebAppPrincipalId
    )

    $localApplicationObjectId = Get-RequiredStringProperty $LocalApplication 'id' 'local-application-object-id-invalid'
    $localApplicationAppId = Get-RequiredStringProperty $LocalApplication 'appId' 'local-application-app-id-invalid'
    $deploymentApplicationObjectId = Get-RequiredStringProperty $DeploymentApplication 'id' 'deployment-application-object-id-invalid'
    $deploymentApplicationAppId = Get-RequiredStringProperty $DeploymentApplication 'appId' 'deployment-application-app-id-invalid'
    $cloudApplicationObjectId = Get-RequiredStringProperty $CloudApplication 'id' 'cloud-application-object-id-invalid'
    $cloudApplicationAppId = Get-RequiredStringProperty $CloudApplication 'appId' 'cloud-application-app-id-invalid'
    $deploymentServicePrincipalObjectId = Get-RequiredStringProperty $DeploymentServicePrincipal 'id' 'deployment-service-principal-object-id-invalid'
    $deploymentServicePrincipalAppId = Get-RequiredStringProperty $DeploymentServicePrincipal 'appId' 'deployment-service-principal-app-id-invalid'
    $cloudServicePrincipalObjectId = Get-RequiredStringProperty $CloudServicePrincipal 'id' 'cloud-service-principal-object-id-invalid'
    $cloudServicePrincipalAppId = Get-RequiredStringProperty $CloudServicePrincipal 'appId' 'cloud-service-principal-app-id-invalid'
    $managedIdentityServicePrincipalObjectId = Get-RequiredStringProperty $ManagedIdentityServicePrincipal 'id' 'managed-identity-service-principal-object-id-invalid'
    $managedIdentityServicePrincipalAppId = Get-RequiredStringProperty $ManagedIdentityServicePrincipal 'appId' 'managed-identity-service-principal-app-id-invalid'

    if (
        -not [string]::Equals($deploymentServicePrincipalAppId, $deploymentApplicationAppId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($cloudServicePrincipalAppId, $cloudApplicationAppId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($managedIdentityServicePrincipalObjectId, $WebAppPrincipalId, [StringComparison]::OrdinalIgnoreCase)
    ) { throw 'identity-object-resolution-mismatch' }

    Assert-DistinctGuidValues `
        @($localApplicationAppId, $deploymentApplicationAppId, $cloudApplicationAppId, $managedIdentityServicePrincipalAppId) `
        4 `
        'application-app-id-reused'
    Assert-DistinctGuidValues `
        @($localApplicationObjectId, $deploymentApplicationObjectId, $cloudApplicationObjectId) `
        3 `
        'application-object-id-reused'
    Assert-DistinctGuidValues `
        @($deploymentServicePrincipalObjectId, $cloudServicePrincipalObjectId, $managedIdentityServicePrincipalObjectId) `
        3 `
        'service-principal-object-id-reused'
    if ([string]::Equals(
        $cloudServicePrincipalObjectId,
        $WebAppPrincipalId,
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'cloud-service-principal-managed-identity-reused' }
}

function Get-CloudApplicationMatches {
    param([Parameter(Mandatory)][string] $CloudAppRegistrationName)

    $applications = Invoke-AzureJsonArray `
        -FailureReason 'cloud-application-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'list',
            '--display-name', $CloudAppRegistrationName,
            '--query', '[].{id:id,appId:appId,displayName:displayName}',
            '--output', 'json',
            '--only-show-errors'
        )

    $matches = @()
    foreach ($application in $applications) {
        if ($null -eq $application -or $application -isnot [psobject]) {
            throw 'cloud-application-list-response-invalid'
        }
        $id = Get-RequiredStringProperty $application 'id' 'cloud-application-list-response-invalid'
        $appId = Get-RequiredStringProperty $application 'appId' 'cloud-application-list-response-invalid'
        $displayName = Get-RequiredStringProperty $application 'displayName' 'cloud-application-list-response-invalid'
        Assert-GuidString $id 'cloud-application-list-response-invalid'
        Assert-GuidString $appId 'cloud-application-list-response-invalid'
        if ([string]::Equals($displayName, $CloudAppRegistrationName, [StringComparison]::Ordinal)) {
            $matches += $application
        }
    }

    Write-Output -NoEnumerate $matches
}

function Assert-CloudApplicationState {
    param(
        [Parameter(Mandatory)][string] $AppId,
        [Parameter(Mandatory)][string] $CloudAppRegistrationName,
        [Parameter(Mandatory)][string] $ExpectedSignInUri,
        [Parameter(Mandatory)][string] $ExpectedSignOutCallbackUri,
        [Parameter(Mandatory)][string] $ExpectedFrontChannelLogoutUri
    )

    $application = Invoke-AzureJsonObject `
        -FailureReason 'cloud-application-response-invalid' `
        -Arguments @(
            'ad', 'app', 'show',
            '--id', $AppId,
            '--query', '{id:id,appId:appId,displayName:displayName,signInAudience:signInAudience,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials,requiredResourceAccess:requiredResourceAccess,appRoles:appRoles,web:web,spa:spa,publicClient:publicClient,isFallbackPublicClient:isFallbackPublicClient}',
            '--output', 'json',
            '--only-show-errors'
        )

    $objectId = Get-RequiredStringProperty $application 'id' 'cloud-application-response-invalid'
    $resolvedAppId = Get-RequiredStringProperty $application 'appId' 'cloud-application-response-invalid'
    $displayName = Get-RequiredStringProperty $application 'displayName' 'cloud-application-response-invalid'
    $signInAudience = Get-RequiredStringProperty $application 'signInAudience' 'cloud-application-response-invalid'
    Assert-GuidString $objectId 'cloud-application-response-invalid'
    if (
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($displayName, $CloudAppRegistrationName, [StringComparison]::Ordinal) -or
        $signInAudience -cne 'AzureADMyOrg'
    ) { throw 'cloud-application-configuration-invalid' }

    Assert-EmptyArrayProperty $application 'passwordCredentials' 'cloud-password-credential-present'
    Assert-EmptyArrayProperty $application 'keyCredentials' 'cloud-key-credential-present'
    Assert-EmptyArrayProperty $application 'requiredResourceAccess' 'cloud-api-permission-present'

    $fallbackPublicClient = Get-RequiredBooleanProperty `
        $application 'isFallbackPublicClient' 'cloud-public-client-configuration-invalid'
    if ($fallbackPublicClient) { throw 'cloud-public-client-enabled' }

    $web = Get-RequiredObjectProperty $application 'web' 'cloud-web-configuration-invalid'
    $redirectUris = @(Get-RequiredArrayProperty $web 'redirectUris' 'cloud-web-configuration-invalid')
    if (
        $redirectUris.Count -ne 2 -or
        $redirectUris -contains $null -or
        $redirectUris -notcontains $ExpectedSignInUri -or
        $redirectUris -notcontains $ExpectedSignOutCallbackUri -or
        @($redirectUris | Where-Object { $_ -match '(?i)localhost' }).Count -ne 0
    ) { throw 'cloud-redirect-uri-mismatch' }

    $logoutUrl = Get-RequiredStringProperty $web 'logoutUrl' 'cloud-logout-configuration-invalid'
    if ($logoutUrl -cne $ExpectedFrontChannelLogoutUri) {
        throw 'cloud-logout-configuration-invalid'
    }
    $implicit = Get-RequiredObjectProperty $web 'implicitGrantSettings' 'cloud-implicit-grant-invalid'
    if (
        (Get-RequiredBooleanProperty $implicit 'enableAccessTokenIssuance' 'cloud-implicit-grant-invalid') -or
        (Get-RequiredBooleanProperty $implicit 'enableIdTokenIssuance' 'cloud-implicit-grant-invalid')
    ) { throw 'cloud-implicit-grant-enabled' }

    $spa = Get-RequiredObjectProperty $application 'spa' 'cloud-spa-configuration-invalid'
    $publicClient = Get-RequiredObjectProperty $application 'publicClient' 'cloud-public-client-configuration-invalid'
    Assert-EmptyArrayProperty $spa 'redirectUris' 'cloud-spa-redirect-uri-present'
    Assert-EmptyArrayProperty $publicClient 'redirectUris' 'cloud-public-client-redirect-uri-present'

    $roles = @(Get-RequiredArrayProperty $application 'appRoles' 'cloud-app-role-invalid')
    if ($roles.Count -ne 1 -or $roles[0] -isnot [psobject]) { throw 'cloud-app-role-invalid' }
    $role = $roles[0]
    $roleId = Get-RequiredStringProperty $role 'id' 'cloud-app-role-invalid'
    $display = Get-RequiredStringProperty $role 'displayName' 'cloud-app-role-invalid'
    $value = Get-RequiredStringProperty $role 'value' 'cloud-app-role-invalid'
    $description = Get-RequiredStringProperty $role 'description' 'cloud-app-role-invalid'
    $enabled = Get-RequiredBooleanProperty $role 'isEnabled' 'cloud-app-role-invalid'
    $memberTypes = @(Get-RequiredArrayProperty $role 'allowedMemberTypes' 'cloud-app-role-invalid')
    Assert-GuidString $roleId 'cloud-app-role-invalid'
    if (
        $display -cne 'SecretNotes.Reader' -or
        $value -cne 'SecretNotes.Reader' -or
        $description -cne 'Read the synthetic secret notes catalog.' -or
        -not $enabled -or
        $memberTypes.Count -ne 1 -or
        $memberTypes[0] -cne 'User'
    ) { throw 'cloud-app-role-invalid' }

    return $application
}

function Get-CloudServicePrincipalMatches {
    param([Parameter(Mandatory)][string] $AppId)

    $servicePrincipals = Invoke-AzureJsonArray `
        -FailureReason 'cloud-service-principal-list-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'list',
            '--filter', "appId eq '$AppId'",
            '--query', '[].{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
            '--output', 'json',
            '--only-show-errors'
        )
    Write-Output -NoEnumerate $servicePrincipals
}

function Assert-CloudServicePrincipalState {
    param([Parameter(Mandatory)][string] $AppId)

    $servicePrincipal = Invoke-AzureJsonObject `
        -FailureReason 'cloud-service-principal-response-invalid' `
        -Arguments @(
            'ad', 'sp', 'show',
            '--id', $AppId,
            '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType,accountEnabled:accountEnabled,appRoleAssignmentRequired:appRoleAssignmentRequired,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
            '--output', 'json',
            '--only-show-errors'
        )

    $id = Get-RequiredStringProperty $servicePrincipal 'id' 'cloud-service-principal-response-invalid'
    $resolvedAppId = Get-RequiredStringProperty $servicePrincipal 'appId' 'cloud-service-principal-response-invalid'
    $type = Get-RequiredStringProperty $servicePrincipal 'servicePrincipalType' 'cloud-service-principal-response-invalid'
    Assert-GuidString $id 'cloud-service-principal-response-invalid'
    if (
        -not [string]::Equals($resolvedAppId, $AppId, [StringComparison]::OrdinalIgnoreCase) -or
        $type -cne 'Application' -or
        -not (Get-RequiredBooleanProperty $servicePrincipal 'accountEnabled' 'cloud-service-principal-response-invalid') -or
        -not (Get-RequiredBooleanProperty $servicePrincipal 'appRoleAssignmentRequired' 'cloud-assignment-required-invalid')
    ) { throw 'cloud-service-principal-configuration-invalid' }

    Assert-EmptyArrayProperty $servicePrincipal 'passwordCredentials' 'cloud-service-principal-password-present'
    Assert-EmptyArrayProperty $servicePrincipal 'keyCredentials' 'cloud-service-principal-key-present'
    return $servicePrincipal
}

function Get-CloudFederatedCredentials {
    param([Parameter(Mandatory)][string] $ApplicationObjectId)

    return Invoke-AzureJsonArray `
        -FailureReason 'cloud-federated-credential-list-response-invalid' `
        -Arguments @(
            'ad', 'app', 'federated-credential', 'list',
            '--id', $ApplicationObjectId,
            '--query', '[].{id:id,name:name,issuer:issuer,subject:subject,audiences:audiences}',
            '--output', 'json',
            '--only-show-errors'
        )
}

function Assert-ExactManagedIdentityFederation {
    param(
        [Parameter(Mandatory)][System.Array] $Credentials,
        [Parameter(Mandatory)][string] $ExpectedIssuer,
        [Parameter(Mandatory)][string] $ExpectedSubject
    )

    if ($Credentials.Count -ne 1 -or $Credentials[0] -isnot [psobject]) {
        throw 'cloud-federated-credential-count-invalid'
    }
    $credential = $Credentials[0]
    $name = Get-RequiredStringProperty $credential 'name' 'cloud-federated-credential-invalid'
    $issuer = Get-RequiredStringProperty $credential 'issuer' 'cloud-federated-credential-invalid'
    $subject = Get-RequiredStringProperty $credential 'subject' 'cloud-federated-credential-invalid'
    $audiences = @(Get-RequiredArrayProperty $credential 'audiences' 'cloud-federated-credential-invalid')
    if (
        $name -cne 'web-app-system-assigned-managed-identity' -or
        $issuer -cne $ExpectedIssuer -or
        $subject -cne $ExpectedSubject -or
        $audiences.Count -ne 1 -or
        $audiences[0] -cne 'api://AzureADTokenExchange'
    ) { throw 'cloud-federated-credential-mismatch' }
}

function Assert-NoDirectKeyVaultRole {
    param(
        [Parameter(Mandatory)][string] $PrincipalObjectId,
        [Parameter(Mandatory)][string] $KeyVaultResourceId,
        [Parameter(Mandatory)][string] $SubscriptionId,
        [Parameter(Mandatory)][string] $FailureReason
    )

    $assignments = Invoke-AzureJsonArray `
        -FailureReason 'key-vault-role-assignment-response-invalid' `
        -Arguments @(
            'role', 'assignment', 'list',
            '--scope', $KeyVaultResourceId,
            '--assignee-object-id', $PrincipalObjectId,
            '--fill-principal-name', 'false',
            '--fill-role-definition-name', 'false',
            '--subscription', $SubscriptionId,
            '--query', '[].{scope:scope}',
            '--output', 'json',
            '--only-show-errors'
        )
    $direct = @($assignments | Where-Object {
        [string]::Equals(
            [string] $_.scope,
            $KeyVaultResourceId,
            [StringComparison]::OrdinalIgnoreCase
        )
    })
    if ($direct.Count -ne 0) { throw $FailureReason }
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
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $DelaySeconds }
    }
    throw $FailureReason
}
