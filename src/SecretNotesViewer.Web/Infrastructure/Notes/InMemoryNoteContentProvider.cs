using SecretNotesViewer.Web.Application.Notes;

namespace SecretNotesViewer.Web.Infrastructure.Notes;

public sealed class InMemoryNoteContentProvider : INoteContentProvider
{
    public ValueTask<string> GetContentAsync(
        NoteId noteId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (noteId == NoteId.Operations)
        {
            return ValueTask.FromResult("Synthetic operations note content.");
        }

        if (noteId == NoteId.Integration)
        {
            return ValueTask.FromResult("Synthetic integration note content.");
        }

        if (noteId == NoteId.Recovery)
        {
            return ValueTask.FromResult("Synthetic recovery note content.");
        }

        throw new InvalidOperationException("Content is unavailable for a known note.");
    }
}
