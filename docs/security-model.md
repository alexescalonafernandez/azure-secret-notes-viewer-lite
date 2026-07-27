# Security model

## Protected assets

- The `/Notes` application authorization boundary.
- Synthetic demonstration secret values that may be stored in Key Vault in a later milestone.
- The future closed catalog of application-owned note identifiers.
- Microsoft Entra application configuration and app-role assignments.
- Future Managed Identity and Azure RBAC assignments.
- Operational evidence that could accidentally disclose credentials, tokens, claims, personal data, or real identifiers.

Only fixed synthetic labels are present today. Real secrets, realistic secret values, credentials, tokens, personal data, sensitive connection strings, and real identifiers must never be committed or exposed.

## Actors and identities

- **Anonymous user:** not authenticated and challenged when requesting `/Notes`.
- **Authenticated user without the required role:** authenticated but forbidden from `/Notes`.
- **Authenticated user with an unrelated role:** authenticated but forbidden from `/Notes`.
- **User with `SecretNotes.Reader`:** authenticated and authorized to render the fixed `/Notes` shell.
- **App Service Managed Identity:** future workload identity intended to call Key Vault; not implemented.
- **Synthetic test principal:** non-identifying principal created only inside the integration-test process.

## Local authentication controls

- Microsoft.Identity.Web implements single-tenant OpenID Connect Authorization Code Flow.
- PKCE remains enabled.
- Implicit access-token flow, implicit ID-token/hybrid flow, and public client flow remain disabled.
- Assignment remains required on the development Enterprise Application.
- The app role remains compatible with `Users/Groups`; B4-D5 creates or changes no user, group, app role, or assignment.
- Local confidential-client authentication continues to use the existing short-lived development-only client secret in .NET User Secrets. User Secrets are not encrypted and are not a production credential strategy.
- Protocol tokens remain confined to the protected authentication ticket for the session lifecycle and logout behavior.
- Sign-out returns through the existing callback and redirects to `/`.
- No token acquisition, token cache, Microsoft Graph, or downstream API support exists.
- Production authentication has no test scheme, header-based bypass, claims transformation, or environment bypass.
- The application renders only coarse signed-in state and never renders a role, claim, user, token, or identifier.
- PII logging is not enabled.

## Authorization requirements for `/Notes`

- `/Notes` requires the named `ReadSecretNotes` policy.
- `ReadSecretNotes` requires `SecretNotes.Reader`.
- Anonymous requests are challenged.
- A missing role results in denial.
- Unrelated roles do not grant access.
- The Notes navigation link is not the security boundary; server-side policy evaluation is.
- Authorization grants no Azure RBAC or Key Vault permission.

No fallback policy or global authorization convention is used. The boundary is applied explicitly at the Notes PageModel class.

## Protected page controls

- The page contains exactly three fixed synthetic labels, not a real secret catalog.
- No identity, role, claim, token, tenant, or object identifier is rendered.
- No route or query parameter selects a note.
- No search, arbitrary lookup, API endpoint, write operation, or persistence exists.
- No Key Vault abstraction or Azure SDK exists.
- The PageModel applies zero-duration, no-location, no-store response-cache behavior.

## Test isolation

Negative authorization tests use synthetic principals only. They do not change or impersonate a real Microsoft Entra user and do not change a real role assignment. The synthetic authentication handler and request headers exist only in the test assembly and test host.

Production OIDC remains responsible for real authentication. The production application reads no test headers, does not disable authorization, and has no bypass for the named policy.

## Identity and permission matrix

| Identity | Authenticates to app | `/Notes` result | Key Vault caller | Azure permission |
| --- | --- | --- | --- | --- |
| Anonymous user | No | Challenged | No | None |
| Authenticated user without required role | Yes | Forbidden | No | None |
| Authenticated user with unrelated role | Yes | Forbidden | No | None |
| User with `SecretNotes.Reader` | Yes | Fixed shell rendered | No | None through the app role |
| Future App Service Managed Identity | Not a human session | Not applicable | Future only | Deferred narrowly scoped Key Vault access |

## Human identity versus workload identity

Human users authenticate to the application and never call Key Vault through this design. `SecretNotes.Reader` authorizes only an application feature.

A future App Service Managed Identity remains the intended Key Vault caller. Azure RBAC will apply to that workload identity, not to the human user. Managed Identity, Azure RBAC, Key Vault integration, deployment, and infrastructure are deferred.

## Least-privilege principles

- Require only the application role needed for the protected feature.
- Deny missing and unrelated roles by default.
- Keep synthetic content fixed and application-owned.
- Grant future Key Vault read access only to the workload identity and scope it narrowly.
- Never grant secret write, delete, purge, key, certificate, management, resource-group, or subscription permissions for this reader feature.

## Secure error and evidence handling

Challenge and forbid responses must not disclose claims, roles, tokens, authentication properties, sensitive identifiers, personal data, or stack traces. Documentation, test output, screenshots, terminal evidence, Issues, and pull requests must contain only coarse results and safe design values.

No role, claim, user, token, identifier, cookie, transient sign-in URL, trace ID, or correlation ID should be captured as evidence.

## Deferred Key Vault security

Key Vault contains no implemented dependency in this milestone. When added later, the application must select only from a closed catalog, authorize before retrieval, use the App Service Managed Identity, avoid logging physical secret names or values, and return safe failures. Human users must never supply arbitrary Key Vault identifiers or use their Entra tokens to call Key Vault.
