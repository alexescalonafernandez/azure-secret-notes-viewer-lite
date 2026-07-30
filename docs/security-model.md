# Security model

## Protected assets

- The implemented `/Notes` application authorization boundary and fixed synthetic catalog.
- Synthetic demonstration secret values stored in the B4-D7 development Key Vault and optionally retrieved through the B4-D8 local provider.
- The closed catalog of approved logical note identifiers used by the application.
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
- **Local developer identity:** Used through `AzureCliCredential` for explicit local Key Vault mode and owner-run validation; it must not be assumed to represent production workload permissions.
- **Future CI/CD identity:** Deferred identity for deployment automation, potentially GitHub Actions OIDC in a later milestone.
- **Synthetic integration-test principal:** A non-identifying test-only principal used to exercise authorization branches without changing a real Entra user or assignment.

## `SecretNotes.Reader` app role

`SecretNotes.Reader` is configured on the development App Registration for `Users/Groups` and is enabled. One individual human user is assigned to the `Secret Notes Reader` role through the corresponding Enterprise Application for development validation. The implemented `ReadSecretNotes` policy requires this role for `/Notes`.

The role allows access only to the application's fixed synthetic `/Notes` catalog. It grants no Key Vault data-plane permission, Azure RBAC permission, or permission to enumerate arbitrary secrets.

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
- Users with `SecretNotes.Reader` may execute the notes service and render only the fixed synthetic catalog.
- No user role, claim, name, email, token, tenant, or identity identifier is rendered.
- The authenticated Notes navigation link is not a security control; the PageModel policy is the authorization boundary.
- `/Notes` applies zero-duration, no-location, no-store response-cache behavior.
- Authorization succeeds before the PageModel executes the notes service.
- `ClosedNoteCatalog` owns membership, order, and display names.
- Only the three known `NoteId` values are valid; logical IDs are not physical Key Vault names.
- Physical Key Vault names must differ case-insensitively from all three public logical `NoteId` values.
- Razor accepts no route, query, form, or handler identifier input.
- Query strings cannot alter or expand the catalog.
- Raw identifier strings never reach `INoteContentProvider`, and the provider cannot enumerate notes.
- Note content is never logged.
- Application authorization grants no Azure RBAC or Key Vault access.

## Integration-test authentication isolation

Automated authorization tests use non-identifying synthetic principals only. The synthetic scheme and its request-header handling exist exclusively in the integration-test assembly and are registered only in the integration-test process.

The production application contains no test scheme, test-header handling, authentication bypass, authorization bypass, or environment-based bypass. Production OpenID Connect remains responsible for authenticating real users.

## System-assigned Managed Identity

A future deployed App Service will use a system-assigned Managed Identity as its workload identity. The identity lifecycle is tied to the App Service, reducing the need to manage a separate credential. Its exact deployed credential composition remains deferred. B4-D8 uses only `AzureCliCredential` for deterministic local access with the B4-D7 development identity.

## Key Vault Azure RBAC

The B4-D7 repository definition explicitly enables Azure RBAC on the development vault. The owner-run denial check after the first deployment proved that control-plane permission to deploy the vault did not grant secret data-plane access.

Bootstrap grants the signed-in development user `Key Vault Secrets Officer` only at the individual vault and only for the bounded secret-creation procedure. Cleanup is attempted through `finally`; it is not guaranteed when Azure is unavailable. The script exits successfully only after a complete direct vault-scope query confirms Officer access is absent. The final Bicep deployment uses `deployer().objectId` to assign the identity executing that deployment `Key Vault Secrets User` at vault scope through a deterministic role assignment. The owner must use the same interactive identity for both deployments, bootstrap, and final validation. The built-in role definition ID, not its display name, is the declarative identity of the role.

The repository owner must privately select and verify the intended Azure CLI active subscription before running any workflow. Each script captures that active subscription once without displaying account metadata and never changes the CLI context. The linked `.bicepparam` is the complete deployment parameter source and supplies no principal value; the deployment workflows use it without `--template-file` or inline overrides. Scripts 03 through 05 still resolve the current interactive user under the established context for temporary access and exact effective-permission validation.

