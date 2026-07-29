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

Persistent state belongs to Bicep. Simple preflight, sanitized `what-if`, and deployment commands belong in `.azcli`. Procedural denial validation, temporary RBAC, bounded propagation retries, secret creation, local comparison, cleanup, and final validation belong in strict PowerShell.

Use two declarative deployments. The first disables the final reader assignment. After the owner proves data-plane denial, bootstrap temporarily assigns vault-scoped `Key Vault Secrets Officer`, creates exactly three synthetic secrets with 90-day UTC expiration, validates them locally, and removes Officer access. The second deployment enables the persistent vault-scoped `Key Vault Secrets User` assignment.

Do not create secrets in Bicep. Do not create persistent Officer, Administrator, Owner, or Contributor assignments. Do not create an application or Managed Identity assignment in this milestone.

## Consequences

- Control-plane and data-plane separation becomes an explicit, owner-validated property.
- Persistent Azure state remains reviewable and idempotent; temporary privilege is procedural and cleaned up.
- The local developer receives final read access only to one development vault.
- Public network access permits local validation but increases exposure relative to a private endpoint; this exception must not be copied into production without review.
- Purge protection and seven-day retention improve recovery safety but prevent immediate purge and immediate vault-name reuse during teardown.
- Secret values are intentionally synthetic, physical names remain local, and evidence is limited to coarse markers.
- Repository completion does not prove Azure state. Validation is complete only after the owner runs the reviewed workflows.
- Application behavior is unchanged. `InMemoryNoteContentProvider` remains active, and B4-D8 owns the future Key Vault adapter and workload-identity design.

## Alternatives considered

- Access policies: rejected because Azure RBAC provides the intended control/data-plane model and scoped built-in roles.
- Persistent `Key Vault Secrets Officer`: rejected because ongoing write access exceeds the post-bootstrap requirement.
- Secrets in Bicep: rejected because values would cross the declarative deployment and source-control boundary.
- Private endpoint in B4-D7: deferred because local development networking is intentionally limited in this milestone.
- Application Managed Identity assignment now: deferred until the application and App Service integration milestone.
