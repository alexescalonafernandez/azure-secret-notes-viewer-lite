# SecretNotes.Reader Authorization

## Purpose

This guide describes the first application-owned authorization boundary in Secret Notes Viewer Lite and how to validate it without exposing identity data.

## Scope

B4-D5 protects `/Notes` and adds a fixed synthetic page shell. `/`, `/Privacy`, and `/health` remain public. Key Vault retrieval, Managed Identity, Azure RBAC, deployment, infrastructure, and CI/CD remain deferred.

## Authentication versus authorization

Production OpenID Connect authentication remains responsible for authenticating real users through Microsoft Entra ID. Authentication establishes an application principal. Authorization separately decides whether that principal may access `/Notes`.

## Microsoft Entra roles claim

Microsoft Entra emits assigned app roles through the `roles` claim. Role and claim data must not be rendered, logged, copied into evidence, or included in troubleshooting output.

## App role and policy

`SecretNotes.Reader` is the app-role value. `ReadSecretNotes` is the distinct application policy name. The policy requires the role, and absence of the required role is denied by default.

## Protected Notes boundary

The `/Notes` PageModel applies `ReadSecretNotes` at the class level. The page contains only three fixed synthetic labels and a statement that Key Vault retrieval is deferred. It accepts no note identifier through a route, query string, or form.

The authenticated navigation link is a convenience, not a security control. Server-side policy enforcement is the security boundary, and the UI does not inspect or display roles.

## Anonymous behavior

An anonymous request to `/Notes` is challenged. In a normal local production-authentication run, this starts the Microsoft Entra sign-in flow.

## Authenticated user without the role

An authenticated principal with no role or an unrelated role is forbidden. Authentication alone does not grant access.

## Authenticated user with the role

An authenticated principal with `SecretNotes.Reader` may open `/Notes`. The assigned real user is used only for successful manual validation; no real user is modified or impersonated by the automated tests.

## Synthetic integration-test design

Integration tests send real HTTP requests through `WebApplicationFactory<Program>`. Negative role scenarios use non-identifying synthetic principals. They prove challenge, forbid, success, content, and cache behavior without changing a real Microsoft Entra user or role assignment.

## Separation between test and production authentication

The deterministic authentication scheme exists only in the test assembly and is registered only in the integration-test process. The production project does not read test headers, contain a test bypass, or disable the named policy. Production OIDC remains responsible for authenticating real users.

## Running restore, build, and tests

```bash
dotnet restore SecretNotesViewer.slnx

dotnet build SecretNotesViewer.slnx \
  --configuration Release \
  --no-restore

dotnet test SecretNotesViewer.slnx \
  --configuration Release \
  --no-build
```

## Manual local validation

Run the existing HTTPS launch profile:

```bash
dotnet run \
  --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj \
  --launch-profile https
```

Validate without recording identity, claim, token, or identifier evidence:

```text
[ ] / remains public
[ ] /Privacy remains public
[ ] /health remains public
[ ] signed-out /Notes starts Microsoft Entra sign-in
[ ] assigned user completes sign-in
[ ] assigned user can open /Notes
[ ] /Notes shows only fixed synthetic content
[ ] no identity or claim information is shown
[ ] response uses no-store behavior
[ ] sign-out returns to /
```

## No-store behavior

The `/Notes` PageModel applies a response-cache policy with zero duration, no cache location, and `NoStore = true`. Authorized responses therefore include `Cache-Control` with `no-store`.

## Role-assignment token refresh

Role changes may not appear in an existing authentication session. Sign out and complete a new sign-in to receive a fresh token before validating a changed assignment.

## Sanitized troubleshooting

Confirm only coarse outcomes: public endpoint success, sign-in challenge, forbidden response, successful protected-page response, and the presence of `no-store`. Do not capture roles, claims, user details, tokens, cookies, authentication properties, transient sign-in URLs, trace data, or identifiers as evidence.

## Security limitations

Application authorization grants no Azure RBAC or Key Vault permission. The fixed page is not a real secret catalog, performs no lookup or write operation, and exposes no identity information. Human users do not call Key Vault.

## Deferred Key Vault integration

Secret retrieval remains deferred to a later milestone. A future App Service Managed Identity, not a human user's token, is intended to call Key Vault after separate infrastructure and Azure RBAC work.
