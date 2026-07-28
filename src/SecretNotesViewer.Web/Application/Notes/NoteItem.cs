namespace SecretNotesViewer.Web.Application.Notes;

public sealed record NoteItem(
    NoteId Id,
    string DisplayName,
    string Content);
