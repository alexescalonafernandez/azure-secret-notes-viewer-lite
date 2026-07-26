# Microsoft Entra ID Development Bootstrap

## Purpose

This runbook records the completed manual bootstrap of the development identity for Secret Notes Viewer Lite before authentication code exists. It provides sanitized, repository-safe evidence of the intended configuration.

## Scope

This documentation-only milestone records existing Microsoft Entra objects and settings. No application code changed, no client credential was created, no Azure resource was created, and no Microsoft Graph automation was used. The document contains sanitized evidence only.

## Execution model

The repository owner completed and verified the bootstrap manually. The documentation and verification date is **2026-07-26 UTC**. No Entra or Azure write operation is part of this runbook execution.

## Sanitized configuration summary

| Area | Approved value or status |
| --- | --- |
| App Registration display name | `Secret Notes Viewer Lite - Development` |
| Supported account type | Accounts in this organizational directory only |
| Tenant model | Single tenant |
| Platform | Web |
| App role | `Secret Notes Reader` / `SecretNotes.Reader` |
| App role member types | Users/Groups |
| API permissions | None configured |
| Admin consent | Not granted |
| Credentials | None |
| Enterprise Application | Exists |
| Assignment required | Yes |
| Visible to users | No |
| Assigned users | Exactly one individual human user |

## Application object and service principal

The **application object / App Registration** defines the development application's identity-platform configuration, callbacks, app role, ownership, and credential registrations.

The corresponding **service principal / Enterprise Application** represents that application inside the tenant. It controls assignment requirements, visibility, and user or group assignments. Finding or configuring one object does not establish the state of the other.

## Authentication endpoints

The Web platform contains exactly two redirect URIs:

- `https://localhost:7164/signin-oidc` receives the authentication callback.
- `https://localhost:7164/signout-callback-oidc` receives the browser after the sign-out flow completes.

The separate front-channel logout URL is:

- `https://localhost:7164/signout-oidc`, which receives front-channel logout notifications.

No HTTP, wildcard, production, App Service, or additional callback URL is configured. Implicit access-token flow, implicit ID-token and hybrid flow, and public client flows are disabled. No optional claim is configured.

## App role

Exactly one app role is configured:

| Setting | Value |
| --- | --- |
| Display name | `Secret Notes Reader` |
| Value | `SecretNotes.Reader` |
| Allowed member types | Users/Groups |
| Description | Can view the protected synthetic secret notes area. |
| Enabled | Yes |

Generated role identifiers are intentionally not recorded.

## API permissions

The default delegated Microsoft Graph `User.Read` permission was removed. The final state is:

- Delegated API permissions: None configured.
- Application API permissions: None configured.
- Admin consent: Not granted.

OpenID Connect sign-in is not represented as a manually configured Microsoft Graph permission.

## Credentials

The final credential state is:

- Certificates: None.
- Client secrets: None.
- Federated credentials: None.

No credential value was created or documented.

## Enterprise Application access controls

The corresponding Enterprise Application exists. **Assignment required?** is set to **Yes**, and **Visible to users?** is set to **No**. These are service-principal access controls, not App Registration settings.

## User assignment

Exactly one individual human user is assigned to `Secret Notes Reader`. This assignment grants the application role `SecretNotes.Reader`; it grants no Azure RBAC or Key Vault access.

The human user and the user's Entra token are not the Key Vault caller. A future App Service system-assigned Managed Identity will be the workload identity that calls Key Vault.

## Ownership

The repository owner was added as an owner of the App Registration. The owner's identity is deliberately excluded from repository documentation.

## Validation checklist

- [x] App Registration exists.
- [x] Display name is `Secret Notes Viewer Lite - Development`.
- [x] Supported account type is single tenant.
- [x] An owner is configured.
- [x] Web platform is configured.
- [x] The two approved redirect URIs are configured.
- [x] The approved front-channel logout URL is configured.
- [x] Implicit access-token and ID-token/hybrid flows are disabled.
- [x] Public client flows are disabled.
- [x] No optional claims are configured.
- [x] `SecretNotes.Reader` exists and is enabled.
- [x] No delegated or application API permissions remain.
- [x] No certificate, client secret, or federated credential exists.
- [x] The Enterprise Application exists.
- [x] Assignment is required.
- [x] The Enterprise Application is hidden from My Apps.
- [x] Exactly one individual user is assigned to `Secret Notes Reader`.

## Evidence and redaction rules

Repository evidence is text-only and sanitized. Do not record tenant, client, application, object, principal, role, assignment, or subscription identifiers; tenant domains; user names; email addresses; portal URLs; credentials; tokens; screenshots; account details; or personal information. Never rely on repository-recorded identifiers to locate these objects.

## Operational limitations

Group assignment was unavailable under the current tenant plan. An individual user assignment was used successfully, which satisfies this milestone. The app role remains configured for `Users/Groups`; no group was created or assigned. This operational limitation is not an application defect and does not alter the authorization design.

## Deferred work

- Add Microsoft.Identity.Web.
- Add local runtime configuration.
- Decide the confidential-client credential strategy.
- Validate authentication and sign-out.
- Implement the authorization policy.
- Implement `/Notes`.
- Create a separate production App Registration.
- Deploy to App Service.
- Enable the App Service system-assigned Managed Identity.
- Integrate Key Vault.
- Add Bicep.
- Add privacy-conscious telemetry.
- Add CI/CD.

Production App Service endpoints must not be added to the development App Registration. Development and production credential lifecycles must remain separate.

## Teardown

Do not execute teardown as part of this documentation milestone. If manual teardown is later authorized:

1. Locate the development Enterprise Application by the approved display name.
2. Remove user assignments if appropriate.
3. Delete the Enterprise Application/service principal.
4. Locate and delete the development App Registration/application object.
5. Verify that neither object remains.
6. Review whether any credentials or assignments were unexpectedly left behind.

Deleting or locating only one object is not sufficient evidence that the other object is absent. Teardown must verify both the Enterprise Application and App Registration, and it must never rely on recorded IDs in repository documentation.
