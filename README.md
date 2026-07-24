# Secret Notes Viewer Lite

Secret Notes Viewer Lite is a security-focused Azure learning project for a small web application that will display a closed set of synthetic demonstration notes stored as Azure Key Vault secrets. It is intentionally documentation-first so the identity, authorization, workload identity, and secret-handling model are agreed before application code or Azure infrastructure exists.

## Learning objectives

- Model Microsoft Entra ID authentication separately from application authorization.
- Use an app role, `SecretNotes.Reader`, to gate access to protected note viewing.
- Use an App Service system-assigned Managed Identity as the only Key Vault caller.
- Apply Azure Key Vault Azure RBAC with least privilege.
- Keep real secrets, credentials, identifiers, and personal data out of source control, logs, screenshots, Issues, pull requests, and telemetry.

## Lite scope

The Lite version is a minimal portfolio workload: one ASP.NET Core Razor Pages web app, one protected `/Notes` area, a closed catalog of known secret names, and Azure Key Vault as the secret store. Users will never submit arbitrary Key Vault secret names, and users will never access Key Vault directly.

## Planned technology baseline

- ASP.NET Core Razor Pages.
- Microsoft.Identity.Web for Microsoft Entra ID integration.
- Single-tenant Microsoft Entra ID authentication.
- `SecretNotes.Reader` app-role authorization for `/Notes`.
- Azure App Service with system-assigned Managed Identity.
- Azure Key Vault using Azure RBAC, with the Managed Identity expected to receive `Key Vault Secrets User`.
- Azure SDK `SecretClient` with `DefaultAzureCredential`.
- Bicep for Azure resources in a later milestone.
- .NET 10 LTS is proposed but remains provisional because the installed Azure CLI could not return an explicit supported-only runtime result.

## Current status

`B4-D1 — Local Toolchain and App Service Runtime Validation`

The runtime target remains provisional pending an explicit supported-only App Service Linux runtime result. See the validation record for the exact .NET 10 value observed in the available-runtime catalog. No application code, infrastructure, deployment automation, GitHub Actions workflows, Azure resources, Entra ID objects, Key Vault resources, Managed Identity configuration, or Application Insights configuration are introduced in this milestone.

## Documentation

- [Architecture](docs/architecture.md)
- [Security model](docs/security-model.md)
- [Cost and teardown operations](docs/operations/cost-and-teardown.md)
- [Local toolchain and App Service runtime validation](docs/operations/runtime-validation.md)
- [ADR 0001: Security architecture baseline](docs/adr/0001-security-architecture-baseline.md)

## Future milestones

- Confirm the supported App Service Linux .NET runtime with a CLI version that exposes support status.
- Bootstrap Microsoft Entra ID application registration and app role manually with documented evidence that contains no sensitive values.
- Add the Razor Pages application and enforce `/Notes` authorization.
- Add Key Vault secret retrieval through Managed Identity and a closed secret-name catalog.
- Add Bicep-managed Azure infrastructure.
- Add manual deployment guidance before considering GitHub Actions OIDC.

> **Security warning:** Never commit real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, or realistic secret values. Only synthetic demonstration secrets may be used in later milestones.
