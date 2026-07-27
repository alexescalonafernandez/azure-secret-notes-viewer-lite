using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using SecretNotesViewer.Web.Authorization;
using SecretNotesViewer.Web.Tests.Infrastructure;
using Xunit;

namespace SecretNotesViewer.Web.Tests;

public sealed class NotesAuthorizationTests(
    SecretNotesWebApplicationFactory factory)
    : IClassFixture<SecretNotesWebApplicationFactory>
{
    [Fact]
    public async Task Home_IsPublic()
    {
        using var client = CreateClient();

        var response = await client.GetAsync("/");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Privacy_IsPublic()
    {
        using var client = CreateClient();

        var response = await client.GetAsync("/Privacy");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Health_IsPublic()
    {
        using var client = CreateClient();

        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Notes_AnonymousRequest_IsChallenged()
    {
        using var client = CreateClient();

        var response = await client.GetAsync("/Notes");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Notes_AuthenticatedWithoutRoles_IsForbidden()
    {
        using var client = CreateClient();
        using var request = CreateAuthenticatedRequest();

        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Notes_AuthenticatedWithUnrelatedRole_IsForbidden()
    {
        using var client = CreateClient();
        using var request = CreateAuthenticatedRequest("Unrelated.Reader");

        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Notes_AuthenticatedWithRequiredRole_IsSuccessful()
    {
        using var response = await GetAuthorizedNotesAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Notes_AuthorizedResponse_ContainsProtectedAreaMarker()
    {
        using var response = await GetAuthorizedNotesAsync();
        var content = await response.Content.ReadAsStringAsync();

        Assert.Contains("Protected notes area", content);
    }

    [Fact]
    public async Task Notes_AuthorizedResponse_ContainsThreeSyntheticLabels()
    {
        using var response = await GetAuthorizedNotesAsync();
        var content = await response.Content.ReadAsStringAsync();

        Assert.Contains("demo-operations-note", content);
        Assert.Contains("demo-integration-note", content);
        Assert.Contains("demo-recovery-note", content);
    }

    [Fact]
    public async Task Notes_AuthorizedResponse_ContainsKeyVaultDeferral()
    {
        using var response = await GetAuthorizedNotesAsync();
        var content = await response.Content.ReadAsStringAsync();

        Assert.Contains(
            "Secret value retrieval is deferred to a later Key Vault milestone.",
            content);
    }

    [Fact]
    public async Task Notes_AuthorizedResponse_DoesNotRenderSyntheticSubject()
    {
        using var response = await GetAuthorizedNotesAsync();
        var content = await response.Content.ReadAsStringAsync();

        Assert.DoesNotContain("synthetic-subject", content);
    }

    [Fact]
    public async Task Notes_AuthorizedResponse_UsesNoStore()
    {
        using var response = await GetAuthorizedNotesAsync();

        Assert.Contains(
            "no-store",
            response.Headers.CacheControl?.ToString() ?? string.Empty,
            StringComparison.OrdinalIgnoreCase);
    }

    private HttpClient CreateClient()
    {
        return factory.CreateClient(
            new WebApplicationFactoryClientOptions
            {
                AllowAutoRedirect = false
            });
    }

    private async Task<HttpResponseMessage> GetAuthorizedNotesAsync()
    {
        using var client = CreateClient();
        using var request = CreateAuthenticatedRequest(AppRoles.SecretNotesReader);

        return await client.SendAsync(request);
    }

    private static HttpRequestMessage CreateAuthenticatedRequest(string? role = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/Notes");
        request.Headers.Add(TestAuthenticationHandler.AuthenticatedHeader, "true");

        if (role is not null)
        {
            request.Headers.Add(TestAuthenticationHandler.RolesHeader, role);
        }

        return request;
    }
}
