# App Service hosting foundation

## Status

B4-D9 has repository implementation present and repository-local validation complete. Owner-run Azure validation is pending, so the milestone is not ready for a pull request. This guide does not claim that the App Service resources exist in Azure.

## Objective and scope

B4-D9 prepares an owner-gated hosting foundation in the existing development Resource Group:

```text
Linux App Service Plan — F1 / Free
└── empty Linux Web App
    ├── .NET 10 Linux runtime
    ├── HTTPS-only
    ├── TLS 1.2 minimum for the site and SCM
    ├── FTP/FTPS disabled
    ├── SCM and FTP basic publishing credentials disabled
    └── system-assigned Managed Identity without Key Vault authorization
```

The existing Resource Group, Standard Key Vault, three synthetic secret values and versions, and development-user reader assignment remain independent and unchanged. The committed application and tests are unchanged, `InMemory` remains the content-provider default, and B4-D8 local `AzureCliCredential` behavior remains intact.

F1 is a learning-only tier. It carries no production SLA or production recommendation in this project and must not be used to make availability, scaling, or resilience claims.

## Runtime and API versions

The Web App uses exactly `DOTNETCORE|10.0` as `siteConfig.linuxFxVersion`. The pipe form is the App Service resource value. `DOTNETCORE:10.0` is the Azure CLI runtime argument and must not appear in Bicep as `linuxFxVersion`.

The implementation uses current stable, non-preview resource schemas supported by the repository toolchain:

- `Microsoft.Web/serverfarms@2025-03-01`
- `Microsoft.Web/sites@2025-03-01`
- `Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01`

These stable schemas represent the required Linux plan, runtime, transport, identity, public-network, client-affinity, and publishing-policy properties without preview features.

## Safe gate and private parameters

The root composition defaults `provisionAppServiceHosting` to `false`. The plan and Web App modules exist only when an owner deliberately enables that gate. `appServicePlanName` and `webAppName` default to empty strings in the root template and must be populated privately before enabling the gate.

The committed `infra/environments/development.bicepparam.example` contains placeholders and keeps the gate disabled. Copy it to the ignored `infra/environments/development.bicepparam` and replace placeholders only in the private file. Never publish, display, or commit the private file or its values.

## Owner-run workflow

All commands in this section are for the repository owner in a private terminal after privately selecting the intended Azure subscription. Codex did not run scripts 06 through 08.

1. Set the private App Service Plan and Web App names, keep the fixed `westeurope` location decision, and deliberately set `provisionAppServiceHosting = true`.
2. Run `infra/scripts/06-app-service-preflight.ps1`. It validates the CLI and Bicep toolchain, linked private parameters, subscription and signed-in identity context, the gate, local name syntax, location, and F1/Free plan definition. It emits only coarse markers.
3. Run `infra/scripts/07-app-service-deploy.ps1` without approval. It performs subscription deployment validation and a sanitized `what-if`. `Create` and `Modify` are accepted only when all three hosting categories are present; zero material changes are accepted as idempotent. Hosting `Ignore`, `Unsupported`, `Delete`, partial hosting sets, unknown change types, and unexpected resource changes fail closed. The script stops with `deployment-approval-required` unless explicit approval is supplied.
4. Privately investigate any raw diagnostic or unexpected scope. Do not publish a complete `what-if` transcript. Share only coarse markers and the expected Microsoft.Web resource categories.
5. After deliberate owner review, rerun `infra/scripts/07-app-service-deploy.ps1 -ApproveDeployment`. Only this explicit switch permits mutation.
6. Run `infra/scripts/08-app-service-validate.ps1`. It uses read-only Azure queries and emits only coarse conclusions for the plan, runtime, HTTPS/TLS, disabled publishing paths, identity, absent Key Vault role, empty application state, absent private settings, and absent telemetry resources. App Settings, connection strings, deployment children, and App Service deployment records are reduced to aggregate counts rather than returned as objects or values.

The workflow never changes the Azure CLI context. Raw Azure stderr is suppressed from shared output, identifiers are retained only in memory for relationship comparisons, and failures close without printing names, IDs, hostnames, principals, subscription or tenant metadata, deployment names, or operation IDs.

## Security boundaries

The system-assigned identity is created with the Web App but remains unauthorized. B4-D9 does not output its principal or tenant ID and creates no role assignment that consumes it. B4-D11 owns the future Key Vault RBAC decision and must preserve least privilege.

SCM and FTP basic publishing credentials are explicitly disabled with two child policies whose `allow` value is `false`. FTPS is also disabled in site configuration. No alternate username/password publishing mechanism is enabled.

No application package is deployed by B4-D9. The App Service platform may show its default empty-site placeholder; that page is platform-created and is not evidence that the repository application was published. The `application-package-absent` marker means precisely: no App Service deployment record or repository-defined deployment mechanism was found for the newly created empty site. It requires zero deployment records, no deployment/source-control/site-extension child resource, no App Setting, and no connection string. This is a scoped milestone assertion, not universal forensic proof that arbitrary content never existed.

B4-D9 defines no App Settings, connection strings, Key Vault references, App Service Authentication, Easy Auth, deployment slots, custom domains, certificates, VNet integration, private endpoints, IP restrictions, CORS, Application Insights, Log Analytics, diagnostic settings, source control, deployment extensions, GitHub Actions, or OIDC.

## Evidence rules

Share only the documented coarse success markers and expected resource categories. Never share the private parameter file, names, IDs, hostnames, principal or tenant data, subscription metadata, raw validation or deployment output, complete `what-if` output, deployment or operation IDs, settings values, role objects, URLs, screenshots containing metadata, or Azure errors.

Repository-local evidence consists of successful Bicep and example-parameter compilation, Release restore/build/test results, `git diff --check`, and focused static security searches. Azure success must not be inferred from those checks; owner-run preflight, validation, reviewed `what-if`, explicit deployment, and post-deployment validation remain separate evidence.

## Teardown and later milestones

Deleting the Web App deletes its system-assigned identity. Any later RBAC assignment for that identity must be removed or reviewed during teardown. The Key Vault is purge protected and independent of the App Service lifecycle; a hosting-only teardown must preserve it, its synthetic secret versions, and the development-user reader role. See the cost and teardown guide for the conceptual sequence.

B4-D10 owns the separate cloud App Registration, cloud redirect and logout URIs, minimum non-secret runtime configuration, manual application publication, `Provider=InMemory` startup, and deployed authentication plus `SecretNotes.Reader` authorization validation. It grants the Web App identity no Key Vault access.

B4-D11 owns deployed workload credential composition, the vault-scoped `Key Vault Secrets User` assignment for the Web App identity, `Provider=KeyVault` in Azure, and deployed closed-catalog reads. Neither later boundary is implemented or implied by B4-D9.
