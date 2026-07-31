namespace SecretNotesViewer.Web.Infrastructure.Notes;

public sealed class KeyVaultNoteContentOptions
{
    public const string SectionName = "KeyVault";

    public string? VaultUri { get; init; }

    public KeyVaultSecretNameOptions SecretNames { get; init; } = new();
}
