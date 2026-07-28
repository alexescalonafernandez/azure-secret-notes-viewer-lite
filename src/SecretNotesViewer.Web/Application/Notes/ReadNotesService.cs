namespace SecretNotesViewer.Web.Application.Notes;

public sealed class ReadNotesService(
    INoteContentProvider contentProvider)
    : IReadNotesService
{
    public async Task<IReadOnlyList<NoteItem>> GetAllAsync(
        CancellationToken cancellationToken = default)
    {
        var notes = new NoteItem[ClosedNoteCatalog.Definitions.Count];

        for (var index = 0; index < ClosedNoteCatalog.Definitions.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var definition = ClosedNoteCatalog.Definitions[index];
            var content = await contentProvider.GetContentAsync(
                definition.Id,
                cancellationToken);

            notes[index] = new NoteItem(
                definition.Id,
                definition.DisplayName,
                content);
        }

        return Array.AsReadOnly(notes);
    }
}
