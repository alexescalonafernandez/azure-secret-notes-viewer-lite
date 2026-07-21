# Security model

## Protected assets

- Synthetic demonstration secret values stored in Azure Key Vault in later milestones.
- The closed catalog of approved secret names used by the application.
- Microsoft Entra ID application registration and app-role assignments.
- App Service system-assigned Managed Identity.
- Azure RBAC assignments for Key Vault.
- Operational evidence, logs, screenshots, pull requests, and telemetry that could accidentally disclose sensitive data.

Only synthetic demonstration secrets may be used later. Real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, and realistic secret values are prohibited.

## Actors and identities

- **Anonymous user:** Has not authenticated to the application.
- **Authenticated user without app role:** Has a valid single-tenant Entra ID session but lacks `SecretNotes.Reader`.
- **User with `SecretNotes.Reader`:** Has a valid single-tenant Entra ID session and the application role required for `/Notes`.
- **App Service Managed Identity:** The system-assigned workload identity used by the deployed application to access Key Vault.
- **Local developer identity:** Used for local development and manual validation; must not be assumed to represent production workload permissions.
- **Future CI/CD identity:** Deferred identity for deployment automation, potentially GitHub Actions OIDC in a later milestone.

## `SecretNotes.Reader` app role

`SecretNotes.Reader` is a conceptual application role issued by Microsoft Entra ID to authorized human users. It allows access to the application's `/Notes` feature only. It must not be interpreted as Key Vault data-plane permission, Azure RBAC permission, or permission to enumerate arbitrary secrets.

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

Secret values are prohibited from source control, README and ADRs, Issues and pull requests, logs and exceptions, URLs and query strings, screenshots and videos, terminal output used as evidence, Application Insights telemetry, and custom properties, metrics, or events. Logs may record coarse outcomes such as success, denied, missing configuration, or dependency failure, but must not record secret names unless they are non-sensitive catalog identifiers approved for diagnostics.

## Screenshot and documentation rules

Documentation and screenshots must use synthetic placeholders only. They must not show real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, realistic secret values, raw access tokens, full Azure resource IDs, or terminal output that contains sensitive values.

## Threat and negative-test scenarios

Later milestones must test or validate these scenarios:

- Unauthenticated access to `/Notes` is challenged and no Key Vault request occurs.
- Authenticated user without `SecretNotes.Reader` is denied and no Key Vault request occurs.
- Managed Identity without Key Vault RBAC receives a safe failure with no secret disclosure.
- Missing secret receives a safe failure with no secret disclosure.
- Secret value is not exposed through logs or exceptions.
- Secret value is not exposed through documentation or screenshots.
- Arbitrary secret-name enumeration is impossible through routes, forms, query strings, or request bodies.
- Sensitive configuration is not stored in source control or App Settings.
