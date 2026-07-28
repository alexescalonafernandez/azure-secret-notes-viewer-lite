using SecretNotesViewer.Web.Application.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Application.Notes;

public sealed class ReadNotesServiceTests
{
    [Fact]
    public async Task GetAllAsync_RequestsOnlyCatalogIdsInCatalogOrder()
    {
        var provider = new RecordingNoteContentProvider();
        var service = new ReadNotesService(provider);

        var notes = await service.GetAllAsync();

        var expectedIds = ClosedNoteCatalog.Definitions
            .Select(definition => definition.Id)
            .ToArray();
        Assert.Equal(expectedIds, provider.RequestedIds);
        Assert.DoesNotContain(default(NoteId), provider.RequestedIds);
        Assert.Equal(expectedIds, notes.Select(note => note.Id));
    }

    [Fact]
    public async Task GetAllAsync_MatchesContentToDefinitions()
    {
        var provider = new RecordingNoteContentProvider();
        var service = new ReadNotesService(provider);

        var notes = await service.GetAllAsync();

        Assert.Collection(
            notes,
            note => AssertNote(note, NoteId.Operations, "operations-content"),
            note => AssertNote(note, NoteId.Integration, "integration-content"),
            note => AssertNote(note, NoteId.Recovery, "recovery-content"));
    }

    [Fact]
    public async Task GetAllAsync_PropagatesCancellationToken()
    {
        var provider = new RecordingNoteContentProvider();
        var service = new ReadNotesService(provider);
        using var cancellationSource = new CancellationTokenSource();

        await service.GetAllAsync(cancellationSource.Token);

        Assert.All(
            provider.ReceivedTokens,
            token => Assert.Equal(cancellationSource.Token, token));
    }

    [Fact]
    public async Task GetAllAsync_CanceledRequestThrows()
    {
        var provider = new RecordingNoteContentProvider();
        var service = new ReadNotesService(provider);
        using var cancellationSource = new CancellationTokenSource();
        cancellationSource.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => service.GetAllAsync(cancellationSource.Token));
    }

    [Fact]
    public async Task GetAllAsync_ReturnsReadOnlyListThatCannotBeMutated()
    {
        var service = new ReadNotesService(
            new RecordingNoteContentProvider());

        IReadOnlyList<NoteItem> notes = await service.GetAllAsync();
        var mutableView = Assert.IsAssignableFrom<IList<NoteItem>>(notes);

        Assert.True(mutableView.IsReadOnly);
        Assert.Throws<NotSupportedException>(
            () => mutableView.Add(
                new NoteItem(NoteId.Operations, "Replacement", "replacement")));
    }

    private static void AssertNote(
        NoteItem note,
        NoteId expectedId,
        string expectedContent)
    {
        var definition = Assert.Single(
            ClosedNoteCatalog.Definitions,
            definition => definition.Id == expectedId);

        Assert.Equal(expectedId, note.Id);
        Assert.Equal(definition.DisplayName, note.DisplayName);
        Assert.Equal(expectedContent, note.Content);
    }

    private sealed class RecordingNoteContentProvider : INoteContentProvider
    {
        private static readonly IReadOnlyDictionary<NoteId, string> Content =
            new Dictionary<NoteId, string>
            {
                [NoteId.Operations] = "operations-content",
                [NoteId.Integration] = "integration-content",
                [NoteId.Recovery] = "recovery-content"
            };

        public List<NoteId> RequestedIds { get; } = [];

        public List<CancellationToken> ReceivedTokens { get; } = [];

        public ValueTask<string> GetContentAsync(
            NoteId noteId,
            CancellationToken cancellationToken = default)
        {
            RequestedIds.Add(noteId);
            ReceivedTokens.Add(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            return ValueTask.FromResult(Content[noteId]);
        }
    }
}
