namespace SecretNotesViewer.Web.Infrastructure.Notes;

public sealed class KeyVaultSecretNameOptions
{
    public string? Operations { get; init; }

    public string? Integration { get; init; }

    public string? Recovery { get; init; }
}
