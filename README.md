# Secret Notes Viewer Lite

Secret Notes Viewer Lite is a security-focused Azure learning project for a small web application that will display a closed set of synthetic demonstration notes stored as Azure Key Vault secrets. The repository now includes the minimal locally runnable ASP.NET Core Razor Pages skeleton and the Microsoft Entra development identity bootstrap. Runtime authentication, authorization enforcement, Azure integration, and infrastructure remain deferred.

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
- .NET 10 LTS with target framework `net10.0`, Azure CLI runtime argument `DOTNETCORE:10.0`, and future Bicep/App Service `linuxFxVersion` value `DOTNETCORE|10.0`.

## Current status

`B4-D3 — Microsoft Entra ID Development Bootstrap`

The development App Registration and corresponding Enterprise Application now exist. The `SecretNotes.Reader` app role is configured and assigned to one individual user, API permissions are empty, and no credential exists. Application authentication code remains deferred.

## Application structure

- Solution: `SecretNotesViewer.slnx`
- Web project: `src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj`

## Local quick start

```bash
dotnet restore SecretNotesViewer.slnx
dotnet build SecretNotesViewer.slnx --configuration Release --no-restore
dotnet run --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

After the application starts, open the printed loopback URL. `GET /` displays the application skeleton and `GET /health` returns a minimal process-health response. See the [local development guide](docs/operations/local-development.md) for the complete workflow and smoke-validation examples.

## Documentation

- [Architecture](docs/architecture.md)
- [Security model](docs/security-model.md)
- [Cost and teardown operations](docs/operations/cost-and-teardown.md)
- [Local development](docs/operations/local-development.md)
- [Local toolchain and App Service runtime validation](docs/operations/runtime-validation.md)
- [Microsoft Entra ID development bootstrap](docs/operations/entra-development-bootstrap.md)
- [ADR 0001: Security architecture baseline](docs/adr/0001-security-architecture-baseline.md)
- [ADR 0002: Microsoft Entra ID development identity](docs/adr/0002-entra-development-identity.md)

## Deferred capabilities

- `/Notes`
- Microsoft Entra ID authentication
- `SecretNotes.Reader` authorization policy and enforcement
- Azure Key Vault
- Managed Identity
- Bicep
- Azure resources
- Application Insights
- CI/CD

> **Security warning:** Never commit real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, or realistic secret values. Only synthetic demonstration secrets may be used in later milestones.
