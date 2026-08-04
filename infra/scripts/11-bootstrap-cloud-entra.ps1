#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [Parameter(Mandatory)][string] $WebAppName,
    [Parameter(Mandatory)][string] $CloudAppRegistrationName,
    [Parameter(Mandatory)][string] $LocalDevelopmentAppClientId,
    [Parameter(Mandatory)][string] $DeploymentAppClientId,
    [switch] $Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Standalone implementation; intentionally does not dot-source cloud-entra-common.ps1.

function Assert-Guid([string] $Value, [string] $Reason) {
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Value, [ref] $parsed) -or $parsed -eq [Guid]::Empty) {
        throw $Reason
    }
}

function Read-String(
    [System.Collections.IDictionary] $Map,
    [string] $Key,
    [string] $Reason
) {
    $value = $Map[$Key]
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        throw $Reason
    }
    return [string] $value
}

function Read-OptionalString(
    [System.Collections.IDictionary] $Map,
    [string] $Key,
    [string] $Reason
) {
    $value = $Map[$Key]
    if ($null -eq $value) { return $null }
    if ($value -isnot [string]) { throw $Reason }
    return [string] $value
}

function Read-Bool(
    [System.Collections.IDictionary] $Map,
    [string] $Key,
    [string] $Reason
) {
    $value = $Map[$Key]
    if ($value -isnot [bool]) { throw $Reason }
    return [bool] $value
}

function Read-OptionalBool(
    [System.Collections.IDictionary] $Map,
    [string] $Key,
    [string] $Reason
) {
    $value = $Map[$Key]
    if ($null -eq $value) { return $null }
    if ($value -isnot [bool]) { throw $Reason }
    return [bool] $value
}

function As-Array($Value, [string] $Reason) {
    if ($null -eq $Value) { return @() }
    if ($Value -isnot [System.Array]) { throw $Reason }
    return @($Value)
}

function As-Map($Value, [string] $Reason) {
    if ($null -eq $Value) { return $null }
    if ($Value -isnot [System.Collections.IDictionary]) { throw $Reason }
    return $Value
}

function ConvertTo-Map([string[]] $Lines, [string] $Reason) {
    try {
        $value = ConvertFrom-Json `
            -InputObject ($Lines -join [Environment]::NewLine) `
            -AsHashtable `
            -NoEnumerate
    }
    catch {
        throw $Reason
    }

    if ($value -isnot [System.Collections.IDictionary]) { throw $Reason }
    return $value
}

function ConvertTo-List([string[]] $Lines, [string] $Reason) {
    try {
        $value = ConvertFrom-Json `
            -InputObject ($Lines -join [Environment]::NewLine) `
            -AsHashtable `
            -NoEnumerate
    }
    catch {
        throw $Reason
    }

    if ($value -isnot [System.Array]) { throw $Reason }
    foreach ($item in $value) {
        if ($item -isnot [System.Collections.IDictionary]) { throw $Reason }
        Write-Output $item
    }
}

function Invoke-AzMap([string[]] $Arguments, [string] $Reason) {
    $lines = @(& az @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw $Reason }
    return ConvertTo-Map $lines $Reason
}

function Invoke-AzList([string[]] $Arguments, [string] $Reason) {
    $lines = @(& az @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw $Reason }
    foreach ($item in @(ConvertTo-List $lines $Reason)) {
        Write-Output $item
    }
}

