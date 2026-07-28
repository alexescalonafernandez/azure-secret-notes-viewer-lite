using SecretNotesViewer.Web.Application.Notes;
using SecretNotesViewer.Web.Infrastructure.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Infrastructure.Notes;

public sealed class InMemoryNoteContentProviderTests
{
    public static TheoryData<NoteId, string> KnownContent =>
        new()
        {
            {
                NoteId.Operations,
                "Synthetic operations note content."
            },
            {
                NoteId.Integration,
                "Synthetic integration note content."
            },
            {
                NoteId.Recovery,
                "Synthetic recovery note content."
            }
        };

    [Theory]
    [MemberData(nameof(KnownContent))]
    public async Task GetContentAsync_KnownId_ReturnsDeterministicContent(
        NoteId noteId,
        string expected)
    {
        var provider = new InMemoryNoteContentProvider();

        var first = await provider.GetContentAsync(noteId);
        var second = await provider.GetContentAsync(noteId);

        Assert.Equal(expected, first);
        Assert.Equal(first, second);
        Assert.False(string.IsNullOrWhiteSpace(first));
    }

    [Theory]
    [MemberData(nameof(KnownContent))]
    public async Task GetContentAsync_ContentContainsNoCredentialLikeStrings(
        NoteId noteId,
        string _)
    {
        var provider = new InMemoryNoteContentProvider();

        var content = await provider.GetContentAsync(noteId);

        Assert.DoesNotContain("credential", content, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("password", content, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token", content, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("connection string", content, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("secret=", content, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GetContentAsync_CanceledRequestThrowsSafely()
    {
        var provider = new InMemoryNoteContentProvider();
        using var cancellationSource = new CancellationTokenSource();
        cancellationSource.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            async () => await provider.GetContentAsync(
                NoteId.Operations,
                cancellationSource.Token));
    }

    [Fact]
    public async Task GetContentAsync_UnknownInternalIdThrowsGenericException()
    {
        var provider = new InMemoryNoteContentProvider();

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            async () => await provider.GetContentAsync(default));

        Assert.DoesNotContain("content.", exception.Message, StringComparison.OrdinalIgnoreCase);
    }
}
