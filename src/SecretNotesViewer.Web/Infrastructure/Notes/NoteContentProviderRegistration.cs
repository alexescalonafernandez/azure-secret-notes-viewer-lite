using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Extensions.Options;
using SecretNotesViewer.Web.Application.Notes;

namespace SecretNotesViewer.Web.Infrastructure.Notes;

public static class NoteContentProviderRegistration
{
    public static IServiceCollection AddNoteContentProvider(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var provider = configuration[$"{NoteContentOptions.SectionName}:Provider"];

        if (string.Equals(provider, "InMemory", StringComparison.OrdinalIgnoreCase))
        {
            services.AddSingleton<INoteContentProvider, InMemoryNoteContentProvider>();
            return services;
        }

        if (!string.Equals(provider, "KeyVault", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                "The configured note-content provider is unsupported.");
        }

        services
            .AddOptions<KeyVaultNoteContentOptions>()
            .Bind(configuration.GetSection(KeyVaultNoteContentOptions.SectionName))
            .ValidateOnStart();
        services.AddSingleton<
            IValidateOptions<KeyVaultNoteContentOptions>,
            KeyVaultNoteContentOptionsValidator>();
        services.AddSingleton(
            provider => provider
                .GetRequiredService<IOptions<KeyVaultNoteContentOptions>>()
                .Value);
        services.AddSingleton<AzureCliCredential>();
        services.AddSingleton(
            provider =>
            {
                var options =
                    provider.GetRequiredService<KeyVaultNoteContentOptions>();
                KeyVaultNoteContentOptionsValidator.TryGetValidVaultUri(
                    options.VaultUri,
                    out var vaultUri);

                return new SecretClient(
                    vaultUri!,
                    provider.GetRequiredService<AzureCliCredential>());
            });
        services.AddSingleton<INoteContentProvider, KeyVaultNoteContentProvider>();

        return services;
    }
}
