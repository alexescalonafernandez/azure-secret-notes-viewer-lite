namespace SecretNotesViewer.Web.Application.Notes;

public sealed class NoteContentUnavailableException : Exception
{
    public NoteContentUnavailableException()
        : base("Note content is temporarily unavailable.")
    {
    }
}