The B4-D7 owner-run sequence is complete. Initial deployment and negative data-plane validation succeeded; bootstrap created the exact three synthetic secrets; explicit `-ResumeExistingSecrets` partial-bootstrap recovery validated the already active secrets without secret writes or additional versions; `finally` cleanup proved temporary Officer absence; the final deployment added exactly one direct reader assignment for the development user; and final vault, secret, direct-role, and inherited-access validation succeeded. Scripts 01 and 02 preserve Azure CLI diagnostics in the private local terminal for investigation, while scripts 04 and 05 suppress raw Azure diagnostics and expose only script-generated sanitized reasons plus coarse markers. Shared security evidence remains limited to sanitized conclusions and markers; raw diagnostics, identifiers, URLs, principal data, and resource names must not be published.

Normal bootstrap remains intentionally non-idempotent and accepts only an empty vault. The explicit `-ResumeExistingSecrets` recovery mode accepts exactly the three supplied active physical names, case-insensitively, and then performs the same read-only value, enabled-state, content-type, persisted 90-day lifetime, and one-version checks as normal validation. Recovery performs no secret set, attribute update, deletion, purge, recovery, disable, overwrite, or version creation. Any other non-empty state is rejected.

Scripts 04 and 05 preserve JSON timestamps as their original ISO strings with `ConvertFrom-Json -DateKind String`. Field validation explicitly parses those strings as `DateTimeOffset` with invariant culture and normalizes them to UTC before comparing the persisted lifetime. Validation therefore does not depend on local date formatting, the operator's Windows culture, or daylight-saving transitions.

Secret-version validation requests JSON without a CLI-side JMESPath count and counts the parsed collection locally. During bootstrap and recovery, that metadata read relied on the already approved temporary Officer assignment. The later persistent reader deployment restored the intended read-only access after `finally` removed Officer access. No additional or persistent write-capable data-plane role was introduced.

Direct role assignments are not interchangeable with inherited effective permissions. Direct validation queries the vault scope without `--all` or `--include-inherited`, disables principal- and role-name filling, and filters exact scope locally. This global-across-principals view detects any direct Officer or application-identity assignment introduced at the vault. Effective inherited validation uses the vault scope, the current user's object ID, transitive-group expansion, and inherited-assignment inclusion, also without `--all`. An effective inherited role with Key Vault data actions invalidates the development least-privilege assumptions and causes sanitized failure as an unsupported precondition. Unrelated inherited assignments for other principals are excluded because they are not effective permissions of the development user.

This human reader assignment is a local-development exception and is unrelated to `SecretNotes.Reader`. B4-D8 local Key Vault mode deliberately uses that same Azure CLI identity. B4-D7 creates no application or Managed Identity assignment. The future App Service Managed Identity remains the expected deployed application caller and requires a separate least-privilege decision in a later milestone.

The vault keeps public network access enabled so the repository owner can validate it locally. This is a documented development exception. Purge protection and seven-day soft-delete retention reduce accidental irreversible loss but also prevent immediate purge during teardown.

## Least-privilege principles

- Grant users only the application role needed to view the protected feature.
- Grant application Key Vault data-plane access only to the Managed Identity.
- Limit the B4-D7 development-user exception to temporary Officer and final read-only User access at one vault.
- Prefer read-only secret access; do not grant secret write, delete, purge, key, certificate, or management permissions to the application identity.
- Keep the secret catalog closed and application-owned.
- Avoid broad resource group, subscription, wildcard, or owner-style permissions.

## Identity and permission matrix

The matrix distinguishes the current implemented application authorization state from the deferred Key Vault and deployment state.

| Identity | Authenticates to app | May access `/Notes` | Key Vault caller | Expected Key Vault permission | Notes |
| --- | --- | --- | --- | --- | --- |
| Anonymous user | No | No; challenged | No | None | Implemented and covered by authorization tests; the notes service does not execute. |
| Authenticated user without app role | Yes | No; denied | No | None | Implemented and covered by authorization tests; authentication alone is insufficient. |
| Authenticated user with unrelated app role | Yes | No; denied | No | None | Implemented and covered by authorization tests; unrelated roles grant no access. |
| User with `SecretNotes.Reader` | Yes | Yes; fixed synthetic catalog only | No | None through this app role | Implemented; the app role permits application feature use only. |
| App Service Managed Identity | No human session | Not applicable | Future: yes | Deferred `Key Vault Secrets User` | Future workload identity used by `SecretClient`. |
| Local developer identity | Yes when local authentication is configured | Depends on assigned app role | Yes only in explicitly selected local Key Vault mode through `AzureCliCredential` | Final direct `Key Vault Secrets User` at vault scope; temporary Officer removed | B4-D7 validation completed; B4-D8 interactive application validation is pending. |
| Future CI/CD identity | No | Not applicable | No for runtime reads | Deployment permissions only, deferred | GitHub Actions OIDC is deferred. |

