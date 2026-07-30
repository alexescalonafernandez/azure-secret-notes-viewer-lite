using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using SecretNotesViewer.Web.Application.Notes;
using SecretNotesViewer.Web.Infrastructure.Notes;
using Xunit;

namespace SecretNotesViewer.Web.Tests.Infrastructure.Notes;

public sealed class KeyVaultNoteContentProviderTests
{
    [Theory]
    [MemberData(nameof(KnownMappings))]
    public async Task KnownNoteRequestsOnlyConfiguredPhysicalName(
        NoteId noteId,
        string expectedPhysicalName)
    {
        var client = new StubSecretClient(
            (name, _, _) => ResponseWithValue(name, "value-from-key-vault"));
        var provider = CreateProvider(client);

        var result = await provider.GetContentAsync(noteId);

        Assert.Equal("value-from-key-vault", result);
        Assert.Equal(expectedPhysicalName, client.RequestedName);
        Assert.Null(client.RequestedVersion);
        Assert.Equal(1, client.CallCount);
    }

    [Fact]
    public async Task CancellationTokenReachesSecretClient()
    {
        using var source = new CancellationTokenSource();
        var client = new StubSecretClient(
            (name, _, _) => ResponseWithValue(name, "value"));
        var provider = CreateProvider(client);

        await provider.GetContentAsync(NoteId.Operations, source.Token);

        Assert.Equal(source.Token, client.RequestedCancellationToken);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task MissingValueProducesSafeException(string? value)
    {
        var client = new StubSecretClient(
            (name, _, _) => ResponseWithValue(name, value));
        var provider = CreateProvider(client);

        var exception = await Assert.ThrowsAsync<NoteContentUnavailableException>(
            async () => await provider.GetContentAsync(NoteId.Operations));

        AssertSafeException(exception);
    }

    [Fact]
    public async Task RequestFailureProducesSafeException()
    {
        var client = new StubSecretClient(
            (_, _, _) => throw new RequestFailedException(
                403,
                "raw request failure with private-operations"));
        var provider = CreateProvider(client);

        var exception = await Assert.ThrowsAsync<NoteContentUnavailableException>(
            async () => await provider.GetContentAsync(NoteId.Operations));

        AssertSafeException(exception);
    }

    [Fact]
    public async Task AuthenticationFailureProducesSafeException()
    {
        var client = new StubSecretClient(
            (_, _, _) => throw new AuthenticationFailedException(
                "raw authentication failure with unit-test.invalid"));
        var provider = CreateProvider(client);

        var exception = await Assert.ThrowsAsync<NoteContentUnavailableException>(
            async () => await provider.GetContentAsync(NoteId.Operations));

        AssertSafeException(exception);
    }

    [Fact]
    public async Task CallerCancellationRemainsCancellation()
    {
        using var source = new CancellationTokenSource();
        source.Cancel();
        var client = new StubSecretClient(
            (_, _, cancellationToken) =>
                throw new OperationCanceledException(cancellationToken));
        var provider = CreateProvider(client);

        var exception = await Assert.ThrowsAnyAsync<OperationCanceledException>(
            async () =>
                await provider.GetContentAsync(NoteId.Operations, source.Token));

        Assert.Equal(source.Token, exception.CancellationToken);
    }

    [Fact]
    public async Task UnknownNoteDoesNotCallSecretClient()
    {
        var client = new StubSecretClient(
            (_, _, _) => throw new InvalidOperationException(
                "The client must not be called."));
        var provider = CreateProvider(client);

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            async () => await provider.GetContentAsync(default));

        Assert.Equal(
            "Content is unavailable for a known note.",
            exception.Message);
        Assert.Equal(0, client.CallCount);
    }

    public static TheoryData<NoteId, string> KnownMappings =>
        new()
        {
            { NoteId.Operations, "private-operations" },
            { NoteId.Integration, "private-integration" },
            { NoteId.Recovery, "private-recovery" }
        };

    private static KeyVaultNoteContentProvider CreateProvider(
        SecretClient secretClient)
    {
        return new KeyVaultNoteContentProvider(
            secretClient,
            new KeyVaultNoteContentOptions
            {
                VaultUri = "https://unit-test.invalid",
                SecretNames = new KeyVaultSecretNameOptions
                {
                    Operations = "private-operations",
                    Integration = "private-integration",
                    Recovery = "private-recovery"
                }
            });
    }

    private static Response<KeyVaultSecret> ResponseWithValue(
        string name,
        string? value)
    {
        var properties = new KeyVaultSecret(name, "placeholder").Properties;

        return Response.FromValue(
            SecretModelFactory.KeyVaultSecret(properties, value!),
            new StubResponse());
    }

    private static void AssertSafeException(
        NoteContentUnavailableException exception)
    {
        Assert.Equal(
            "Note content is temporarily unavailable.",
            exception.Message);
        Assert.Null(exception.InnerException);
        Assert.DoesNotContain("private-operations", exception.ToString());
        Assert.DoesNotContain("unit-test.invalid", exception.ToString());
        Assert.DoesNotContain("raw", exception.ToString());
    }

    private sealed class StubSecretClient : SecretClient
    {
        private readonly Func<
            string,
            string?,
            CancellationToken,
            Response<KeyVaultSecret>> responseFactory;

        public StubSecretClient(
            Func<
                string,
                string?,
                CancellationToken,
                Response<KeyVaultSecret>> responseFactory)
            : base()
        {
            this.responseFactory = responseFactory;
        }

        public string? RequestedName { get; private set; }

        public string? RequestedVersion { get; private set; }

        public CancellationToken RequestedCancellationToken { get; private set; }

        public int CallCount { get; private set; }

        public override Task<Response<KeyVaultSecret>> GetSecretAsync(
            string name,
            string? version = null,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            RequestedName = name;
            RequestedVersion = version;
            RequestedCancellationToken = cancellationToken;

            return Task.FromResult(
                responseFactory(name, version, cancellationToken));
        }
    }

    private sealed class StubResponse : Response
    {
        public override int Status => 200;

        public override string ReasonPhrase => "OK";

        public override Stream? ContentStream { get; set; }

        public override string ClientRequestId { get; set; } = string.Empty;

        public override void Dispose()
        {
        }

        protected override bool ContainsHeader(string name)
        {
            return false;
        }

        protected override IEnumerable<HttpHeader> EnumerateHeaders()
        {
            return [];
        }

        protected override bool TryGetHeader(string name, out string value)
        {
            value = string.Empty;
            return false;
        }

        protected override bool TryGetHeaderValues(
            string name,
            out IEnumerable<string> values)
        {
            values = [];
            return false;
        }
    }
}
