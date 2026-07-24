# ADR 0001: Security architecture baseline

## Status

Accepted for B4-D0 documentation baseline.

## Context

Secret Notes Viewer Lite needs a lean security-first architecture before application code or Azure infrastructure is introduced. The project will demonstrate secure access to synthetic demonstration notes stored as Azure Key Vault secrets while keeping human authentication, application authorization, and workload authorization separate.

Real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, and realistic secret values are prohibited from source control, README and ADRs, Issues and pull requests, logs and exceptions, URLs and query strings, screenshots and videos, terminal output used as evidence, Application Insights telemetry, custom properties, metrics, and events.

## Decision

The approved baseline decisions are:

- Use ASP.NET Core Razor Pages for the web application.
- Use Microsoft.Identity.Web for Microsoft Entra ID integration.
- Use single-tenant Microsoft Entra ID authentication.
- Define a conceptual `SecretNotes.Reader` app role for human user authorization.
- Protect `/Notes` through an authorization policy requiring `SecretNotes.Reader`.
- Use Azure Key Vault with Azure RBAC for secret storage and authorization.
- Use an App Service system-assigned Managed Identity as the workload identity.
- Use Azure SDK `SecretClient` with `DefaultAzureCredential` for Key Vault access.
- Assign the Managed Identity the expected Key Vault data-plane role `Key Vault Secrets User`, scoped as narrowly as practical.
- Use a closed catalog of known secret names; users must not supply arbitrary Key Vault secret names.
- Bootstrap Entra ID manually and document the process without sensitive values.
- Use Bicep for Azure resources in a later milestone.
- Deploy manually first.
- Defer GitHub Actions OIDC until after the manual deployment path is understood.
- Use .NET 10 LTS with target framework `net10.0`. On 2026-07-24 UTC, local SDK `10.0.301` and App Service Linux runtime availability were validated independently. Azure CLI returned the canonical runtime argument `DOTNETCORE:10.0`; future Bicep configuration will use the distinct App Service `linuxFxVersion` value `DOTNETCORE|10.0`. See the [runtime validation record](../operations/runtime-validation.md).

## Rationale

Razor Pages keeps the application simple for a small viewer while leaving room for standard ASP.NET Core authorization policies. Microsoft.Identity.Web aligns the application with Microsoft Entra ID authentication patterns. A single-tenant model narrows the learning scope and reduces identity complexity.

Separating `SecretNotes.Reader` from Key Vault RBAC prevents a human application role from becoming cloud data-plane access. The Managed Identity removes the need for stored workload credentials in App Service. Azure RBAC and `Key Vault Secrets User` support least-privilege secret reads without granting management, write, delete, key, or certificate permissions.

A closed secret-name catalog prevents arbitrary secret-name enumeration and avoids treating Key Vault as a user-browsable store. Manual Entra ID bootstrap and manual deployment are intentionally chosen first so the identity model can be inspected before automation is added.

## Consequences

- Users with `SecretNotes.Reader` can use the `/Notes` application feature, but they do not receive direct Key Vault access.
- The application depends on the App Service Managed Identity having correct Key Vault Azure RBAC.
- Local development may require separate, carefully controlled developer permissions that must not be confused with production workload permissions.
- Entra ID objects may require manual cleanup because they can outlive Azure resource teardown.
- Deployment automation and GitHub Actions OIDC are deferred.
- .NET 10 is confirmed as the target; local SDK availability and App Service Linux runtime availability were validated separately.

## Alternatives considered

- **ASP.NET Core MVC or SPA:** Deferred because Razor Pages is leaner for the planned single protected page scenario.
- **Multi-tenant Entra ID:** Deferred because it expands consent, issuer validation, and operational complexity beyond Lite scope.
- **Direct user Key Vault access:** Rejected because it couples human app authorization to cloud data-plane authorization and expands the blast radius.
- **Client secrets for the application:** Rejected for Azure hosting because Managed Identity avoids stored workload credentials.
- **Key Vault access policies:** Rejected for the baseline in favor of Azure RBAC consistency.
- **User-supplied secret names:** Rejected because it enables enumeration and unintended disclosure paths.
- **GitHub Actions OIDC immediately:** Deferred until manual deployment and identity behavior are validated.

## Validation required

- The .NET 10 decision was confirmed on 2026-07-24 UTC using local SDK `10.0.301` and the App Service Linux runtime result `DOTNETCORE:10.0`. Future Bicep configuration will use `DOTNETCORE|10.0` as `linuxFxVersion`; see the [runtime validation record](../operations/runtime-validation.md).
- Validate unauthenticated `/Notes` requests are challenged.
- Validate authenticated users without `SecretNotes.Reader` are denied.
- Validate users with `SecretNotes.Reader` can access the application feature but do not call Key Vault directly.
- Validate the App Service Managed Identity is the Key Vault caller.
- Validate the Managed Identity requires Azure RBAC and the expected `Key Vault Secrets User` role to read secrets.
- Validate missing secrets and RBAC failures produce safe, non-disclosing errors.
- Validate arbitrary secret-name enumeration is not possible.
- Validate logs, exceptions, telemetry, screenshots, Issues, pull requests, and terminal evidence contain no secret values or sensitive identifiers.
