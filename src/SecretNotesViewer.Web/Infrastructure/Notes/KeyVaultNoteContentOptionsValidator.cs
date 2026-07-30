using Microsoft.Extensions.Options;

namespace SecretNotesViewer.Web.Infrastructure.Notes;

public sealed class KeyVaultNoteContentOptionsValidator
    : IValidateOptions<KeyVaultNoteContentOptions>
{
    private static readonly HashSet<string> PublicLogicalIds = new(
        [
            "demo-operations-note",
            "demo-integration-note",
            "demo-recovery-note"
        ],
        StringComparer.OrdinalIgnoreCase);

    public ValidateOptionsResult Validate(
        string? name,
        KeyVaultNoteContentOptions options)
    {
        if (!TryGetValidVaultUri(options.VaultUri, out _))
        {
            return ValidateOptionsResult.Fail(
                "The Key Vault URI configuration is invalid.");
        }

        var physicalNames = new[]
        {
            options.SecretNames.Operations,
            options.SecretNames.Integration,
            options.SecretNames.Recovery
        };

        if (physicalNames.Any(string.IsNullOrWhiteSpace))
        {
            return ValidateOptionsResult.Fail(
                "A required Key Vault secret-name configuration is missing.");
        }

        var nonNullNames = physicalNames.Select(value => value!).ToArray();

        if (nonNullNames.Distinct(StringComparer.OrdinalIgnoreCase).Count()
            != nonNullNames.Length)
        {
            return ValidateOptionsResult.Fail(
                "Key Vault physical secret names must be distinct.");
        }

        if (nonNullNames.Any(PublicLogicalIds.Contains))
        {
            return ValidateOptionsResult.Fail(
                "A Key Vault physical secret-name configuration is invalid.");
        }

        return ValidateOptionsResult.Success;
    }

    internal static bool TryGetValidVaultUri(string? value, out Uri? vaultUri)
    {
        vaultUri = null;

        if (string.IsNullOrWhiteSpace(value)
            || !Uri.TryCreate(value, UriKind.Absolute, out var parsed)
            || parsed.Scheme != Uri.UriSchemeHttps
            || !string.IsNullOrEmpty(parsed.UserInfo)
            || !string.IsNullOrEmpty(parsed.Query)
            || !string.IsNullOrEmpty(parsed.Fragment))
        {
            return false;
        }

        vaultUri = parsed;
        return true;
    }
}
