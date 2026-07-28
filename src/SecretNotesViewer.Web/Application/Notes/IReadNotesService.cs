namespace SecretNotesViewer.Web.Application.Notes;

public interface IReadNotesService
{
    Task<IReadOnlyList<NoteItem>> GetAllAsync(
        CancellationToken cancellationToken = default);
}
