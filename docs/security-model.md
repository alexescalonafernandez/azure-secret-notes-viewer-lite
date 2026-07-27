# Security model

## Protected assets

- The implemented `/Notes` application authorization boundary and fixed synthetic shell.
- Synthetic demonstration secret values stored in Azure Key Vault in later milestones.
- The closed catalog of approved secret names used by the application.
- Microsoft Entra ID application registration and app-role assignments.
- App Service system-assigned Managed Identity.
- Azure RBAC assignments for Key Vault.
- Operational evidence, logs, screenshots, pull requests, and telemetry that could accidentally disclose sensitive data.

Only synthetic demonstration secrets may be used later. Tenant IDs and application/client IDs are identifiers, not credentials, and may be supplied as runtime configuration when needed. Real identifier values should not be unnecessarily published in README files, Issues, pull requests, screenshots, videos, or terminal evidence. Client secrets, passwords, access tokens, refresh tokens, credentials, secret values, sensitive connection strings, personal data, and realistic secret values must never be committed or exposed.

## Actors and identities

- **Anonymous user:** Has not authenticated to the application.
- **Authenticated user without app role:** Has a valid single-tenant Entra ID session but lacks `SecretNotes.Reader`.
- **Authenticated user with unrelated app role:** Has a valid single-tenant Entra ID session, but an unrelated role does not authorize `/Notes`.
- **User with `SecretNotes.Reader`:** Has a valid single-tenant Entra ID session and the application role required for `/Notes`.
- **App Service Managed Identity:** The system-assigned workload identity used by the deployed application to access Key Vault.
- **Local developer identity:** Used for local development and manual validation; must not be assumed to represent production workload permissions.
- **Future CI/CD identity:** Deferred identity for deployment automation, potentially GitHub Actions OIDC in a later milestone.
- **Synthetic integration-test principal:** A non-identifying test-only principal used to exercise authorization branches without changing a real Entra user or assignment.

## `SecretNotes.Reader` app role

`SecretNotes.Reader` is configured on the development App Registration for `Users/Groups` and is enabled. One individual human user is assigned to the `Secret Notes Reader` role through the corresponding Enterprise Application for development validation. The implemented `ReadSecretNotes` policy requires this role for `/Notes`.

The role allows access only to the application's fixed synthetic `/Notes` shell. It grants no Key Vault data-plane permission, Azure RBAC permission, or permission to enumerate arbitrary secrets.

## Development identity controls

- The development App Registration is single tenant.
- Assignment is required on the Enterprise Application.
- Exactly one individual human user is assigned to `Secret Notes Reader`.
- The Enterprise Application is hidden from My Apps.
- No delegated or application API permission is configured, and admin consent has not been granted.
- Local authentication uses exactly one short-lived, development-only client secret created manually by the repository owner. Its expiration must be the shortest practical duration and never exceed 180 days.
- The local client-secret value remains outside the repository in .NET User Secrets. User Secrets are not encrypted, are suitable only for local development, and must not be used as a production credential strategy.
- Production must use a different credential strategy.
- Real Entra identifiers and personal information are excluded from portfolio evidence and source control.
- Group assignment was unavailable under the current tenant plan but was not required for this milestone. The role remains compatible with `Users/Groups`; no group was created or assigned, and the authorization design is unchanged.

## Local authentication controls

- Local authentication uses OpenID Connect Authorization Code Flow with PKCE enabled.
- The browser receives an authorization code, which the server redeems as a confidential client using the development-only client secret.
- Implicit access-token flow, implicit ID-token/hybrid flow, and public client flow remain disabled. The App Registration must continue rejecting direct `response_type=id_token` requests.
- Protocol tokens are retained only inside the protected local authentication ticket to support the OIDC session lifecycle and reliable logout. They are never shown, logged, copied, decoded for portfolio evidence, or exposed to application code unnecessarily.
- No token-acquisition, token-cache, Microsoft Graph, or downstream API support exists.
- Logout returns through the registered sign-out callback before the application redirects to `/`.
- Production authentication-ticket persistence and logout behavior require a separate security review.
- Microsoft Entra authentication establishes only whether the local user is authenticated; it does not grant Key Vault access.
- The application displays only a coarse signed-in or not-signed-in state. It does not display personal identity information, raw claims, roles, tokens, authentication properties, or identifiers.
- PII logging is not enabled.
- `/Notes` authorization is enforced through the named `ReadSecretNotes` policy, which requires `SecretNotes.Reader`.
- The local client secret is solely for the interactive development web application and must not be used in production.
- App Service Managed Identity remains the future Key Vault caller.

## Authorization requirements for `/Notes`

- `/Notes` requires the named `ReadSecretNotes` policy.
- `ReadSecretNotes` requires `SecretNotes.Reader`.
- Anonymous access to `/Notes` is challenged.
- Authenticated users without `SecretNotes.Reader` are denied.
- Authenticated users with an unrelated role are denied.
- Users with `SecretNotes.Reader` may render only the fixed synthetic shell.
- No role, claim, name, email, token, tenant, or identifier is rendered.
- The authenticated Notes navigation link is not a security control; the PageModel policy is the authorization boundary.
- `/Notes` applies zero-duration, no-location, no-store response-cache behavior.
- The application must select secrets only from a closed catalog of known names when Key Vault retrieval is added later.
- Authorization must succeed before any future Key Vault request is attempted.
- Application authorization grants no Azure RBAC or Key Vault access.

