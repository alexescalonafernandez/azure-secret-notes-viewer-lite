using SecretNotesViewer.Web.Application.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Application.Notes;

public sealed class ClosedNoteCatalogTests
{
    [Fact]
    public void Definitions_ContainsExactlyThreeEntriesInRequiredOrder()
    {
        var definitions = ClosedNoteCatalog.Definitions;

        Assert.Equal(3, definitions.Count);
        Assert.Equal(NoteId.Operations, definitions[0].Id);
        Assert.Equal(NoteId.Integration, definitions[1].Id);
        Assert.Equal(NoteId.Recovery, definitions[2].Id);
    }

    [Fact]
    public void Definitions_ContainsUniqueIdsAndNonEmptyDisplayNames()
    {
        var definitions = ClosedNoteCatalog.Definitions;

        Assert.Equal(
            definitions.Count,
            definitions.Select(definition => definition.Id).Distinct().Count());
        Assert.All(
            definitions,
            definition => Assert.False(
                string.IsNullOrWhiteSpace(definition.DisplayName)));
    }

    [Fact]
    public void Definitions_CannotBeMutated()
    {
        var definitions = Assert.IsAssignableFrom<IList<NoteDefinition>>(
            ClosedNoteCatalog.Definitions);

        Assert.True(definitions.IsReadOnly);
        Assert.Throws<NotSupportedException>(
            () => definitions.Add(
                new NoteDefinition(NoteId.Operations, "Replacement")));
    }
}
