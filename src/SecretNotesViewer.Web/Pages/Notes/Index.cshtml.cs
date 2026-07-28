using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using SecretNotesViewer.Web.Application.Notes;
using SecretNotesViewer.Web.Authorization;

namespace SecretNotesViewer.Web.Pages.Notes;

[Authorize(Policy = AuthorizationPolicies.ReadSecretNotes)]
[ResponseCache(
    Duration = 0,
    Location = ResponseCacheLocation.None,
    NoStore = true)]
public class IndexModel(
    IReadNotesService readNotesService)
    : PageModel
{
    public IReadOnlyList<NoteItem> Notes { get; private set; } =
        Array.Empty<NoteItem>();

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        Notes = await readNotesService.GetAllAsync(cancellationToken);
    }
}