function Invoke-JsonMutation {
    param(
        [ValidateSet('POST', 'PATCH')][string] $Method,
        [string] $Url,
        [System.Collections.IDictionary] $Document,
        [string] $Reason
    )

    $temporaryFile = New-TemporaryFile
    try {
        [IO.File]::WriteAllText(
            $temporaryFile.FullName,
            ($Document | ConvertTo-Json -Depth 12),
            [Text.UTF8Encoding]::new($false)
        )

        $arguments = @(
            'rest',
            '--method', $Method,
            '--url', $Url,
            '--headers', 'Content-Type=application/json',
            '--body', "@$($temporaryFile.FullName)",
            '--output', 'none',
            '--only-show-errors'
        )
        $null = & az @arguments 2>$null
        if ($LASTEXITCODE -ne 0) { throw $Reason }
    }
    finally {
        Remove-Item -LiteralPath $temporaryFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BoundedDiscovery {
    param(
        [scriptblock] $Read,
        [string] $Reason,
        [int] $MaxAttempts = 6
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $items = @(& $Read)
            if ($items.Count -eq 1) { return $items[0] }
            if ($items.Count -gt 1) { throw $Reason }
        }
        catch {
            if ($attempt -eq $MaxAttempts) { throw $Reason }
        }

        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 5 }
    }

    throw $Reason
}

function Get-CloudApplications {
    $items = @(Invoke-AzList -Reason 'cloud-application-list-response-invalid' -Arguments @(
        'ad', 'app', 'list',
        '--display-name', $CloudAppRegistrationName,
        '--query', '[].{id:id,appId:appId,displayName:displayName}',
        '--output', 'json',
        '--only-show-errors'
    ))

    foreach ($item in $items) {
        $id = Read-String $item 'id' 'cloud-application-list-response-invalid'
        $appId = Read-String $item 'appId' 'cloud-application-list-response-invalid'
        $displayName = Read-String $item 'displayName' 'cloud-application-list-response-invalid'
        Assert-Guid $id 'cloud-application-list-response-invalid'
        Assert-Guid $appId 'cloud-application-list-response-invalid'
        if ($displayName -ceq $CloudAppRegistrationName) { Write-Output $item }
    }
}

function Get-CloudApplication([string] $CloudAppClientId) {
    return Invoke-AzMap -Reason 'cloud-application-response-invalid' -Arguments @(
        'ad', 'app', 'show',
        '--id', $CloudAppClientId,
        '--query',
        '{id:id,appId:appId,displayName:displayName,signInAudience:signInAudience,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials,requiredResourceAccess:requiredResourceAccess,appRoles:appRoles,web:web,spa:spa,publicClient:publicClient,isFallbackPublicClient:isFallbackPublicClient}',
        '--output', 'json',
        '--only-show-errors'
    )
}