## Integration-test authentication isolation

Automated authorization tests use non-identifying synthetic principals only. The synthetic scheme and its request-header handling exist exclusively in the integration-test assembly and are registered only in the integration-test process.

The production application contains no test scheme, test-header handling, authentication bypass, authorization bypass, or environment-based bypass. Production OpenID Connect remains responsible for authenticating real users.

## System-assigned Managed Identity

A future deployed App Service will use a system-assigned Managed Identity as its workload identity. The identity lifecycle is tied to the App Service, reducing the need to manage a separate credential. The application will use `SecretClient` with `DefaultAzureCredential`; in Azure, the credential chain is expected to resolve to the App Service Managed Identity. This Key Vault integration is not implemented in B4-D5.

## Key Vault Azure RBAC

Azure Key Vault will use Azure RBAC in the deferred target state. The expected data-plane role for the App Service Managed Identity is `Key Vault Secrets User`, scoped as narrowly as practical. Human users do not receive direct Key Vault access as part of the application reader role.

## Least-privilege principles

- Grant users only the application role needed to view the protected feature.
- Grant Key Vault data-plane access only to the Managed Identity.
- Prefer read-only secret access; do not grant secret write, delete, purge, key, certificate, or management permissions to the application identity.
- Keep the secret catalog closed and application-owned.
- Avoid broad resource group, subscription, wildcard, or owner-style permissions.

## Identity and permission matrix

The matrix distinguishes the current implemented application authorization state from the deferred Key Vault and deployment state.

| Identity | Authenticates to app | May access `/Notes` | Key Vault caller | Expected Key Vault permission | Notes |
| --- | --- | --- | --- | --- | --- |
| Anonymous user | No | No; challenged | No | None | Implemented and covered by B4-D5 tests; must not trigger future secret retrieval. |
| Authenticated user without app role | Yes | No; denied | No | None | Implemented and covered by B4-D5 tests; authentication alone is insufficient. |
| Authenticated user with unrelated app role | Yes | No; denied | No | None | Implemented and covered by B4-D5 tests; unrelated roles grant no access. |
| User with `SecretNotes.Reader` | Yes | Yes; fixed synthetic shell only | No | None through this app role | Implemented; the app role permits application feature use only. |
| App Service Managed Identity | No human session | Not applicable | Future: yes | Deferred `Key Vault Secrets User` | Future workload identity used by `SecretClient`. |
| Local developer identity | Yes when local authentication is configured | Depends on assigned app role | Only for future local Key Vault development if explicitly configured | Minimal temporary read access, if needed | Must not be documented with sensitive IDs or values. |
| Future CI/CD identity | No | Not applicable | No for runtime reads | Deployment permissions only, deferred | GitHub Actions OIDC is deferred. |

## Secure error-handling expectations

Errors must be safe by default. Authentication failures, missing app roles, Key Vault authorization failures, missing secrets, and unavailable dependencies must not expose secret values, sensitive identifiers, tokens, raw claims, stack traces, or connection details to users. User-facing messages should be generic, while diagnostic details must be minimized and scrubbed.

## Logging and telemetry restrictions

Secret values are prohibited from source control, README and ADRs, Issues and pull requests, logs and exceptions, URLs and query strings, screenshots and videos, terminal output used as evidence, Application Insights telemetry, and custom properties, metrics, or events. Physical Azure Key Vault secret names should not normally be logged. Logs may record coarse outcomes such as success, denied, missing configuration, or dependency failure, and may include controlled logical application-owned note identifiers such as `release-note` only when necessary and safe.

## Screenshot and documentation rules

Documentation and screenshots must use synthetic placeholders only. They must not show real secrets, credentials, tokens, personal data, sensitive connection strings, realistic secret values, raw access tokens, full Azure resource IDs, or terminal output that contains sensitive values. Tenant IDs and application/client IDs are non-secret identifiers, but real values should still not be unnecessarily published in portfolio evidence such as screenshots, videos, Issues, pull requests, README files, or terminal output.

## Threat and negative-test scenarios

Automated in B4-D5:

- Anonymous `/Notes` challenge.
- Missing-role denial.
- Unrelated-role denial.
- Authorized-role success.
- Fixed synthetic content.
- Identity non-disclosure.
- No-store behavior.

Deferred:

- Managed Identity without Key Vault RBAC receives a safe failure with no secret disclosure.
- Missing Key Vault secret receives a safe failure with no secret disclosure.
- Key Vault dependency failure receives a safe failure with no sensitive disclosure.
- Secret values are not exposed through logs or exceptions.
- Physical Azure Key Vault secret names are not normally logged; controlled logical note identifiers such as `release-note` are logged only when necessary and safe.

Continuing security scenarios:

- Secret value is not exposed through documentation or screenshots.
- Arbitrary secret-name enumeration is impossible through routes, forms, query strings, or request bodies.
- Sensitive values are not stored in source control or App Settings, while non-secret identifiers such as tenant ID and application/client ID are treated as runtime configuration rather than credentials.
