namespace SecretNotesViewer.Web.Application.Notes;

public static class ClosedNoteCatalog
{
    private static readonly IReadOnlyList<NoteDefinition> definitions =
        Array.AsReadOnly(
            new[]
            {
                new NoteDefinition(NoteId.Operations, "Operations note"),
                new NoteDefinition(NoteId.Integration, "Integration note"),
                new NoteDefinition(NoteId.Recovery, "Recovery note")
            });

    public static IReadOnlyList<NoteDefinition> Definitions => definitions;
}
