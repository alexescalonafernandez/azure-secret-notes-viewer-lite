using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SecretNotesViewer.Web.Application.Notes;
using SecretNotesViewer.Web.Infrastructure.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Infrastructure.Notes;

public sealed class NoteContentProviderRegistrationTests
{
    [Fact]
    public void CommittedDefaultSelectsInMemoryProvider()
    {
        var configuration = new ConfigurationBuilder()
            .SetBasePath(GetWebProjectPath())
            .AddJsonFile("appsettings.json")
            .Build();

        using var provider = BuildProvider(configuration);

        Assert.IsType<InMemoryNoteContentProvider>(
            provider.GetRequiredService<INoteContentProvider>());
        Assert.Null(provider.GetService<AzureCliCredential>());
        Assert.Null(provider.GetService<SecretClient>());
    }

    [Fact]
    public void InMemoryDoesNotRequireKeyVaultConfiguration()
    {
        using var provider = BuildProvider(Configuration(("NoteContent:Provider", "InMemory")));

        Assert.IsType<InMemoryNoteContentProvider>(
            provider.GetRequiredService<INoteContentProvider>());
    }

    [Fact]
    public void KeyVaultRegistersOnlyKeyVaultProvider()
    {
        using var provider = BuildProvider(ValidKeyVaultConfiguration());

        var contentProviders = provider
            .GetServices<INoteContentProvider>()
            .ToArray();

        Assert.Single(contentProviders);
        Assert.IsType<KeyVaultNoteContentProvider>(contentProviders[0]);
        Assert.Null(provider.GetService<InMemoryNoteContentProvider>());
    }

    [Fact]
    public void KeyVaultRegistersOneReusableSecretClient()
    {
        using var provider = BuildProvider(ValidKeyVaultConfiguration());

        var first = provider.GetRequiredService<SecretClient>();
        var second = provider.GetRequiredService<SecretClient>();

        Assert.Same(first, second);
        Assert.Single(provider.GetServices<SecretClient>());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("unsupported")]
    public void MissingOrUnsupportedProviderFails(string? configuredProvider)
    {
        var configuration = configuredProvider is null
            ? Configuration()
            : Configuration(("NoteContent:Provider", configuredProvider));
        var services = new ServiceCollection();

        var exception = Assert.Throws<InvalidOperationException>(
            () => services.AddNoteContentProvider(configuration));

        Assert.Equal(
            "The configured note-content provider is unsupported.",
            exception.Message);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("relative-vault")]
    [InlineData("http://unit-test.invalid")]
    [InlineData("https://user@unit-test.invalid")]
    [InlineData("https://unit-test.invalid?query=value")]
    [InlineData("https://unit-test.invalid#fragment")]
    public void InvalidVaultUriFailsWithoutDisclosingValue(string? vaultUri)
    {
        var configuration = KeyVaultConfiguration(
            vaultUri,
            "private-operations",
            "private-integration",
            "private-recovery");

        var exception = ResolveValidationException(configuration);

        Assert.Contains("Key Vault URI configuration", exception.Message);
        if (!string.IsNullOrEmpty(vaultUri))
        {
            Assert.DoesNotContain(vaultUri, exception.Message);
        }
    }

    [Theory]
    [InlineData(null, "private-integration", "private-recovery")]
    [InlineData("private-operations", null, "private-recovery")]
    [InlineData("private-operations", "private-integration", null)]
    [InlineData(" ", "private-integration", "private-recovery")]
    public void MissingPhysicalNameFails(
        string? operations,
        string? integration,
        string? recovery)
    {
        var exception = ResolveValidationException(
            KeyVaultConfiguration(
                "https://unit-test.invalid",
                operations,
                integration,
                recovery));

        Assert.Contains(
            "required Key Vault secret-name configuration is missing",
            exception.Message);
    }

    [Fact]
    public void DuplicatePhysicalNamesFailCaseInsensitively()
    {
        var exception = ResolveValidationException(
            KeyVaultConfiguration(
                "https://unit-test.invalid",
                "private-name",
                "PRIVATE-NAME",
                "private-recovery"));

        Assert.Contains("physical secret names must be distinct", exception.Message);
        Assert.DoesNotContain("private-name", exception.Message);
    }

    [Theory]
    [InlineData("DEMO-OPERATIONS-NOTE", "private-integration", "private-recovery")]
    [InlineData("private-operations", "Demo-Integration-Note", "private-recovery")]
    [InlineData("private-operations", "private-integration", "demo-recovery-note")]
    public void PublicLogicalIdsCannotBePhysicalNames(
        string operations,
        string integration,
        string recovery)
    {
        var exception = ResolveValidationException(
            KeyVaultConfiguration(
                "https://unit-test.invalid",
                operations,
                integration,
                recovery));

        Assert.Contains(
            "physical secret-name configuration is invalid",
            exception.Message);
        Assert.DoesNotContain(operations, exception.Message);
        Assert.DoesNotContain(integration, exception.Message);
        Assert.DoesNotContain(recovery, exception.Message);
    }

    private static OptionsValidationException ResolveValidationException(
        IConfiguration configuration)
    {
        using var provider = BuildProvider(configuration);

        return Assert.Throws<OptionsValidationException>(
            () => provider.GetRequiredService<INoteContentProvider>());
    }

    private static ServiceProvider BuildProvider(IConfiguration configuration)
    {
        var services = new ServiceCollection();
        services.AddNoteContentProvider(configuration);
        return services.BuildServiceProvider();
    }

    private static IConfiguration ValidKeyVaultConfiguration()
    {
        return KeyVaultConfiguration(
            "https://unit-test.invalid",
            "private-operations",
            "private-integration",
            "private-recovery");
    }

    private static IConfiguration KeyVaultConfiguration(
        string? vaultUri,
        string? operations,
        string? integration,
        string? recovery)
    {
        return Configuration(
            ("NoteContent:Provider", "KeyVault"),
            ("KeyVault:VaultUri", vaultUri),
            ("KeyVault:SecretNames:Operations", operations),
            ("KeyVault:SecretNames:Integration", integration),
            ("KeyVault:SecretNames:Recovery", recovery));
    }

    private static IConfiguration Configuration(
        params (string Key, string? Value)[] values)
    {
        return new ConfigurationBuilder()
            .AddInMemoryCollection(
                values.ToDictionary(
                    item => item.Key,
                    item => item.Value))
            .Build();
    }

    private static string GetWebProjectPath()
    {
        return Path.GetFullPath(
            Path.Combine(
                AppContext.BaseDirectory,
                "..",
                "..",
                "..",
                "..",
                "..",
                "src",
                "SecretNotesViewer.Web"));
    }
}
