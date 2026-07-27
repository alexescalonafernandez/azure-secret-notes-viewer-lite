using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using SecretNotesViewer.Web.Authorization;

namespace SecretNotesViewer.Web.Pages.Notes;

[Authorize(Policy = AuthorizationPolicies.ReadSecretNotes)]
[ResponseCache(
    Duration = 0,
    Location = ResponseCacheLocation.None,
    NoStore = true)]
public class IndexModel : PageModel
{
    public void OnGet()
    {
    }
}
