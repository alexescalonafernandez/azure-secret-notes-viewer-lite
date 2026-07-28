namespace SecretNotesViewer.Web.Application.Notes;

public interface INoteContentProvider
{
    ValueTask<string> GetContentAsync(
        NoteId noteId,
        CancellationToken cancellationToken = default);
}
