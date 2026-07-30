# Secret Notes Viewer Lite

Secret Notes Viewer Lite is a security-focused Azure learning project for a small web application that displays a closed set of synthetic demonstration notes. The repository includes a locally runnable ASP.NET Core Razor Pages application with Microsoft Entra authentication, a server-side authorization boundary for `/Notes`, an application-owned closed catalog, and an owner-deployed and validated development Key Vault defined by repository-backed infrastructure.

## Learning objectives

- Model Microsoft Entra ID authentication separately from application authorization.
- Use an app role, `SecretNotes.Reader`, to gate access to protected note viewing.
- Use an App Service system-assigned Managed Identity as the only application Key Vault caller.
- Apply Azure Key Vault Azure RBAC with least privilege.
- Keep real secrets, credentials, identifiers, and personal data out of source control, logs, screenshots, Issues, pull requests, and telemetry.

## Lite scope

The Lite version is a minimal portfolio workload: one ASP.NET Core Razor Pages web app, one protected `/Notes` area, an application-owned catalog of known logical note identifiers, and a repository-defined Azure Key Vault whose application integration is deferred. Users will never submit arbitrary Key Vault secret names, and application users will never access Key Vault directly.

## Planned technology baseline

- ASP.NET Core Razor Pages.
- Microsoft.Identity.Web for Microsoft Entra ID integration.
- Single-tenant Microsoft Entra ID authentication.
- `SecretNotes.Reader` app-role authorization for `/Notes`.
- Azure App Service with system-assigned Managed Identity.
- Azure Key Vault using Azure RBAC, with the Managed Identity expected to receive `Key Vault Secrets User`.
- Azure SDK `SecretClient` with `DefaultAzureCredential`.
- Bicep as the persistent-state source of truth for the development Resource Group, Key Vault, and final local reader assignment.
- .NET 10 LTS with target framework `net10.0`, Azure CLI runtime argument `DOTNETCORE:10.0`, and future Bicep/App Service `linuxFxVersion` value `DOTNETCORE|10.0`.

## Current status

`B4-D7 — Development Key Vault Infrastructure and RBAC Bootstrap`

The repository now implements subscription-scope Bicep for a dedicated development Resource Group, a Standard Key Vault in West Europe, and an optional vault-scoped `Key Vault Secrets User` assignment. The linked `.bicepparam` is the complete deployment parameter source, while Bicep resolves the final deployment identity with `deployer().objectId`. Six focused PowerShell workflows cover local preflight, sanitized `what-if`, deployment, negative data-plane validation, temporary bootstrap access, synthetic-secret creation, cleanup, and final validation. They use PowerShell because the workflows contain validation and control flow; `.azcli` remains reserved for genuinely linear Azure CLI scrapbooks.

B4-D7 is complete. The owner successfully deployed the initial vault, proved that control-plane deployment did not grant secret data-plane access, created and recovered the exact three synthetic secrets without adding versions, verified temporary Officer cleanup, deployed the final vault-scoped `Key Vault Secrets User` assignment, and completed sanitized vault, secret, and RBAC validation. Application behavior is unchanged: `INoteContentProvider` still resolves to `InMemoryNoteContentProvider`; B4-D8 owns the Key Vault adapter and Azure SDK integration, while App Service, Managed Identity, telemetry, and CI/CD remain deferred.

## Application structure

- Solution: `SecretNotesViewer.slnx`
- Web project: `src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj`
- Integration tests: `tests/SecretNotesViewer.Web.Tests/SecretNotesViewer.Web.Tests.csproj`
- Notes application boundary: `src/SecretNotesViewer.Web/Application/Notes`
- In-memory provider adapter: `src/SecretNotesViewer.Web/Infrastructure/Notes`

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
- [Closed notes catalog and service boundary](docs/operations/closed-notes-catalog.md)
- [Development Key Vault bootstrap](docs/operations/development-key-vault-bootstrap.md)
- [ADR 0001: Security architecture baseline](docs/adr/0001-security-architecture-baseline.md)
- [ADR 0002: Microsoft Entra ID development identity](docs/adr/0002-entra-development-identity.md)
- [ADR 0003: Development Key Vault RBAC](docs/adr/0003-development-key-vault-rbac.md)

## Deferred capabilities

- Azure Key Vault retrieval
- Managed Identity
- Application identity Azure RBAC
- Application Insights
- CI/CD

> **Security warning:** Never commit real secrets, credentials, tokens, tenant IDs, subscription IDs, client IDs, object IDs, physical secret names, resource identifiers, personal data, connection strings, or realistic secret values. Keep the real development parameter file local and ignored.
