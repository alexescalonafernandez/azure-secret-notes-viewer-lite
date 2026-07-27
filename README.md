# Secret Notes Viewer Lite

Secret Notes Viewer Lite is a security-focused Azure learning project for a small web application that will display a closed set of synthetic demonstration notes. The repository includes a locally runnable ASP.NET Core Razor Pages application with Microsoft Entra authentication and a server-side authorization boundary for a fixed synthetic `/Notes` shell. Azure integration and infrastructure remain deferred.

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

`B4-D5 — SecretNotes.Reader Authorization and Protected Notes Shell`

Microsoft Entra authentication is implemented through Microsoft.Identity.Web. `/Notes` now requires `SecretNotes.Reader`, enforced server-side through the named `ReadSecretNotes` policy. Automated integration tests cover public endpoints plus anonymous, missing-role, unrelated-role, and authorized requests. The protected page contains fixed synthetic content only. Key Vault, Managed Identity, Azure RBAC, deployment, infrastructure, and CI/CD remain deferred.

## Application structure

- Solution: `SecretNotesViewer.slnx`
- Web project: `src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj`
- Integration tests: `tests/SecretNotesViewer.Web.Tests/SecretNotesViewer.Web.Tests.csproj`

## Local quick start

```bash
dotnet restore SecretNotesViewer.slnx
dotnet build SecretNotesViewer.slnx --configuration Release --no-restore
dotnet run \
  --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj \
  --launch-profile https
```

Local authentication requires explicitly selecting the existing `https` launch profile, and the application must listen on `https://localhost:7164`. The `http` profile at `http://localhost:5046` is not valid for the registered Microsoft Entra callbacks. Changing the port would require matching redirect-URI changes in the App Registration and is outside B4-D4.

After the application starts, open `https://localhost:7164`. `GET /` displays the public home page and `GET /health` returns a minimal process-health response. See the [local development guide](docs/operations/local-development.md) for the general workflow and the [local authentication guide](docs/operations/local-authentication.md) for credential setup and authentication validation.

## Documentation

- [Architecture](docs/architecture.md)
- [Security model](docs/security-model.md)
- [Cost and teardown operations](docs/operations/cost-and-teardown.md)
- [Local development](docs/operations/local-development.md)
- [Local toolchain and App Service runtime validation](docs/operations/runtime-validation.md)
- [Microsoft Entra ID development bootstrap](docs/operations/entra-development-bootstrap.md)
- [Local Microsoft Entra authentication](docs/operations/local-authentication.md)
- [SecretNotes.Reader authorization](docs/operations/role-authorization.md)
- [ADR 0001: Security architecture baseline](docs/adr/0001-security-architecture-baseline.md)
- [ADR 0002: Microsoft Entra ID development identity](docs/adr/0002-entra-development-identity.md)

## Deferred capabilities

- Azure Key Vault retrieval
- Managed Identity
- Azure RBAC
- Bicep and Azure resources
- Deployment
- Application Insights
- CI/CD

> **Security warning:** Never commit real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, personal data, connection strings, or realistic secret values. Only synthetic demonstration secrets may be used in later milestones.
