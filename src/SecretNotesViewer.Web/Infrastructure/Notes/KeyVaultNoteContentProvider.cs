using Azure;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using SecretNotesViewer.Web.Application.Notes;

namespace SecretNotesViewer.Web.Infrastructure.Notes;

public sealed class KeyVaultNoteContentProvider : INoteContentProvider
{
    private readonly SecretClient secretClient;
    private readonly KeyVaultSecretNameOptions secretNames;

    public KeyVaultNoteContentProvider(
        SecretClient secretClient,
        KeyVaultNoteContentOptions options)
    {
        this.secretClient = secretClient;
        secretNames = options.SecretNames;
    }

    public async ValueTask<string> GetContentAsync(
        NoteId noteId,
        CancellationToken cancellationToken = default)
    {
        var physicalName = GetPhysicalName(noteId);

        try
        {
            var response = await secretClient.GetSecretAsync(
                physicalName,
                version: null,
                cancellationToken: cancellationToken);
            var content = response.Value.Value;

            if (string.IsNullOrWhiteSpace(content))
            {
                throw new NoteContentUnavailableException();
            }

            return content;
        }
        catch (RequestFailedException)
        {
            throw new NoteContentUnavailableException();
        }
        catch (AuthenticationFailedException)
        {
            throw new NoteContentUnavailableException();
        }
    }

    private string GetPhysicalName(NoteId noteId)
    {
        if (noteId == NoteId.Operations)
        {
            return secretNames.Operations!;
        }

        if (noteId == NoteId.Integration)
        {
            return secretNames.Integration!;
        }

        if (noteId == NoteId.Recovery)
        {
            return secretNames.Recovery!;
        }

        throw new InvalidOperationException(
            "Content is unavailable for a known note.");
    }
}
