# ADR 0002: Microsoft Entra ID Development Identity

- Status: Accepted
- Date: 2026-07-26

## Context

Secret Notes Viewer Lite needs a development identity foundation before application authentication and authorization are implemented. The manual bootstrap must support single-tenant sign-in and app-role assignment while keeping human authorization separate from the future workload identity used for Key Vault.

Portfolio documentation must provide useful evidence without publishing real Entra identifiers, personal information, credentials, screenshots, or administrative URLs. The current tenant plan also did not make group assignment available.

## Decision

- Use the development-specific App Registration `Secret Notes Viewer Lite - Development`.
- Use single-tenant authentication.
- Create a separate production App Registration in a future deployment milestone.
- Use app roles rather than tenant-specific group claims.
- Define the enabled `SecretNotes.Reader` role for `Users/Groups`.
- Require assignment on the corresponding Enterprise Application.
- Hide the Enterprise Application from My Apps.
- Configure only the approved localhost HTTPS callbacks on the development registration.
- Configure no delegated or application API permissions.
- Create no certificate, client secret, or federated credential in B4-D3.
- Keep real Entra identifiers and personal information outside source control.
- Assign one individual human user for current development validation.
- Retain future group compatibility despite the current tenant-plan limitation.

## Rationale

A development-specific registration prevents callback and credential lifecycle coupling with production. Single-tenant authentication and required assignment constrain access. An app role expresses application authorization without binding the application to tenant-specific group claims. Empty API permissions and credentials minimize the identity footprint before runtime authentication requirements are implemented.

The individual assignment satisfies current validation needs. Keeping `Users/Groups` as the allowed member type preserves the intended future assignment model without claiming that a group is currently assigned.

## Consequences

- The development application and its tenant-local Enterprise Application are separate objects with separate responsibilities.
- Only assigned users can receive access through the Enterprise Application, and one individual user is currently assigned.
- Application authentication, sign-out handling, and authorization enforcement are not yet implemented.
- Production App Service endpoints must not be added to the development registration.
- Development and production credential lifecycles must remain separate.
- The future App Service system-assigned Managed Identity, not a human user or human Entra token, will call Key Vault.
- Administrative changes remain manual until an automation approach is explicitly adopted.

## Alternatives considered

- **One shared development and production App Registration:** Rejected because it would couple callback configuration, access boundaries, and credential lifecycles across environments.
- **Direct group-claim authorization:** Rejected because it would bind application authorization to tenant-specific group identifiers and token behavior; app roles provide a stable application contract.
- **Leaving assignment required disabled:** Rejected because any otherwise eligible tenant user could attempt access without an explicit Enterprise Application assignment.
- **Retaining Microsoft Graph `User.Read`:** Rejected because the application does not need Graph access for this milestone, and OpenID Connect sign-in does not require representing it as a manually configured Graph permission.
- **Creating a client secret immediately:** Deferred because authentication code and the confidential-client credential strategy are not yet decided. Client secrets are not permanently prohibited.
- **Automating the bootstrap with Microsoft Graph or Azure CLI:** Deferred because the objects were configured manually and this milestone records sanitized results only; automation would add permissions, implementation, and evidence-handling concerns beyond scope.

## Security implications

Single-tenancy, required assignment, no API permissions, no credential, and an Enterprise Application hidden from My Apps reduce the current exposure. The `SecretNotes.Reader` app role authorizes only the future application feature and grants no Azure RBAC or Key Vault permission.

The application object defines callbacks, the app role, ownership, and credential registrations. The service principal controls tenant assignment and visibility. One human assignment grants `SecretNotes.Reader`; it does not make that human identity the workload caller. The future App Service system-assigned Managed Identity will authenticate to Key Vault and will require separate least-privilege Azure RBAC.

Repository evidence excludes real identifiers, credentials, personal data, screenshots, and portal URLs.

## Deferred decisions

- Microsoft.Identity.Web integration and local runtime configuration.
- Confidential-client credential strategy.
- Authentication, sign-out, and authorization-policy validation.
- `/Notes` implementation.
- Production App Registration and App Service configuration.
- Managed Identity, Key Vault, and Azure RBAC.
- Bicep, telemetry, and CI/CD.
- Any future group assignment after tenant capabilities permit it.