function Get-CloudServicePrincipals([string] $CloudAppClientId) {
    $items = @(Invoke-AzList -Reason 'cloud-service-principal-list-response-invalid' -Arguments @(
        'ad', 'sp', 'list',
        '--filter', "appId eq '$CloudAppClientId'",
        '--query', '[].{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
        '--output', 'json',
        '--only-show-errors'
    ))

    foreach ($item in $items) {
        $id = Read-String $item 'id' 'cloud-service-principal-list-response-invalid'
        $appId = Read-String $item 'appId' 'cloud-service-principal-list-response-invalid'
        $type = Read-String $item 'servicePrincipalType' 'cloud-service-principal-list-response-invalid'
        Assert-Guid $id 'cloud-service-principal-list-response-invalid'
        Assert-Guid $appId 'cloud-service-principal-list-response-invalid'
        if (
            -not [string]::Equals($appId, $CloudAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
            $type -cne 'Application'
        ) {
            throw 'cloud-service-principal-list-response-invalid'
        }

        Write-Output $item
    }
}

function Get-FederatedCredentials([string] $ApplicationObjectId) {
    foreach ($item in @(Invoke-AzList -Reason 'cloud-federated-credential-list-response-invalid' -Arguments @(
        'ad', 'app', 'federated-credential', 'list',
        '--id', $ApplicationObjectId,
        '--query', '[].{id:id,name:name,issuer:issuer,subject:subject,audiences:audiences}',
        '--output', 'json',
        '--only-show-errors'
    ))) {
        Write-Output $item
    }
}

function New-ReaderRoleDocument([string] $RoleId) {
    Assert-Guid $RoleId 'cloud-app-role-invalid'
    return [ordered]@{
        id = $RoleId
        displayName = 'SecretNotes.Reader'
        description = 'Read the synthetic secret notes catalog.'
        value = 'SecretNotes.Reader'
        allowedMemberTypes = @('User')
        isEnabled = $true
    }
}

function Get-CloudApplicationConvergencePlan {
    param(
        [System.Collections.IDictionary] $Application,
        [string] $ExpectedSignInUri,
        [string] $ExpectedSignOutCallbackUri,
        [string] $ExpectedLogoutUri
    )

    $objectId = Read-String $Application 'id' 'cloud-application-response-invalid'
    $appId = Read-String $Application 'appId' 'cloud-application-response-invalid'
    $displayName = Read-String $Application 'displayName' 'cloud-application-response-invalid'
    $audience = Read-String $Application 'signInAudience' 'cloud-application-response-invalid'
    Assert-Guid $objectId 'cloud-application-response-invalid'
    Assert-Guid $appId 'cloud-application-response-invalid'

    if ($displayName -cne $CloudAppRegistrationName -or $audience -cne 'AzureADMyOrg') {
        throw 'cloud-application-configuration-invalid'
    }

    if (@(As-Array $Application['passwordCredentials'] 'cloud-password-credential-response-invalid').Count -ne 0) {
        throw 'cloud-password-credential-present'
    }
    if (@(As-Array $Application['keyCredentials'] 'cloud-key-credential-response-invalid').Count -ne 0) {
        throw 'cloud-key-credential-present'
    }
    if (@(As-Array $Application['requiredResourceAccess'] 'cloud-api-permission-response-invalid').Count -ne 0) {
        throw 'cloud-api-permission-present'
    }

    $fallbackPublicClient = Read-OptionalBool `
        $Application 'isFallbackPublicClient' 'cloud-public-client-configuration-invalid'
    if ($fallbackPublicClient -eq $true) { throw 'cloud-public-client-enabled' }

    $publicClient = As-Map $Application['publicClient'] 'cloud-public-client-configuration-invalid'
    if (
        $null -ne $publicClient -and
        @(As-Array $publicClient['redirectUris'] 'cloud-public-client-configuration-invalid').Count -ne 0
    ) {
        throw 'cloud-public-client-redirect-uri-present'
    }

    $spa = As-Map $Application['spa'] 'cloud-spa-configuration-invalid'
    if (
        $null -ne $spa -and
        @(As-Array $spa['redirectUris'] 'cloud-spa-configuration-invalid').Count -ne 0
    ) {
        throw 'cloud-spa-redirect-uri-present'
    }

    $needsPatch = $false
    $web = As-Map $Application['web'] 'cloud-web-configuration-invalid'
    if ($null -eq $web) {
        $needsPatch = $true
        $redirectUris = @()
        $logoutUrl = $null
        $implicit = $null
    }
    else {
        $redirectUris = @(As-Array $web['redirectUris'] 'cloud-web-configuration-invalid')
        $logoutUrl = Read-OptionalString $web 'logoutUrl' 'cloud-logout-configuration-invalid'
        $implicit = As-Map $web['implicitGrantSettings'] 'cloud-implicit-grant-invalid'
    }

    if ($redirectUris.Count -eq 0) {
        $needsPatch = $true
    }
    elseif (
        $redirectUris.Count -ne 2 -or
        $redirectUris -notcontains $ExpectedSignInUri -or
        $redirectUris -notcontains $ExpectedSignOutCallbackUri -or
        @($redirectUris | Where-Object { $_ -isnot [string] -or $_ -match '(?i)localhost' }).Count -ne 0
    ) {
        throw 'cloud-redirect-uri-mismatch'
    }

    if ([string]::IsNullOrWhiteSpace($logoutUrl)) {
        $needsPatch = $true
    }
    elseif ($logoutUrl -cne $ExpectedLogoutUri) {
        throw 'cloud-logout-configuration-invalid'
    }

    if ($null -ne $implicit) {
        foreach ($key in @('enableAccessTokenIssuance', 'enableIdTokenIssuance')) {
            $value = Read-OptionalBool $implicit $key 'cloud-implicit-grant-invalid'
            if ($value -eq $true) { throw 'cloud-implicit-grant-enabled' }
        }
    }

    $roles = @(As-Array $Application['appRoles'] 'cloud-app-role-invalid')
    if ($roles.Count -eq 0) {
        $needsPatch = $true
        $roleDocument = New-ReaderRoleDocument ([Guid]::NewGuid().ToString())
    }
    elseif ($roles.Count -eq 1 -and $roles[0] -is [System.Collections.IDictionary]) {
        $role = $roles[0]
        $roleId = Read-String $role 'id' 'cloud-app-role-invalid'
        Assert-Guid $roleId 'cloud-app-role-invalid'
        $memberTypes = @(As-Array $role['allowedMemberTypes'] 'cloud-app-role-invalid')
        if (
            (Read-String $role 'displayName' 'cloud-app-role-invalid') -cne 'SecretNotes.Reader' -or
            (Read-String $role 'value' 'cloud-app-role-invalid') -cne 'SecretNotes.Reader' -or
            (Read-String $role 'description' 'cloud-app-role-invalid') -cne 'Read the synthetic secret notes catalog.' -or
            -not (Read-Bool $role 'isEnabled' 'cloud-app-role-invalid') -or
            $memberTypes.Count -ne 1 -or
            $memberTypes[0] -cne 'User'
        ) {
            throw 'cloud-app-role-invalid'
        }
        $roleDocument = New-ReaderRoleDocument $roleId
    }
    else {
        throw 'cloud-app-role-invalid'
    }

    return [ordered]@{
        NeedsPatch = $needsPatch
        RoleDocument = $roleDocument
    }
}

function Assert-CloudServicePrincipalState {
    param(
        [System.Collections.IDictionary] $ServicePrincipal,
        [string] $CloudAppClientId
    )

    $id = Read-String $ServicePrincipal 'id' 'cloud-service-principal-response-invalid'
    $appId = Read-String $ServicePrincipal 'appId' 'cloud-service-principal-response-invalid'
    Assert-Guid $id 'cloud-service-principal-response-invalid'
    Assert-Guid $appId 'cloud-service-principal-response-invalid'

    if (
        -not [string]::Equals($appId, $CloudAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        (Read-String $ServicePrincipal 'servicePrincipalType' 'cloud-service-principal-response-invalid') -cne 'Application' -or
        -not (Read-Bool $ServicePrincipal 'accountEnabled' 'cloud-service-principal-response-invalid') -or
        -not (Read-Bool $ServicePrincipal 'appRoleAssignmentRequired' 'cloud-assignment-required-invalid')
    ) {
        throw 'cloud-service-principal-configuration-invalid'
    }

    if (@(As-Array $ServicePrincipal['passwordCredentials'] 'cloud-service-principal-password-response-invalid').Count -ne 0) {
        throw 'cloud-service-principal-password-present'
    }
    if (@(As-Array $ServicePrincipal['keyCredentials'] 'cloud-service-principal-key-response-invalid').Count -ne 0) {
        throw 'cloud-service-principal-key-present'
    }

    return $ServicePrincipal
}

function Assert-DistinctGuids([string[]] $Values, [string] $Reason) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Values) {
        Assert-Guid $value $Reason
        if (-not $seen.Add($value)) { throw $Reason }
    }
}

function Assert-FederatedCredential {
    param(
        [System.Collections.IDictionary] $Credential,
        [string] $ExpectedIssuer,
        [string] $ExpectedSubject
    )

    $audiences = @(As-Array $Credential['audiences'] 'cloud-federated-credential-invalid')
    if (
        (Read-String $Credential 'name' 'cloud-federated-credential-invalid') -cne 'web-app-system-assigned-managed-identity' -or
        (Read-String $Credential 'issuer' 'cloud-federated-credential-invalid') -cne $ExpectedIssuer -or
        (Read-String $Credential 'subject' 'cloud-federated-credential-invalid') -cne $ExpectedSubject -or
        $audiences.Count -ne 1 -or
        $audiences[0] -cne 'api://AzureADTokenExchange'
    ) {
        throw 'cloud-federated-credential-mismatch'
    }
}

try {
    if (
        $ResourceGroupName -notmatch '^[A-Za-z0-9_.()-]{1,90}$' -or
        $WebAppName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{1,58}[A-Za-z0-9]$' -or
        $CloudAppRegistrationName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{1,118}[A-Za-z0-9]$'
    ) {
        throw 'private-input-invalid'
    }

    Assert-Guid $LocalDevelopmentAppClientId 'local-development-identity-input-invalid'
    Assert-Guid $DeploymentAppClientId 'deployment-identity-input-invalid'
    if ([string]::Equals(
        $LocalDevelopmentAppClientId,
        $DeploymentAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'local-deployment-identity-reused'
    }

    if ($null -eq (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'azure-cli-unavailable'
    }

    $context = Invoke-AzMap -Reason 'subscription-context-invalid' -Arguments @(
        'account', 'show',
        '--query', '{id:id,tenantId:tenantId}',
        '--output', 'json',
        '--only-show-errors'
    )
    $subscriptionId = Read-String $context 'id' 'subscription-context-invalid'
    $tenantId = Read-String $context 'tenantId' 'subscription-context-invalid'
    Assert-Guid $subscriptionId 'subscription-context-invalid'
    Assert-Guid $tenantId 'subscription-context-invalid'

    $webApp = Invoke-AzMap -Reason 'web-app-response-invalid' -Arguments @(
        'webapp', 'show',
        '--resource-group', $ResourceGroupName,
        '--name', $WebAppName,
        '--subscription', $subscriptionId,
        '--query',
        '{id:id,type:type,kind:kind,defaultHostName:defaultHostName,identityType:identity.type,principalId:identity.principalId}',
        '--output', 'json',
        '--only-show-errors'
    )

    $webAppResourceId = Read-String $webApp 'id' 'web-app-response-invalid'
    $webAppPrincipalId = Read-String $webApp 'principalId' 'web-app-response-invalid'
    $hostName = Read-String $webApp 'defaultHostName' 'web-app-response-invalid'
    $webAppKind = Read-String $webApp 'kind' 'web-app-response-invalid'
    Assert-Guid $webAppPrincipalId 'web-app-response-invalid'

    $expectedWebAppResourceId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Web/sites/{2}' -f `
        $subscriptionId, $ResourceGroupName, $WebAppName
    if (
        -not [string]::Equals($webAppResourceId, $expectedWebAppResourceId, [StringComparison]::OrdinalIgnoreCase) -or
        (Read-String $webApp 'type' 'web-app-response-invalid') -cne 'Microsoft.Web/sites' -or
        $webAppKind -notmatch '(?i)(^|,)app($|,)' -or
        $webAppKind -notmatch '(?i)(^|,)linux($|,)' -or
        (Read-String $webApp 'identityType' 'web-app-response-invalid') -notmatch '(^|,)SystemAssigned($|,)' -or
        $hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{1,251}[A-Za-z0-9]$'
    ) {
        throw 'web-app-response-invalid'
    }

    $localApplication = Invoke-AzMap -Reason 'local-development-application-response-invalid' -Arguments @(
        'ad', 'app', 'show', '--id', $LocalDevelopmentAppClientId,
        '--query', '{id:id,appId:appId}', '--output', 'json', '--only-show-errors'
    )
    $deploymentApplication = Invoke-AzMap -Reason 'deployment-application-response-invalid' -Arguments @(
        'ad', 'app', 'show', '--id', $DeploymentAppClientId,
        '--query', '{id:id,appId:appId}', '--output', 'json', '--only-show-errors'
    )
    $deploymentServicePrincipal = Invoke-AzMap -Reason 'deployment-service-principal-response-invalid' -Arguments @(
        'ad', 'sp', 'show', '--id', $DeploymentAppClientId,
        '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
        '--output', 'json', '--only-show-errors'
    )
    $managedIdentityServicePrincipal = Invoke-AzMap -Reason 'managed-identity-service-principal-response-invalid' -Arguments @(
        'ad', 'sp', 'show', '--id', $webAppPrincipalId,
        '--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType}',
        '--output', 'json', '--only-show-errors'
    )

    $localAppObjectId = Read-String $localApplication 'id' 'local-development-application-response-invalid'
    $localAppId = Read-String $localApplication 'appId' 'local-development-application-response-invalid'
    $deploymentAppObjectId = Read-String $deploymentApplication 'id' 'deployment-application-response-invalid'
    $deploymentAppId = Read-String $deploymentApplication 'appId' 'deployment-application-response-invalid'
    $deploymentSpObjectId = Read-String $deploymentServicePrincipal 'id' 'deployment-service-principal-response-invalid'
    $deploymentSpAppId = Read-String $deploymentServicePrincipal 'appId' 'deployment-service-principal-response-invalid'
    $managedIdentityObjectId = Read-String $managedIdentityServicePrincipal 'id' 'managed-identity-service-principal-response-invalid'
    $managedIdentityAppId = Read-String $managedIdentityServicePrincipal 'appId' 'managed-identity-service-principal-response-invalid'

    foreach ($value in @(
        $localAppObjectId, $localAppId,
        $deploymentAppObjectId, $deploymentAppId,
        $deploymentSpObjectId, $deploymentSpAppId,
        $managedIdentityObjectId, $managedIdentityAppId
    )) {
        Assert-Guid $value 'identity-response-invalid'
    }

    if (
        -not [string]::Equals($localAppId, $LocalDevelopmentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($deploymentAppId, $DeploymentAppClientId, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($deploymentSpAppId, $deploymentAppId, [StringComparison]::OrdinalIgnoreCase) -or
        (Read-String $deploymentServicePrincipal 'servicePrincipalType' 'deployment-service-principal-response-invalid') -cne 'Application' -or
        -not [string]::Equals($managedIdentityObjectId, $webAppPrincipalId, [StringComparison]::OrdinalIgnoreCase) -or
        (Read-String $managedIdentityServicePrincipal 'servicePrincipalType' 'managed-identity-service-principal-response-invalid') -cne 'ManagedIdentity'
    ) {
        throw 'identity-object-resolution-mismatch'
    }

    $expectedSignInUri = "https://$hostName/signin-oidc"
    $expectedSignOutCallbackUri = "https://$hostName/signout-callback-oidc"
    $expectedLogoutUri = "https://$hostName/signout-oidc"
    $expectedIssuer = "https://login.microsoftonline.com/$tenantId/v2.0"

    $applications = @(Get-CloudApplications)
    if ($applications.Count -gt 1) { throw 'cloud-application-duplicate' }
    if ($applications.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $applicationDocument = [ordered]@{
            displayName = $CloudAppRegistrationName
            signInAudience = 'AzureADMyOrg'
            isFallbackPublicClient = $false
            requiredResourceAccess = @()
            passwordCredentials = @()
            keyCredentials = @()
            appRoles = @(New-ReaderRoleDocument ([Guid]::NewGuid().ToString()))
            web = [ordered]@{
                redirectUris = @($expectedSignInUri, $expectedSignOutCallbackUri)
                logoutUrl = $expectedLogoutUri
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
            -Reason 'cloud-application-create-failed'
        $applications = @(
            Invoke-BoundedDiscovery `
                -Read { Get-CloudApplications } `
                -Reason 'cloud-application-create-invalid'
        )
    }

    if ($applications.Count -ne 1) { throw 'cloud-application-count-invalid' }

    $cloudAppClientId = Read-String $applications[0] 'appId' 'cloud-application-response-invalid'
    $cloudApplication = Get-CloudApplication $cloudAppClientId
    $applicationPlan = Get-CloudApplicationConvergencePlan `
        $cloudApplication $expectedSignInUri $expectedSignOutCallbackUri $expectedLogoutUri
    $cloudAppObjectId = Read-String $cloudApplication 'id' 'cloud-application-response-invalid'

    if ([bool] $applicationPlan['NeedsPatch']) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $applicationPatchDocument = [ordered]@{
            web = [ordered]@{
                redirectUris = @($expectedSignInUri, $expectedSignOutCallbackUri)
                logoutUrl = $expectedLogoutUri
                implicitGrantSettings = [ordered]@{
                    enableAccessTokenIssuance = $false
                    enableIdTokenIssuance = $false
                }
            }
            appRoles = @($applicationPlan['RoleDocument'])
        }
        Invoke-JsonMutation `
            -Method 'PATCH' `
            -Url "https://graph.microsoft.com/v1.0/applications/$cloudAppObjectId" `
            -Document $applicationPatchDocument `
            -Reason 'cloud-application-update-failed'

        $cloudApplication = Invoke-BoundedDiscovery `
            -Read {
                $candidate = Get-CloudApplication $cloudAppClientId
                $candidatePlan = Get-CloudApplicationConvergencePlan `
                    $candidate $expectedSignInUri $expectedSignOutCallbackUri $expectedLogoutUri
                if (-not [bool] $candidatePlan['NeedsPatch']) { Write-Output $candidate }
            } `
            -Reason 'cloud-application-update-invalid'
        $applicationPlan = Get-CloudApplicationConvergencePlan `
            $cloudApplication $expectedSignInUri $expectedSignOutCallbackUri $expectedLogoutUri
        if ([bool] $applicationPlan['NeedsPatch']) { throw 'cloud-application-update-invalid' }
    }

    $cloudAppObjectId = Read-String $cloudApplication 'id' 'cloud-application-response-invalid'

    Write-Output 'cloud-app-registration-valid'
    Write-Output 'cloud-redirect-uris-valid'
    Write-Output 'cloud-app-role-valid'
    Write-Output 'cloud-client-secret-absent'
    Write-Output 'cloud-certificate-absent'

    $servicePrincipals = @(Get-CloudServicePrincipals $cloudAppClientId)
    if ($servicePrincipals.Count -gt 1) { throw 'cloud-service-principal-duplicate' }

    $servicePrincipalCreated = $false
    if ($servicePrincipals.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $servicePrincipalDocument = [ordered]@{
            appId = $cloudAppClientId
        }
        Invoke-JsonMutation `
            -Method 'POST' `
            -Url 'https://graph.microsoft.com/v1.0/servicePrincipals' `
            -Document $servicePrincipalDocument `
            -Reason 'cloud-service-principal-create-failed'
        $servicePrincipals = @(
            Invoke-BoundedDiscovery `
                -Read { Get-CloudServicePrincipals $cloudAppClientId } `
                -Reason 'cloud-service-principal-create-invalid'
        )
        $servicePrincipalCreated = $true
    }

    if ($servicePrincipals.Count -ne 1) { throw 'cloud-service-principal-count-invalid' }

    $createdServicePrincipalId = Read-String `
        $servicePrincipals[0] 'id' 'cloud-service-principal-response-invalid'

    if ($servicePrincipalCreated) {
        $servicePrincipalPatchDocument = [ordered]@{
            appRoleAssignmentRequired = $true
        }
        Invoke-JsonMutation `
            -Method 'PATCH' `
            -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$createdServicePrincipalId" `
            -Document $servicePrincipalPatchDocument `
            -Reason 'cloud-service-principal-update-failed'

        $validatedServicePrincipals = @(
            Invoke-BoundedDiscovery `
                -Read {
                    $candidate = Invoke-AzMap -Reason 'cloud-service-principal-response-invalid' -Arguments @(
                        'ad', 'sp', 'show', '--id', $cloudAppClientId,
                        '--query',
                        '{id:id,appId:appId,servicePrincipalType:servicePrincipalType,accountEnabled:accountEnabled,appRoleAssignmentRequired:appRoleAssignmentRequired,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
                        '--output', 'json', '--only-show-errors'
                    )
                    $candidate = Assert-CloudServicePrincipalState $candidate $cloudAppClientId
                    if (-not [string]::Equals(
                        (Read-String $candidate 'id' 'cloud-service-principal-validation-failed'),
                        $createdServicePrincipalId,
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                        throw 'cloud-service-principal-validation-failed'
                    }
                    Write-Output $candidate
                } `
                -Reason 'cloud-service-principal-validation-failed'
        )
        if ($validatedServicePrincipals.Count -ne 1) {
            throw 'cloud-service-principal-validation-failed'
        }
        $cloudServicePrincipal = $validatedServicePrincipals[0]
    }
    else {
        $cloudServicePrincipal = Assert-CloudServicePrincipalState `
            (Invoke-AzMap -Reason 'cloud-service-principal-response-invalid' -Arguments @(
                'ad', 'sp', 'show', '--id', $cloudAppClientId,
                '--query',
                '{id:id,appId:appId,servicePrincipalType:servicePrincipalType,accountEnabled:accountEnabled,appRoleAssignmentRequired:appRoleAssignmentRequired,passwordCredentials:passwordCredentials,keyCredentials:keyCredentials}',
                '--output', 'json', '--only-show-errors'
            )) `
            $cloudAppClientId
    }

    $cloudSpObjectId = Read-String $cloudServicePrincipal 'id' 'cloud-service-principal-response-invalid'
    $cloudSpAppId = Read-String $cloudServicePrincipal 'appId' 'cloud-service-principal-response-invalid'
    Assert-DistinctGuids `
        @($localAppId, $deploymentAppId, $cloudAppClientId, $managedIdentityAppId) `
        'application-app-id-reused'
    Assert-DistinctGuids `
        @($localAppObjectId, $deploymentAppObjectId, $cloudAppObjectId) `
        'application-object-id-reused'
    Assert-DistinctGuids `
        @($deploymentSpObjectId, $cloudSpObjectId, $managedIdentityObjectId) `
        'service-principal-object-id-reused'
    if (-not [string]::Equals(
        $cloudSpAppId,
        $cloudAppClientId,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'identity-object-resolution-mismatch'
    }

    Write-Output 'cloud-enterprise-application-valid'
    Write-Output 'cloud-assignment-required-valid'

    $credentials = @(Get-FederatedCredentials $cloudAppObjectId)
    if ($credentials.Count -gt 1) { throw 'cloud-federated-credential-count-invalid' }
    if ($credentials.Count -eq 0) {
        if (-not $Apply) {
            Write-Output 'cloud-entra-apply-required'
            return
        }

        $credentialDocument = [ordered]@{
            name = 'web-app-system-assigned-managed-identity'
            issuer = $expectedIssuer
            subject = $webAppPrincipalId
            audiences = @('api://AzureADTokenExchange')
        }
        Invoke-JsonMutation `
            -Method 'POST' `
            -Url "https://graph.microsoft.com/v1.0/applications/$cloudAppObjectId/federatedIdentityCredentials" `
            -Document $credentialDocument `
            -Reason 'cloud-federated-credential-create-failed'
        $credentials = @(
            Invoke-BoundedDiscovery `
                -Read { Get-FederatedCredentials $cloudAppObjectId } `
                -Reason 'cloud-federated-credential-create-invalid'
        )
    }

    if ($credentials.Count -ne 1) { throw 'cloud-federated-credential-count-invalid' }
    Assert-FederatedCredential $credentials[0] $expectedIssuer $webAppPrincipalId

    Write-Output 'cloud-managed-identity-federation-valid'
    Write-Output 'cloud-identity-separation-valid'
    Write-Output 'cloud-entra-bootstrap-valid'
}
catch {
    $reason = $_.Exception.Message
    if ($reason -notmatch '^[a-z0-9-]+$') {
        $reason = 'cloud-entra-bootstrap-operation-failed'
    }
    Write-Output "cloud-entra-bootstrap-failure-reason:$reason"
    Write-Output 'cloud-entra-bootstrap-failed'
    exit 1
}
