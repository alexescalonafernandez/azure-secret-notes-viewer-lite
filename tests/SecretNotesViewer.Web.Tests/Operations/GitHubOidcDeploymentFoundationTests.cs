using System.Text.RegularExpressions;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Operations;

public sealed class GitHubOidcDeploymentFoundationTests
{
    private const string ExpectedIssuer =
        "https://token.actions.githubusercontent.com";
    private const string ExpectedSubject =
        "repo:alexescalonafernandez/azure-secret-notes-viewer-lite:environment:dev";
    private const string ExpectedAudience = "api://AzureADTokenExchange";

    [Fact]
    public void WorkflowIsManualOnlyAndLeastPrivilege()
    {
        var workflow = ReadRepositoryFile(
            ".github",
            "workflows",
            "deploy-webapp.yml");

        var triggerBlock = ExtractBlock(workflow, "on", "permissions");
        Assert.Matches(@"(?m)^  workflow_dispatch:\s*$", triggerBlock);
        Assert.DoesNotMatch(
            @"(?m)^  (push|pull_request|schedule|release|workflow_run):",
            triggerBlock);
        Assert.Equal(
            new[] { "workflow_dispatch:" },
            ContentLines(triggerBlock));

        var permissionsBlock = ExtractBlock(workflow, "permissions", "jobs");
        Assert.Equal(
            new[] { "id-token: write", "contents: read" },
            ContentLines(permissionsBlock));

        Assert.Contains("environment: dev", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("permissions: write-all", workflow, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void WorkflowBuildsTestsPublishesAndDeploysThroughOidc()
    {
        var workflow = ReadRepositoryFile(
            ".github",
            "workflows",
            "deploy-webapp.yml");

        Assert.Contains("actions/checkout@v4", workflow, StringComparison.Ordinal);
        Assert.Contains("actions/setup-dotnet@v4", workflow, StringComparison.Ordinal);
        Assert.Contains("dotnet-version: ${{ vars.DOTNET_VERSION }}", workflow, StringComparison.Ordinal);
        Assert.Contains("[ \"$DOTNET_VERSION\" != \"10.0.x\" ]", workflow, StringComparison.Ordinal);
        Assert.Contains(
            "[ \"$PROJECT_PATH\" != \"src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj\" ]",
            workflow,
            StringComparison.Ordinal);
        Assert.Contains("dotnet restore SecretNotesViewer.slnx", workflow, StringComparison.Ordinal);
        Assert.Contains(
            "dotnet build SecretNotesViewer.slnx --configuration Release --no-restore",
            workflow,
            StringComparison.Ordinal);
        Assert.Contains(
            "dotnet test SecretNotesViewer.slnx --configuration Release --no-build",
            workflow,
            StringComparison.Ordinal);
        Assert.Contains(
            "dotnet publish \"${{ vars.PROJECT_PATH }}\" --configuration Release --no-build",
            workflow,
            StringComparison.Ordinal);
        Assert.Contains("azure/login@v2", workflow, StringComparison.Ordinal);
        Assert.Contains("azure/webapps-deploy@v3", workflow, StringComparison.Ordinal);
        Assert.Contains("AZURE_CLIENT_ID", workflow, StringComparison.Ordinal);
        Assert.Contains("AZURE_TENANT_ID", workflow, StringComparison.Ordinal);
        Assert.Contains("AZURE_SUBSCRIPTION_ID", workflow, StringComparison.Ordinal);
        Assert.Contains("AZURE_WEBAPP_NAME", workflow, StringComparison.Ordinal);
        Assert.Contains("--connect-timeout 5", workflow, StringComparison.Ordinal);
        Assert.Contains("--max-time 15", workflow, StringComparison.Ordinal);
        Assert.Contains("for attempt in {1..12}", workflow, StringComparison.Ordinal);
        Assert.Contains("public-health-valid", workflow, StringComparison.Ordinal);

        var maskIndex = workflow.IndexOf("::add-mask::", StringComparison.Ordinal);
        var loginIndex = workflow.IndexOf("azure/login@v2", StringComparison.Ordinal);
        Assert.True(maskIndex >= 0 && maskIndex < loginIndex);
    }

    [Fact]
    public void WorkflowContainsNoLongLivedOrBasicCredentialPath()
    {
        var workflow = ReadRepositoryFile(
            ".github",
            "workflows",
            "deploy-webapp.yml");

        foreach (var forbidden in new[]
        {
            "publish-profile",
            "AZURE_CREDENTIALS",
            "client-secret",
            "SCM_",
            "ftp",
            "basic-auth",
            "az webapp config",
            "az deployment",
            "az ad "
        })
        {
            Assert.DoesNotContain(forbidden, workflow, StringComparison.OrdinalIgnoreCase);
        }

        var actions = Regex.Matches(workflow, @"(?m)^\s*uses:\s*(\S+)\s*$")
            .Select(match => match.Groups[1].Value)
            .ToArray();
        Assert.Equal(
            new[]
            {
                "actions/checkout@v4",
                "actions/setup-dotnet@v4",
                "azure/login@v2",
                "azure/webapps-deploy@v3"
            },
            actions);
    }

    [Theory]
    [InlineData("09-bootstrap-github-oidc.ps1")]
    [InlineData("10-validate-github-oidc.ps1")]
    public void ScriptsEncodeExactTrustAndLeastPrivilege(string fileName)
    {
        var script = ReadRepositoryFile("infra", "scripts", fileName);

        Assert.Contains(ExpectedIssuer, script, StringComparison.Ordinal);
        Assert.Contains(ExpectedSubject, script, StringComparison.Ordinal);
        Assert.Contains(ExpectedAudience, script, StringComparison.Ordinal);
        Assert.StartsWith("#requires -Version 7.0", script, StringComparison.Ordinal);
        Assert.Contains("Website Contributor", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Web/sites", script, StringComparison.Ordinal);
        Assert.Contains("deployment-key-vault-rbac-absent", script, StringComparison.Ordinal);
        Assert.Contains("[Parameter(Mandatory)]", script, StringComparison.Ordinal);
        Assert.Contains("$DeploymentAppRegistrationName", script, StringComparison.Ordinal);
        Assert.Contains("$LocalDevelopmentAppClientId", script, StringComparison.Ordinal);

        Assert.DoesNotContain("Invoke-Expression", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("--output', 'tsv", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Key Vault Contributor", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Key Vault Secrets", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Contributor'", script.Replace("Website Contributor'", string.Empty), StringComparison.Ordinal);
    }

    [Fact]
    public void BootstrapRequiresExplicitMutationApproval()
    {
        var script = ReadRepositoryFile(
            "infra",
            "scripts",
            "09-bootstrap-github-oidc.ps1");

        Assert.Contains("[switch] $Apply", script, StringComparison.Ordinal);
        Assert.Contains("if (-not $Apply)", script, StringComparison.Ordinal);
        Assert.Contains("github-oidc-apply-required", script, StringComparison.Ordinal);
        Assert.Contains("github-oidc-bootstrap-valid", script, StringComparison.Ordinal);

        var roleCreation = Regex.Match(
            script,
            @"(?s)'role', 'assignment', 'create',(?<arguments>.*?)'--only-show-errors'");
        Assert.True(roleCreation.Success);
        Assert.Contains(
            "'--scope', $webAppScope",
            roleCreation.Groups["arguments"].Value,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "'--scope', $ResourceGroupName",
            roleCreation.Groups["arguments"].Value,
            StringComparison.Ordinal);
    }

    [Fact]
    public void ValidationChecksIdentitySeparationAndNoClientSecret()
    {
        var script = ReadRepositoryFile(
            "infra",
            "scripts",
            "10-validate-github-oidc.ps1");

        Assert.Contains("local-development-identity-reused", script, StringComparison.Ordinal);
        Assert.Contains("webAppPrincipalId", script, StringComparison.Ordinal);
        Assert.Contains("deployment-client-secret-present", script, StringComparison.Ordinal);
        Assert.Contains("deployment-broader-rbac-absent", script, StringComparison.Ordinal);
        Assert.Contains("github-oidc-validation-valid", script, StringComparison.Ordinal);
    }

    private static string ExtractBlock(
        string document,
        string startKey,
        string endKey)
    {
        var match = Regex.Match(
            document,
            $@"(?ms)^{Regex.Escape(startKey)}:\s*\r?\n(?<block>.*?)^{Regex.Escape(endKey)}:");

        Assert.True(match.Success, $"Missing {startKey} block.");
        return match.Groups["block"].Value;
    }

    private static string[] ContentLines(string block)
    {
        return block
            .Split(new[] { "\r\n", "\n" }, StringSplitOptions.None)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#'))
            .ToArray();
    }

    private static string ReadRepositoryFile(params string[] relativeSegments)
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

        return File.ReadAllText(Path.GetFullPath(Path.Combine(segments)));
    }
}
