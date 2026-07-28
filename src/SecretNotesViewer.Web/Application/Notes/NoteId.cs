namespace SecretNotesViewer.Web.Application.Notes;

public readonly record struct NoteId
{
    private const string OperationsValue = "demo-operations-note";
    private const string IntegrationValue = "demo-integration-note";
    private const string RecoveryValue = "demo-recovery-note";

    private readonly string? value;

    private NoteId(string value)
    {
        this.value = value;
    }

    public static NoteId Operations { get; } = new(OperationsValue);

    public static NoteId Integration { get; } = new(IntegrationValue);

    public static NoteId Recovery { get; } = new(RecoveryValue);

    public static bool TryParseKnown(string? value, out NoteId noteId)
    {
        noteId = value switch
        {
            OperationsValue => Operations,
            IntegrationValue => Integration,
            RecoveryValue => Recovery,
            _ => default
        };

        return value is OperationsValue or IntegrationValue or RecoveryValue;
    }

    public override string ToString()
    {
        return value ?? string.Empty;
    }
}
