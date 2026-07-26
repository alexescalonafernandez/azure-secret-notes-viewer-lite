# Security model

## Protected assets

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
- **User with `SecretNotes.Reader`:** Has a valid single-tenant Entra ID session and the application role required for `/Notes`.
- **App Service Managed Identity:** The system-assigned workload identity used by the deployed application to access Key Vault.
- **Local developer identity:** Used for local development and manual validation; must not be assumed to represent production workload permissions.
- **Future CI/CD identity:** Deferred identity for deployment automation, potentially GitHub Actions OIDC in a later milestone.

## `SecretNotes.Reader` app role

`SecretNotes.Reader` is configured on the development App Registration for `Users/Groups` and is enabled. One individual human user is assigned to the `Secret Notes Reader` role through the corresponding Enterprise Application for development validation. Application enforcement remains deferred.

The role allows access to the application's future `/Notes` feature only. It grants no Key Vault data-plane permission, Azure RBAC permission, or permission to enumerate arbitrary secrets.

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
- `SecretNotes.Reader` enforcement remains deferred.
- The local client secret is solely for the interactive development web application and must not be used in production.
- App Service Managed Identity remains the future Key Vault caller.

## Authorization requirements for `/Notes`

- Anonymous access to `/Notes` must be challenged.
- Authenticated users without `SecretNotes.Reader` must be denied.
- Users with `SecretNotes.Reader` may request the protected page.
- The application must select secrets only from a closed catalog of known names.
- Authorization must succeed before any Key Vault request is attempted.

## System-assigned Managed Identity

The deployed App Service will use a system-assigned Managed Identity as its workload identity. The identity lifecycle is tied to the App Service, reducing the need to manage a separate credential. The application will use `SecretClient` with `DefaultAzureCredential`; in Azure, the credential chain is expected to resolve to the App Service Managed Identity.

## Key Vault Azure RBAC

Azure Key Vault will use Azure RBAC. The expected data-plane role for the App Service Managed Identity is `Key Vault Secrets User`, scoped as narrowly as practical. Human users do not receive direct Key Vault access as part of the application reader role.

## Least-privilege principles

- Grant users only the application role needed to view the protected feature.
- Grant Key Vault data-plane access only to the Managed Identity.
- Prefer read-only secret access; do not grant secret write, delete, purge, key, certificate, or management permissions to the application identity.
- Keep the secret catalog closed and application-owned.
- Avoid broad resource group, subscription, wildcard, or owner-style permissions.

## Identity and permission matrix

The matrix describes the intended state after runtime authentication, authorization enforcement, `/Notes`, and Key Vault integration are implemented.

| Identity | Authenticates to app | May access `/Notes` | Key Vault caller | Expected Key Vault permission | Notes |
| --- | --- | --- | --- | --- | --- |
| Anonymous user | No | No; challenged | No | None | Must not trigger secret retrieval. |
| Authenticated user without app role | Yes | No; denied | No | None | Authentication alone is insufficient. |
| User with `SecretNotes.Reader` | Yes | Yes | No | None through this app role | App role permits application feature use only. |
| App Service Managed Identity | No human session | Not applicable | Yes | `Key Vault Secrets User` | Workload identity used by `SecretClient`. |
| Local developer identity | Optional for local runs later | Depends on local test setup | Only for local development if explicitly configured | Minimal temporary read access, if needed | Must not be documented with sensitive IDs or values. |
| Future CI/CD identity | No | Not applicable | No for runtime reads | Deployment permissions only, deferred | GitHub Actions OIDC is deferred. |

## Secure error-handling expectations

Errors must be safe by default. Authentication failures, missing app roles, Key Vault authorization failures, missing secrets, and unavailable dependencies must not expose secret values, sensitive identifiers, tokens, raw claims, stack traces, or connection details to users. User-facing messages should be generic, while diagnostic details must be minimized and scrubbed.

## Logging and telemetry restrictions

Secret values are prohibited from source control, README and ADRs, Issues and pull requests, logs and exceptions, URLs and query strings, screenshots and videos, terminal output used as evidence, Application Insights telemetry, and custom properties, metrics, or events. Physical Azure Key Vault secret names should not normally be logged. Logs may record coarse outcomes such as success, denied, missing configuration, or dependency failure, and may include controlled logical application-owned note identifiers such as `release-note` only when necessary and safe.

## Screenshot and documentation rules

Documentation and screenshots must use synthetic placeholders only. They must not show real secrets, credentials, tokens, personal data, sensitive connection strings, realistic secret values, raw access tokens, full Azure resource IDs, or terminal output that contains sensitive values. Tenant IDs and application/client IDs are non-secret identifiers, but real values should still not be unnecessarily published in portfolio evidence such as screenshots, videos, Issues, pull requests, README files, or terminal output.

## Threat and negative-test scenarios

Later milestones must test or validate these scenarios:

- Unauthenticated access to `/Notes` is challenged and no Key Vault request occurs.
- Authenticated user without `SecretNotes.Reader` is denied and no Key Vault request occurs.
- Managed Identity without Key Vault RBAC receives a safe failure with no secret disclosure.
- Missing secret receives a safe failure with no secret disclosure.
- Secret value is not exposed through logs or exceptions.
- Physical Azure Key Vault secret names are not normally logged; controlled logical note identifiers such as `release-note` are logged only when necessary and safe.
- Secret value is not exposed through documentation or screenshots.
- Arbitrary secret-name enumeration is impossible through routes, forms, query strings, or request bodies.
- Sensitive values are not stored in source control or App Settings, while non-secret identifiers such as tenant ID and application/client ID are treated as runtime configuration rather than credentials.
