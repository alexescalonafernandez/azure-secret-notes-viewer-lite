# Local Microsoft Entra Authentication

## Purpose

This guide configures and validates local Microsoft Entra authentication for Secret Notes Viewer Lite without exposing identifiers, credentials, or personal information.

## Scope

This milestone supports a public home page, Microsoft Entra sign-in, return to the local application, a coarse authenticated state, sign-out, and return to an anonymous state. It does not implement `/Notes`, app-role enforcement, Key Vault, Managed Identity, deployment, or infrastructure.

## Prerequisites

- .NET 10 SDK.
- A trusted ASP.NET Core local HTTPS development certificate.
- Access by the repository owner to the existing development App Registration.
- The local application must use `https://localhost:7164`.
- The individual validation user must already be assigned to the Enterprise Application.

## Existing Entra assumptions

The existing App Registration is named `Secret Notes Viewer Lite - Development`, is single tenant, and uses the Web platform. Its registered redirect URIs are:

- `https://localhost:7164/signin-oidc`
- `https://localhost:7164/signout-callback-oidc`

Its front-channel logout URL is `https://localhost:7164/signout-oidc`. Implicit access-token flow, implicit ID-token/hybrid flow, and public client flow are disabled. API permissions and optional claims are absent. Assignment is required, the Enterprise Application is not visible to users, and exactly one individual user is assigned. The existing `SecretNotes.Reader` app role is not enforced in this milestone.

## Selected protocol flow

Local sign-in uses OpenID Connect Authorization Code Flow with PKCE enabled. The browser receives an authorization code, and the server redeems that code using the local development confidential-client credential. An ID token obtained through code redemption does not require enabling the App Registration's implicit ID-token checkbox.

The App Registration must continue rejecting direct `response_type=id_token` requests. Do not enable implicit grant or hybrid flow as a workaround.

## Development credential decision

Exactly one short-lived client secret is intended for local development. The repository owner creates it manually and uses the shortest practical expiration, never exceeding 180 days. Production must not use this client secret and must use a different credential strategy.

The client secret ID and client secret value are different. The application uses only the secret value. The value is normally displayed only once when it is created.

## Creating the local client secret

In the Microsoft Entra admin experience, the repository owner manually creates one client secret on the development App Registration. Copy the secret value directly into .NET User Secrets. Never place the value in GitHub, Codex, ChatGPT, logs, screenshots, documentation, source files, shell history intended for sharing, or application settings committed to the repository.

Do not share or record the secret ID. It is not accepted by the application in place of the secret value.

## User Secrets configuration

Run these commands locally and replace each placeholder only in the private terminal session:

```powershell
dotnet user-secrets set "AzureAd:TenantId" "<tenant-id>" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "AzureAd:ClientId" "<client-id>" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "AzureAd:ClientCredentials:0:ClientSecret" "<client-secret-value>" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

.NET User Secrets are stored outside the repository, but they are not encrypted. They are for local development only. Do not list or print the store. Validate configuration by running the application without printing values.

## Committed versus local configuration

Committed `appsettings.json` contains only the Microsoft identity platform instance, callback paths, signed-out redirect path, Authorization Code Flow response type, PKCE setting, and client-credential source type. Tenant ID, client ID, and client-secret value remain local in User Secrets and must never be committed.

## Restore and build

```powershell
dotnet restore SecretNotesViewer.slnx
dotnet build SecretNotesViewer.slnx --configuration Release --no-restore
```

Restore and build do not require local identity values.

## Local HTTPS run

Explicitly select the repository's existing `https` launch profile:

```bash
dotnet run \
  --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj \
  --launch-profile https
```

The application must listen on `https://localhost:7164`. The `http` profile at `http://localhost:5046` is not valid for the registered Microsoft Entra callbacks. Changing the port would require matching redirect-URI changes in the App Registration and is outside B4-D4.

## Anonymous validation

In a signed-out browser session, open the home page and Privacy page. Both must load without a challenge. The navigation and home page must show `Not signed in`.

## Sign-in validation

Select `Sign in`. Complete Microsoft Entra authentication with the assigned validation user. Microsoft Entra must return the browser to the local application through `/signin-oidc`. Confirm that sign-in succeeds with Authorization Code Flow and PKCE; do not inspect, copy, publish, or capture the complete authorization URL.

## Authenticated-state validation

After return, the navigation and home page must show only `Signed in`. They must not show a name, email address, preferred username, tenant, claim, role, token, authentication property, or identifier.

## Sign-out validation

Select `Sign out`. Microsoft Entra must process sign-out, return through `/signout-callback-oidc`, and redirect to `/`. The navigation and home page must again show `Not signed in`.

## Health endpoint regression

Open `https://localhost:7164/health` before and after authentication. The endpoint must remain public and return a successful process-health response without an authentication challenge.

## Expected failure modes

- **Missing Tenant ID:** Sign-in cannot construct a valid tenant authority. Set the `AzureAd:TenantId` User Secrets key.
- **Missing Client ID:** Sign-in cannot identify the application. Set the `AzureAd:ClientId` User Secrets key.
- **Missing client secret:** The authorization response cannot be redeemed. Set the `AzureAd:ClientCredentials:0:ClientSecret` User Secrets key.
- **Expired client secret:** Authentication fails during authorization-code redemption. Create a replacement short-lived secret, update the User Secrets value, validate it, and delete the expired secret manually.
- **Incorrect secret value:** Authentication fails during authorization-code redemption. Ensure the copied value—not the secret ID—is stored under the client-secret key.
- **Unsupported response type:** If the application requests `id_token` directly while implicit ID-token flow is disabled, Microsoft Entra returns AADSTS700054. Verify that committed configuration sets `ResponseType` to `code`; do not enable implicit flow to work around the error.
- **Redirect URI mismatch:** Microsoft Entra rejects or cannot return the authentication response. Run at `https://localhost:7164` and verify the registered URI matches exactly.
- **Unassigned user:** Microsoft Entra denies access because assignment is required. Use only the already assigned validation user; do not change assignments as part of application troubleshooting.
- **Invalid local development certificate:** The browser warns about HTTPS or the local server cannot establish HTTPS. Repair and trust the ASP.NET Core development certificate before retrying.

Keep troubleshooting evidence sanitized. Do not capture errors containing identifiers, correlation values, names, domains, tenant information, credentials, tokens, cookies, claims, or personal data.

## Client-secret expiration and rotation

Before expiration, the repository owner manually creates one replacement secret with the shortest practical lifetime, never exceeding 180 days. Copy its value directly into the existing User Secrets key, validate sign-in and sign-out, and then manually delete the previous secret from the App Registration. Never maintain extra active development secrets longer than needed.

## Local cleanup

Remove local values by key name without printing them:

```powershell
dotnet user-secrets remove "AzureAd:TenantId" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets remove "AzureAd:ClientId" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets remove "AzureAd:ClientCredentials:0:ClientSecret" --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

When the credential is no longer needed, the repository owner must also manually delete the local-development client secret from the App Registration. Do not execute cleanup merely to validate the application.

## Limitations and deferred work

Authentication alone grants no application role or Key Vault access. `/Notes`, `SecretNotes.Reader` authorization enforcement, Azure Key Vault, Managed Identity, Azure deployment, infrastructure, CI/CD, and automated tests remain deferred.