## Secure error-handling expectations

Errors must be safe by default. Authentication failures, missing app roles, Key Vault authorization failures, missing secrets, and unavailable dependencies must not expose secret values, sensitive identifiers, tokens, raw claims, stack traces, or connection details to users. User-facing messages should be generic, while diagnostic details must be minimized and scrubbed.

## Logging and telemetry restrictions

The source-control boundary distinguishes safe B4-D6 fixtures from real or
retrieved content.

Allowed:

- Explicitly synthetic demonstration strings.
- Deterministic test fixtures.
- The three safe logical `demo-*` identifiers.
- Non-sensitive display names.

These synthetic fixtures are safe to commit because they are intentionally
non-sensitive and are not representative of production secret material.

Prohibited:

- Real note content.
- Realistic operational content.
- Content retrieved from Azure Key Vault.
- Secret values.
- Credentials.
- Tokens.
- Connection strings.
- Personal data.
- Sensitive production information.

Prohibited content must never be committed or exposed through README files,
ADRs, Issues, pull requests, logs, exceptions, URLs, query strings, screenshots,
videos, terminal evidence, Application Insights telemetry, custom properties,
metrics, or events. No note content, including synthetic fixture content, is
logged. Approved application-owned logical `NoteId` values may be logged only
when necessary and safe. Physical Azure Key Vault names must never be logged.

## Screenshot and documentation rules

Documentation and screenshots must use synthetic placeholders only. They must not show real secrets, credentials, tokens, personal data, sensitive connection strings, realistic secret values, raw access tokens, full Azure resource IDs, or terminal output that contains sensitive values. Tenant IDs and application/client IDs are non-secret identifiers, but real values should still not be unnecessarily published in portfolio evidence such as screenshots, videos, Issues, pull requests, README files, or terminal output.

## Threat and negative-test scenarios

Automated through B4-D6:

- Anonymous `/Notes` challenge.
- Missing-role denial.
- Unrelated-role denial.
- Authorized-role success.
- Exactly three known logical identifiers, display names, and synthetic contents.
- Identity non-disclosure.
- No-store behavior.
- Unknown `noteId` query resistance.
- Arbitrary `secretName` query resistance.
- Closed-catalog, service-order, provider-mapping, cancellation, and read-only collection behavior.

Completed owner-run validation for B4-D7:

- Control-plane deployment did not grant the local user secret data-plane access.
- Exactly three enabled synthetic secrets exist, each with one initial version and a validated persisted 90-day lifetime.
- Secret metadata and values matched the expected fixtures through local comparison without printing values or physical names.
- Temporary `Key Vault Secrets Officer` is absent; cleanup ran through `finally` and direct-scope absence was proven.
- Partial-bootstrap recovery completed with the exact expected active names and no secret write, deletion, purge, or version creation.
- Exactly one direct `Key Vault Secrets User` exists for the local user at the individual vault.
- No direct application identity or Managed Identity assignment exists at the vault.
- No unsupported inherited Key Vault data-plane permission is effective for the user or its transitive groups.
- Evidence contains only sanitized markers, with no raw Azure errors, identifiers, URLs, principal data, or role objects.

Automated for B4-D8 without Azure access:

- Closed logical-to-physical mapping and resistance to unknown `NoteId` values.
- Active-version-only retrieval with cancellation propagation.
- Missing values, request failures, and authentication failures become a fixed exception with no raw Azure message, physical name, vault URI, or inner exception.
- Startup rejects unsupported providers, unsafe vault URIs, incomplete or duplicate names, and names equal to public logical IDs.
- Key Vault mode has no in-memory fallback and uses one reusable `SecretClient`.

Still deferred or pending:

- Owner-run B4-D8 local Key Vault application validation.
- App Service Managed Identity behavior and its Azure RBAC validation.

Continuing security scenarios:

- Secret value is not exposed through documentation or screenshots.
- Arbitrary secret-name enumeration is impossible through routes, forms, query strings, or request bodies.
- Sensitive values are not stored in source control or App Settings, while non-secret identifiers such as tenant ID and application/client ID are treated as runtime configuration rather than credentials.
