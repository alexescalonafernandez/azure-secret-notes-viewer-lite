using System.Text.RegularExpressions;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Operations;

public sealed class CloudEntraPublicationFoundationTests
{
    private static readonly string[] ScriptNames =
    [
        "11-bootstrap-cloud-entra.ps1",
        "12-validate-cloud-entra.ps1",
        "13-cloud-runtime-config-deploy.ps1",
        "14-cloud-application-validate.ps1"
    ];

    [Fact]
    public void RequiredOwnerRunScriptsExistAndUseSanitizedContracts()
    {
        var common = ReadScript("cloud-entra-common.ps1");
        Assert.Contains("2>$null", common, StringComparison.Ordinal);

        foreach (var scriptName in ScriptNames)
        {
            var script = ReadRepositoryFile("infra", "scripts", scriptName);

            Assert.StartsWith("#requires -Version 7.0", script, StringComparison.Ordinal);
            Assert.Contains("cloud-entra-common.ps1", script, StringComparison.Ordinal);
            Assert.DoesNotContain("Invoke-Expression", script, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("--output', 'tsv", script, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotMatch(
                @"(?i)(Write-(Output|Host)|echo).*(tenantId|subscriptionId|principalId|appId|hostName|Location|response\.Content)",
                script);
        }

        Assert.Contains(
            "cloud-entra-bootstrap-valid",
            ReadScript("11-bootstrap-cloud-entra.ps1"),
            StringComparison.Ordinal);
        Assert.Contains(
            "cloud-entra-validation-valid",
            ReadScript("12-validate-cloud-entra.ps1"),
            StringComparison.Ordinal);
        Assert.Contains(
            "cloud-runtime-config-valid",
            ReadScript("13-cloud-runtime-config-deploy.ps1"),
            StringComparison.Ordinal);
        Assert.Contains(
            "cloud-application-validation-valid",
            ReadScript("14-cloud-application-validate.ps1"),
            StringComparison.Ordinal);
    }

    [Fact]
    public void BootstrapIsNonMutatingByDefaultAndFailClosed()
    {
        var script = ReadScript("11-bootstrap-cloud-entra.ps1");

        Assert.Contains("[switch] $Apply", script, StringComparison.Ordinal);
        Assert.Contains("if (-not $Apply)", script, StringComparison.Ordinal);
        Assert.Contains("cloud-entra-apply-required", script, StringComparison.Ordinal);
        Assert.Contains("cloud-application-duplicate", script, StringComparison.Ordinal);
        Assert.Contains("cloud-service-principal-duplicate", script, StringComparison.Ordinal);
        Assert.Contains("cloud-federated-credential-count-invalid", script, StringComparison.Ordinal);
        Assert.Contains("'--method', $Method", script, StringComparison.Ordinal);
        Assert.Contains("-Method 'POST'", script, StringComparison.Ordinal);
        Assert.Contains("-Method 'PATCH'", script, StringComparison.Ordinal);
        Assert.DoesNotContain("'DELETE'", script, StringComparison.OrdinalIgnoreCase);

        var firstApplyGuard = script.IndexOf("if (-not $Apply)", StringComparison.Ordinal);
        var firstMutation = script.IndexOf("-Method 'POST'", StringComparison.Ordinal);
        var servicePrincipalPatch = script.IndexOf("-Method 'PATCH'", StringComparison.Ordinal);
        Assert.True(
            firstApplyGuard >= 0 && firstApplyGuard < firstMutation && firstApplyGuard < servicePrincipalPatch);
    }

    [Fact]
    public void CloudApplicationContractIsExactAndSecretless()
    {
        var bootstrap = ReadScript("11-bootstrap-cloud-entra.ps1");
        var common = ReadScript("cloud-entra-common.ps1");
        var combined = bootstrap + common;

        Assert.Contains("AzureADMyOrg", combined, StringComparison.Ordinal);
        Assert.Contains("/signin-oidc", bootstrap, StringComparison.Ordinal);
        Assert.Contains("/signout-callback-oidc", bootstrap, StringComparison.Ordinal);
        Assert.Contains("/signout-oidc", bootstrap, StringComparison.Ordinal);
        Assert.DoesNotContain("localhost", bootstrap, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("SecretNotes.Reader", combined, StringComparison.Ordinal);
        Assert.Contains("allowedMemberTypes = @('User')", bootstrap, StringComparison.Ordinal);
        Assert.Contains("appRoleAssignmentRequired = $true", bootstrap, StringComparison.Ordinal);
        Assert.Contains("requiredResourceAccess = @()", bootstrap, StringComparison.Ordinal);
        Assert.Contains("passwordCredentials = @()", bootstrap, StringComparison.Ordinal);
        Assert.Contains("keyCredentials = @()", bootstrap, StringComparison.Ordinal);
        Assert.Contains("enableAccessTokenIssuance = $false", bootstrap, StringComparison.Ordinal);
        Assert.Contains("enableIdTokenIssuance = $false", bootstrap, StringComparison.Ordinal);
        Assert.Contains("isFallbackPublicClient = $false", bootstrap, StringComparison.Ordinal);

        Assert.Contains("cloud-password-credential-present", common, StringComparison.Ordinal);
        Assert.Contains("cloud-key-credential-present", common, StringComparison.Ordinal);
        Assert.Contains("cloud-api-permission-present", common, StringComparison.Ordinal);
        Assert.Contains("cloud-redirect-uri-mismatch", common, StringComparison.Ordinal);
        Assert.Contains("cloud-assignment-required-invalid", common, StringComparison.Ordinal);
    }

    [Fact]
    public void ManagedIdentityFederationAndIdentitySeparationAreExact()
    {
        var bootstrap = ReadScript("11-bootstrap-cloud-entra.ps1");
        var validator = ReadScript("12-validate-cloud-entra.ps1");
        var common = ReadScript("cloud-entra-common.ps1");
        var combined = bootstrap + validator + common;

        Assert.Contains(
            "https://login.microsoftonline.com/$tenantId/v2.0",
            bootstrap,
            StringComparison.Ordinal);
        Assert.Contains("subject = $webAppPrincipalId", bootstrap, StringComparison.Ordinal);
        Assert.Contains("api://AzureADTokenExchange", combined, StringComparison.Ordinal);
        Assert.Contains(
            "web-app-system-assigned-managed-identity",
            combined,
            StringComparison.Ordinal);
        Assert.Contains("$LocalDevelopmentAppClientId", combined, StringComparison.Ordinal);
        Assert.Contains("$DeploymentAppClientId", combined, StringComparison.Ordinal);
        Assert.Contains("$cloudAppClientId", combined, StringComparison.Ordinal);
        Assert.Contains("$webAppPrincipalId", combined, StringComparison.Ordinal);
        Assert.Contains("application-app-id-reused", combined, StringComparison.Ordinal);
        Assert.Contains("application-object-id-reused", combined, StringComparison.Ordinal);
        Assert.Contains("service-principal-object-id-reused", combined, StringComparison.Ordinal);
        Assert.Contains("cloud-identity-separation-valid", combined, StringComparison.Ordinal);
        Assert.Contains("web-app-key-vault-rbac-absent", validator, StringComparison.Ordinal);
    }

    [Fact]
    public void IdentityResolutionAndSeparationUseMatchingIdentifierDomains()
    {
        var bootstrap = ReadScript("11-bootstrap-cloud-entra.ps1");
        var validator = ReadScript("12-validate-cloud-entra.ps1");
        var common = ReadScript("cloud-entra-common.ps1");
        var scripts = bootstrap + validator;

        Assert.Contains("function Get-IdentityApplicationState", common, StringComparison.Ordinal);
        Assert.Contains("'--query', '{id:id,appId:appId}'", common, StringComparison.Ordinal);
        Assert.Contains("function Get-ApplicationServicePrincipalState", common, StringComparison.Ordinal);
        Assert.Contains("function Get-ManagedIdentityServicePrincipalState", common, StringComparison.Ordinal);
        Assert.Contains(
            "'--query', '{id:id,appId:appId,servicePrincipalType:servicePrincipalType}'",
            common,
            StringComparison.Ordinal);
        Assert.Contains("$localApplication = Get-IdentityApplicationState", scripts, StringComparison.Ordinal);
        Assert.Contains("$deploymentApplication = Get-IdentityApplicationState", scripts, StringComparison.Ordinal);
        Assert.Contains("$deploymentServicePrincipal = Get-ApplicationServicePrincipalState", scripts, StringComparison.Ordinal);
        Assert.Contains("$managedIdentityServicePrincipal = Get-ManagedIdentityServicePrincipalState", scripts, StringComparison.Ordinal);
        Assert.Contains("Assert-CloudIdentitySeparation", scripts, StringComparison.Ordinal);
        Assert.Contains(
            "@($localApplicationAppId, $deploymentApplicationAppId, $cloudApplicationAppId, $managedIdentityServicePrincipalAppId)",
            common,
            StringComparison.Ordinal);
        Assert.Contains(
            "@($localApplicationObjectId, $deploymentApplicationObjectId, $cloudApplicationObjectId)",
            common,
            StringComparison.Ordinal);
        Assert.Contains(
            "@($deploymentServicePrincipalObjectId, $cloudServicePrincipalObjectId, $managedIdentityServicePrincipalObjectId)",
            common,
            StringComparison.Ordinal);
        Assert.DoesNotMatch(
            @"(?im)^\s*\[string\]::Equals\([^\r\n]*(?:principalId[^\r\n]*ClientId|ClientId[^\r\n]*principalId)",
            scripts + common);
        Assert.DoesNotMatch(
            @"(?im)^\s*\[string\]::Equals\([^\r\n]*cloudServicePrincipal(?:Id|ObjectId)[^\r\n]*ClientId",
            scripts + common);
    }

    [Fact]
    public void ServicePrincipalCreationIsMinimalOwnerGatedAndBoundedlyValidated()
    {
        var bootstrap = ReadScript("11-bootstrap-cloud-entra.ps1");
        var common = ReadScript("cloud-entra-common.ps1");
        var document = Regex.Match(
            bootstrap,
            @"(?s)\$servicePrincipalDocument\s*=\s*\[ordered\]@\{(?<body>.*?)\r?\n\s*\}");

        Assert.True(document.Success);
        Assert.Equal("appId = $cloudAppClientId", document.Groups["body"].Value.Trim());
        Assert.Contains("$servicePrincipalCreated = $false", bootstrap, StringComparison.Ordinal);
        Assert.Contains("if ($servicePrincipalCreated)", bootstrap, StringComparison.Ordinal);
        Assert.Matches(
            @"(?s)if \(\$servicePrincipalCreated\).*?appRoleAssignmentRequired\s*=\s*\$true.*?-Method 'PATCH'.*?servicePrincipals/\$createdServicePrincipalId.*?Invoke-BoundedDiscovery",
            bootstrap);

        var servicePrincipalPost = bootstrap.IndexOf(
            "-Url 'https://graph.microsoft.com/v1.0/servicePrincipals'",
            StringComparison.Ordinal);
        var ownerGate = bootstrap.LastIndexOf("if (-not $Apply)", servicePrincipalPost, StringComparison.Ordinal);
        var servicePrincipalPatch = bootstrap.IndexOf("-Method 'PATCH'", servicePrincipalPost, StringComparison.Ordinal);
        Assert.True(ownerGate >= 0 && ownerGate < servicePrincipalPost && servicePrincipalPost < servicePrincipalPatch);

        Assert.Contains("servicePrincipalType:servicePrincipalType", common, StringComparison.Ordinal);
        Assert.Contains("accountEnabled:accountEnabled", common, StringComparison.Ordinal);
        Assert.Contains("appRoleAssignmentRequired:appRoleAssignmentRequired", common, StringComparison.Ordinal);
        Assert.Contains("passwordCredentials:passwordCredentials", common, StringComparison.Ordinal);
        Assert.Contains("keyCredentials:keyCredentials", common, StringComparison.Ordinal);
        Assert.Contains("Assert-EmptyArrayProperty $servicePrincipal 'passwordCredentials'", common, StringComparison.Ordinal);
        Assert.Contains("Assert-EmptyArrayProperty $servicePrincipal 'keyCredentials'", common, StringComparison.Ordinal);
        Assert.Matches(
            @"(?s)else\s*\{\s*\$cloudServicePrincipal\s*=\s*Assert-CloudServicePrincipalState",
            bootstrap);
    }

    [Fact]
    public void ReadOnlyValidatorContainsNoMutationPath()
    {
        var validator = ReadScript("12-validate-cloud-entra.ps1");

        Assert.DoesNotContain("[switch] $Apply", validator, StringComparison.Ordinal);
        Assert.DoesNotContain("Invoke-AzureMutation", validator, StringComparison.Ordinal);
        Assert.DoesNotContain("'create'", validator, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("'delete'", validator, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("'patch'", validator, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("'post'", validator, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void RuntimeBicepReplacesOnlyTheExactFiveSettings()
    {
        var main = ReadRepositoryFile("infra", "main.bicep");
        var module = ReadRepositoryFile("infra", "modules", "web-app-runtime-config.bicep");

        Assert.Contains("param configureCloudRuntime bool = false", main, StringComparison.Ordinal);
        Assert.Contains("if (configureCloudRuntime)", main, StringComparison.Ordinal);
        Assert.Contains("existingWebApp", module, StringComparison.Ordinal);
        Assert.Contains("existing =", module, StringComparison.Ordinal);
        Assert.Contains("name: 'appsettings'", module, StringComparison.Ordinal);

        var properties = Regex.Match(
            module,
            @"(?s)properties:\s*\{(?<settings>.*?)\n\s*\}\s*\n\}");
        Assert.True(properties.Success);
        var settingLines = properties.Groups["settings"].Value
            .Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => line.Contains(':', StringComparison.Ordinal))
            .ToArray();
        Assert.Equal(5, settingLines.Length);
        Assert.Contains("ASPNETCORE_ENVIRONMENT: 'Production'", settingLines);
        Assert.Contains("AzureAd__TenantId: cloudTenantId", settingLines);
        Assert.Contains("AzureAd__ClientId: cloudAppClientId", settingLines);
        Assert.Contains(
            "AzureAd__ClientCredentials__0__SourceType: 'SignedAssertionFromManagedIdentity'",
            settingLines);
        Assert.Contains("NoteContent__Provider: 'InMemory'", settingLines);
        Assert.DoesNotContain("ManagedIdentityClientId", module, StringComparison.Ordinal);
        Assert.DoesNotContain("ClientSecret", module, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Certificate", module, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("@Microsoft.KeyVault", module, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("connectionStrings", module, StringComparison.OrdinalIgnoreCase);

        foreach (var forbidden in new[]
        {
            "Microsoft.Insights",
            "Microsoft.OperationalInsights",
            "slots",
            "virtualNetwork",
            "privateEndpoint",
            "ipSecurityRestrictions",
            "scmIpSecurityRestrictions",
            "cors",
            "basicPublishingCredentialsPolicies"
        })
        {
            Assert.DoesNotContain(forbidden, module, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void RuntimeDeploymentRequiresApplyAndVerifiesSecurityBoundary()
    {
        var script = ReadScript("13-cloud-runtime-config-deploy.ps1");

        Assert.Contains("[switch] $WhatIf", script, StringComparison.Ordinal);
        Assert.Contains("[switch] $Apply", script, StringComparison.Ordinal);
        Assert.Contains("if (-not $Apply)", script, StringComparison.Ordinal);
        Assert.Contains("cloud-runtime-apply-required", script, StringComparison.Ordinal);
        Assert.Contains("'deployment', 'group', 'what-if'", script, StringComparison.Ordinal);
        Assert.Contains("'deployment', 'group', 'create'", script, StringComparison.Ordinal);
        Assert.Contains("SignedAssertionFromManagedIdentity", script, StringComparison.Ordinal);
        Assert.Contains("NoteContent__Provider = 'InMemory'", script, StringComparison.Ordinal);
        Assert.Contains("ManagedIdentityClientId", script, StringComparison.Ordinal);
        Assert.Contains("publishing-credentials-disabled", script, StringComparison.Ordinal);
        Assert.Contains("key-vault-rbac-absent", script, StringComparison.Ordinal);
        Assert.Contains("connection-string", script, StringComparison.Ordinal);
    }

    [Fact]
    public void PostDeploymentValidationDoesNotFollowRedirectsOrExposeResponses()
    {
        var script = ReadScript("14-cloud-application-validate.ps1");

        Assert.Contains("AllowAutoRedirect = $false", script, StringComparison.Ordinal);
        Assert.Contains("FromSeconds(15)", script, StringComparison.Ordinal);
        Assert.Contains("MaxAttempts = 4", script, StringComparison.Ordinal);
        Assert.Contains("[Net.HttpStatusCode]::OK", script, StringComparison.Ordinal);
        Assert.Contains("[Net.HttpStatusCode]::Redirect", script, StringComparison.Ordinal);
        Assert.Contains("login.microsoftonline.com", script, StringComparison.Ordinal);
        Assert.Contains("/oauth2/v2\\.0/authorize$", script, StringComparison.Ordinal);
        Assert.Contains("public-home-valid", script, StringComparison.Ordinal);
        Assert.Contains("public-health-valid", script, StringComparison.Ordinal);
        Assert.Contains("anonymous-notes-challenge-valid", script, StringComparison.Ordinal);
        Assert.Contains("'webapp', 'config', 'connection-string', 'list'", script, StringComparison.Ordinal);
        Assert.Contains("if ($connectionStrings.Count -ne 0)", script, StringComparison.Ordinal);
        Assert.Contains("connection-strings-absent", script, StringComparison.Ordinal);
        Assert.DoesNotContain("response.Content", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Headers.Location.ToString", script, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void CommittedCloudFixturesContainOnlyPlaceholders()
    {
        var example = ReadRepositoryFile(
            "infra",
            "environments",
            "development.example.bicepparam");
        var module = ReadRepositoryFile("infra", "modules", "web-app-runtime-config.bicep");
        var scripts = string.Join(Environment.NewLine, ScriptNames.Select(ReadScript));

        Assert.Contains("<set-private-cloud-tenant-id>", example, StringComparison.Ordinal);
        Assert.Contains("<set-private-cloud-app-client-id>", example, StringComparison.Ordinal);
        Assert.DoesNotMatch(
            @"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b",
            example + module + scripts);
        Assert.DoesNotMatch(@"(?i)https://[a-z0-9-]+\.azurewebsites\.net", example + module);
        Assert.DoesNotMatch(@"(?i)https://[a-z0-9-]+\.vault\.azure\.net", example + module);
    }

    [Fact]
    public void RepositoryContainsOnlyTheCanonicalBicepParameterExample()
    {
        Assert.False(File.Exists(GetRepositoryPath(".azure", "deployment-plan.md")));

        var environmentDirectory = GetRepositoryPath("infra", "environments");
        var examples = Directory.GetFiles(environmentDirectory, "*example*")
            .Where(path => path.Contains("bicepparam", StringComparison.OrdinalIgnoreCase))
            .Select(Path.GetFileName)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(new[] { "development.example.bicepparam" }, examples);
        Assert.False(File.Exists(GetRepositoryPath(
            "infra",
            "environments",
            "development.bicepparam.example")));
    }

    [Fact]
    public void DeploymentWorkflowRemainsManualOnly()
    {
        var workflow = ReadRepositoryFile(".github", "workflows", "deploy-webapp.yml");

        var trigger = Regex.Match(workflow, @"(?ms)^on:\s*\r?\n(?<body>.*?)^permissions:");
        Assert.True(trigger.Success);
        Assert.Equal(
            new[] { "workflow_dispatch:" },
            trigger.Groups["body"].Value
                .Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries)
                .Select(line => line.Trim())
                .Where(line => !line.StartsWith('#'))
                .ToArray());
        Assert.Contains("environment: dev", workflow, StringComparison.Ordinal);
        Assert.Contains("id-token: write", workflow, StringComparison.Ordinal);
        Assert.Contains("contents: read", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("az deployment", workflow, StringComparison.OrdinalIgnoreCase);
    }

    private static string ReadScript(string fileName) =>
        ReadRepositoryFile("infra", "scripts", fileName);

    private static string ReadRepositoryFile(params string[] relativeSegments) =>
        File.ReadAllText(GetRepositoryPath(relativeSegments));

    private static string GetRepositoryPath(params string[] relativeSegments)
    {
        var segments = new[]
        {
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            ".."
        }.Concat(relativeSegments).ToArray();

        return Path.GetFullPath(Path.Combine(segments));
    }
}
