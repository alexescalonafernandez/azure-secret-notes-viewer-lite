# ADR 0003: Development Key Vault RBAC bootstrap

- Status: Accepted; repository implementation complete, Azure execution pending
- Date: 2026-07-29

## Context

The application boundary for a closed synthetic note catalog exists, but B4-D8 has not added a Key Vault provider. B4-D7 needs a reproducible development vault and evidence that Azure resource deployment permission is separate from Key Vault secret access. The workflow must keep identifying deployment values and physical secret names out of source control and must not leave broad write access behind.

## Decision

Use a subscription-scope Bicep entry point with focused modules:

- a subscription-scoped module creates the dedicated Resource Group in West Europe;
- a Resource Group-scoped module creates a Standard Key Vault with Azure RBAC, purge protection, seven-day soft-delete retention, and public network access enabled as a development exception;
- a Resource Group-scoped role module conditionally assigns the built-in `Key Vault Secrets User` role to one individual user at the vault itself, using its stable role definition ID and deterministic assignment naming.

Persistent state belongs to Bicep. Execution, sanitized `what-if`, deployment, procedural denial validation, temporary RBAC, bounded propagation retries, secret creation, local comparison, cleanup attempts, and final validation belong in six strict PowerShell scripts. Even the smaller workflows require validation and control flow, so `.azcli` is reserved for genuinely linear Azure CLI scrapbooks. Small local duplication is preferred over a shared automation framework when it keeps each script independently auditable.

Require the repository owner to privately select and verify the intended Azure CLI active subscription before execution. Each script captures that active subscription once without printing it and does not change the CLI context. The local `.bicepparam` links to `main.bicep` with `using '../main.bicep'` and is the complete deployment parameter source. Deployment workflows pass that file without `--template-file` or inline overrides. Bicep supplies the optional reader principal through `deployer().objectId`; scripts 03 through 05 continue resolving the interactive user for temporary access and validation.

Use two declarative deployments. The first disables the final reader assignment. After the owner proves data-plane denial, bootstrap temporarily assigns vault-scoped `Key Vault Secrets Officer`, creates exactly three synthetic secrets with 90-day UTC expiration, validates them locally, and attempts to remove Officer access through `finally`. A locally generated assignment name makes the exact assignment resource ID known before creation; success still requires a complete direct-scope query to prove absence. The second deployment enables the persistent vault-scoped `Key Vault Secrets User` assignment for the identity executing that deployment. The same signed-in identity must be used throughout both deployments, bootstrap, and final validation.

Enumerate direct vault assignments globally with complete resource-scope semantics and no principal-name resolution, then filter exact scope locally. This global direct check detects milestone-created Officer and application-identity assignments. Inspect inherited effective assignments separately for only the current development user and its transitive groups; unrelated inherited assignments for other principals are excluded. Reject inherited Key Vault data actions effective for that user or those groups as an unsupported least-privilege precondition. Physical secret names must not reuse any public logical `NoteId`, case-insensitively.

Do not create secrets in Bicep. Do not create persistent Officer, Administrator, Owner, or Contributor assignments. Do not create an application or Managed Identity assignment in this milestone.

## Consequences

- Control-plane and data-plane separation becomes an explicit, owner-validated property.
- Persistent Azure state remains reviewable and idempotent; temporary privilege is procedural, cleanup is attempted, and absence is validated before success.
- The local developer receives final read access only to one development vault.
- Public network access permits local validation but increases exposure relative to a private endpoint; this exception must not be copied into production without review.
- Purge protection and seven-day retention improve recovery safety but prevent immediate purge and immediate vault-name reuse during teardown.
- Secret values are intentionally synthetic, physical names remain local, and evidence is limited to coarse markers.
- Preflight validates both the Bicep entry point and the ignored local `.bicepparam`. The first owner-run preflight succeeded, while the first `what-if` exposed the former split parameter-source design before any resource deployment.
- Scripts 01 and 02 leave Azure CLI errors visible for private local diagnosis; raw diagnostics must not be copied into shared evidence.
- Repository completion does not prove Azure state. Validation is complete only after the owner runs the reviewed workflows.
- Application behavior is unchanged. `InMemoryNoteContentProvider` remains active, and B4-D8 owns the future Key Vault adapter and workload-identity design.

## Alternatives considered

- Access policies: rejected because Azure RBAC provides the intended control/data-plane model and scoped built-in roles.
- Persistent `Key Vault Secrets Officer`: rejected because ongoing write access exceeds the post-bootstrap requirement.
- Secrets in Bicep: rejected because values would cross the declarative deployment and source-control boundary.
- Private endpoint in B4-D7: deferred because local development networking is intentionally limited in this milestone.
- Application Managed Identity assignment now: deferred until the application and App Service integration milestone.
