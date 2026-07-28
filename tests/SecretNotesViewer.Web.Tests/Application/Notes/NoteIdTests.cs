using SecretNotesViewer.Web.Application.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Application.Notes;

public sealed class NoteIdTests
{
    public static TheoryData<NoteId> KnownIds =>
        new()
        {
            NoteId.Operations,
            NoteId.Integration,
            NoteId.Recovery
        };

    [Theory]
    [MemberData(nameof(KnownIds))]
    public void TryParseKnown_KnownExactValue_ReturnsKnownId(NoteId expected)
    {
        var parsed = NoteId.TryParseKnown(expected.ToString(), out var actual);

        Assert.True(parsed);
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("\t")]
    [InlineData("unknown")]
    public void TryParseKnown_InvalidValue_IsRejected(string? value)
    {
        var parsed = NoteId.TryParseKnown(value, out var noteId);

        Assert.False(parsed);
        Assert.Equal(default, noteId);
    }

    [Theory]
    [MemberData(nameof(KnownIds))]
    public void TryParseKnown_DifferentlyCasedValue_IsRejected(NoteId knownId)
    {
        var parsed = NoteId.TryParseKnown(
            knownId.ToString().ToUpperInvariant(),
            out _);

        Assert.False(parsed);
    }

    [Theory]
    [MemberData(nameof(KnownIds))]
    public void TryParseKnown_PrefixedValue_IsRejected(NoteId knownId)
    {
        var parsed = NoteId.TryParseKnown($"prefix-{knownId}", out _);

        Assert.False(parsed);
    }

    [Theory]
    [MemberData(nameof(KnownIds))]
    public void TryParseKnown_SuffixedValue_IsRejected(NoteId knownId)
    {
        var parsed = NoteId.TryParseKnown($"{knownId}-suffix", out _);

        Assert.False(parsed);
    }

    [Fact]
    public void KnownIds_AreDistinct()
    {
        var ids = new HashSet<NoteId>(KnownIds);

        Assert.Equal(3, ids.Count);
    }

    [Theory]
    [InlineData("demo-operations-note", 0)]
    [InlineData("demo-integration-note", 1)]
    [InlineData("demo-recovery-note", 2)]
    public void ToString_ReturnsExactSafeLogicalValue(
        string expected,
        int knownIdIndex)
    {
        var knownId = knownIdIndex switch
        {
            0 => NoteId.Operations,
            1 => NoteId.Integration,
            2 => NoteId.Recovery,
            _ => throw new ArgumentOutOfRangeException(nameof(knownIdIndex))
        };

        Assert.Equal(expected, knownId.ToString());
    }
}
