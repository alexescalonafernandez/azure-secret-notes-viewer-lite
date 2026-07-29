# Development Key Vault bootstrap

## Status boundary

- **Implemented in repository:** subscription-scope Bicep, three `.azcli` workflows, and three strict PowerShell validation/bootstrap scripts.
- **Planned manual execution:** the repository owner reviews `what-if`, performs both deployments, runs bootstrap, and retains only sanitized markers.
- **Validated only after owner-run deployment:** actual Resource Group, vault, secret metadata, secret values, and Azure RBAC state.

No Azure or Microsoft Entra mutation was executed while preparing the repository. The application remains on `InMemoryNoteContentProvider`; Key Vault application integration is deferred to B4-D8.

## Tool responsibilities

- Bicep is the persistent desired-state source of truth for the Resource Group, Standard Key Vault, vault configuration, and optional final reader assignment.
- `.azcli` files are simple, selectively executable workflows for local preflight, sanitized subscription-scope `what-if`, and subscription-scope deployment.
- PowerShell owns procedural checks, bounded RBAC propagation, temporary access, local comparisons, cleanup, and sanitized evidence.

The committed parameter example contains unmistakable placeholders only. Copy it to `infra/environments/development.bicepparam`, which is ignored by Git, and replace the placeholders locally. Never publish the local file or its values.

## Owner-run sequence

Run each step selectively from the repository root in a PowerShell terminal. Stop on any failure.

1. Copy the example parameter file to the ignored local filename.
2. Set local Resource Group name, vault name, and current user object ID. Keep `assignDevelopmentReaderRole = false`.
3. Run `infra/scripts/00-preflight.azcli`.
4. Run `infra/scripts/01-what-if-development-key-vault.azcli` and review the sanitized change and resource types.
5. Run `infra/scripts/02-deploy-development-key-vault.azcli`.
6. Run `03-validate-control-data-plane-separation.ps1` with the local vault name. Its only successful output is `data-plane-denied-before-assignment`.
7. Run `04-bootstrap-synthetic-secrets.ps1` with the local Resource Group name, vault name, and three private physical secret names.
8. Change only `assignDevelopmentReaderRole` to `true` in the ignored parameter file.
9. Run the `what-if` workflow again, review it, and run the deployment workflow.
10. Run `05-validate-development-key-vault.ps1` with the same local resource and physical secret names.

The deployment workflow supports both phases through the local Bicep boolean; it does not hardcode either phase.

## Expected state transitions

```text
First Bicep deployment
→ Resource Group and Key Vault
→ no user data-plane role

Negative validation
→ secret data-plane operation denied

PowerShell bootstrap
→ temporary vault-scoped Key Vault Secrets Officer
→ exactly three synthetic secrets
→ local metadata and value comparison
→ temporary Officer removed

Final Bicep deployment
→ deterministic vault-scoped Key Vault Secrets User

Final validation
→ vault configuration, secret state, read access, and RBAC separation verified
```

Each secret is enabled, has one initial version, uses `text/plain; purpose=synthetic-demo`, and expires 90 days after creation in UTC. Physical secret names remain local. The scripts never create a fourth probe secret.

## Security and failure behavior

The Key Vault uses Azure RBAC, purge protection, seven-day soft-delete retention, and Standard SKU in West Europe. Public network access is enabled only as a local-development exception; it is not the production network posture.

Bootstrap refuses a non-empty vault so reruns cannot silently create extra versions. RBAC propagation and cleanup checks use bounded retries. The temporary Officer assignment is removed in `finally` where safely possible, and final validation requires Officer absence, User presence, read success, and no application or Managed Identity assignment at the vault.

The scripts capture Azure responses locally and emit only coarse markers. Do not enable debug or verbose CLI output, copy raw terminal failures, or publish identifiers, vault URLs, physical names, role objects, secret values, or personal information as evidence.

## Teardown constraint

B4-D7 provides no deletion workflow. Purge protection prevents immediate purge, and deleting the Resource Group leaves the vault recoverable for the configured seven-day retention period. Follow the focused cost and teardown guide after validation.
