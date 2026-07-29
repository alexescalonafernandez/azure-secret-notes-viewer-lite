# Development Key Vault bootstrap

## Status boundary

- **Implemented in repository:** subscription-scope Bicep and six focused PowerShell workflow scripts.
- **Planned manual execution:** the repository owner reviews `what-if`, performs both deployments, runs bootstrap, and retains only sanitized markers.
- **Validated only after owner-run deployment:** actual Resource Group, vault, secret metadata, secret values, and Azure RBAC state.

No Azure or Microsoft Entra mutation was executed while preparing the repository. The application remains on `InMemoryNoteContentProvider`; Key Vault application integration is deferred to B4-D8.

## Tool responsibilities

- Bicep is the persistent desired-state source of truth for the Resource Group, Standard Key Vault, vault configuration, and optional final reader assignment.
- PowerShell owns execution, procedural checks, sanitized subscription-scope `what-if`, deployment, bounded RBAC propagation, temporary access, local comparisons, cleanup, and sanitized evidence.
- All six workflows are `.ps1` files because they contain validation and control flow. `.azcli` is reserved for genuinely linear Azure CLI scrapbooks.
- Each script is intentionally independent and readable; the repository does not use a shared command framework.

## Prerequisites

The locally validated baseline is Azure CLI 2.85.0, Bicep CLI 0.45.15, and PowerShell 7.6.4. Use those versions or compatible later versions that provide `az bicep build`, `az bicep lint`, subscription deployments, `az ad signed-in-user show`, and role-assignment listing with `--all`, `--include-inherited`, and `--fill-principal-name false`.

The signed-in operator needs:

- subscription-scope deployment permission, including `Microsoft.Resources/deployments/*`;
- `Microsoft.Resources/subscriptions/resourceGroups/write` for the dedicated Resource Group;
- `Microsoft.KeyVault/vaults/write` at the target Resource Group for the vault deployment;
- permission to read role assignments at subscription, Resource Group, and vault scope;
- permission to read the role definitions referenced by inherited assignments;
- `Microsoft.Authorization/roleAssignments/write` and `Microsoft.Authorization/roleAssignments/delete` at the individual vault, or an appropriate least-privilege role containing them;
- access to resolve the signed-in user's own object ID; and
- the temporary data-plane access granted by the bootstrap workflow after role propagation.

Control-plane deployment permission does not imply Key Vault secret access. Do not broaden permissions to Owner, Contributor, Key Vault Administrator, or persistent Secrets Officer merely to make the workflow pass.

## Local setup

Before running a workflow, privately select and verify the intended Azure CLI active subscription using the owner's normal local CLI process. Do not publish the resulting account output or identifiers. The scripts rely on that preselected context and never call `az account set`.

Each script captures the active subscription once with a sanitized `az account show`, rejects a missing or unauthenticated context, and does not print the captured value. Subscription- and resource-bound commands continue to pass the captured value through `--subscription`. The tenant-bound `az ad signed-in-user show` command does not accept that option and runs only after the active context has been captured.

Copy the committed example to `infra/environments/development.bicepparam`, which is ignored by Git, and replace only the Resource Group name, vault name, and deployment-phase boolean. The development reader object ID is deliberately absent: `what-if` and deployment resolve the current signed-in user under the pinned subscription and pass that value to Bicep in memory. Bootstrap and final validation resolve the same current user under the same subscription context.

Never publish the local parameter file or its values. Do not change the signed-in Azure CLI identity between the initial deployment, bootstrap, final deployment, and validation.

## Owner-run sequence

Run each step selectively from the repository root in a PowerShell terminal. Stop on any failure.

1. Privately select and verify the intended Azure CLI active subscription, then copy the example parameter file to the ignored local filename.
2. Set the local Resource Group name and vault name. Keep `assignDevelopmentReaderRole = false`.
3. Run `infra/scripts/00-preflight.ps1`.
4. Run `infra/scripts/01-what-if-development-key-vault.ps1` and review the sanitized change and resource types.
5. Run `infra/scripts/02-deploy-development-key-vault.ps1`.
6. Run `infra/scripts/03-validate-control-data-plane-separation.ps1` with the local vault name. Its only successful output is `data-plane-denied-before-assignment`.
7. Run `infra/scripts/04-bootstrap-synthetic-secrets.ps1` with the local Resource Group name, vault name, and three private physical secret names.
8. Change only `assignDevelopmentReaderRole` to `true` in the ignored parameter file.
9. Run the `what-if` workflow again, review it, and run the deployment workflow.
10. Run `infra/scripts/05-validate-development-key-vault.ps1` with the same local resource and physical secret names.

The deployment workflow supports both phases through the local Bicep boolean; it does not hardcode either phase.

## Sanitized PowerShell invocations

Keep all resource values and physical names in local variables. The placeholders below are intentionally non-real:

```powershell
$resourceGroupName = '<set-local-resource-group-name>'
$vaultName = '<set-local-vault-name>'
$operationsSecretName = '<set-private-operations-secret-name>'
$integrationSecretName = '<set-private-integration-secret-name>'
$recoverySecretName = '<set-private-recovery-secret-name>'

& ./infra/scripts/03-validate-control-data-plane-separation.ps1 `
    -VaultName $vaultName

& ./infra/scripts/04-bootstrap-synthetic-secrets.ps1 `
    -ResourceGroupName $resourceGroupName `
    -VaultName $vaultName `
    -OperationsSecretName $operationsSecretName `
    -IntegrationSecretName $integrationSecretName `
    -RecoverySecretName $recoverySecretName `
    -PropagationMaxAttempts 12 `
    -PropagationDelaySeconds 10

& ./infra/scripts/05-validate-development-key-vault.ps1 `
    -ResourceGroupName $resourceGroupName `
    -VaultName $vaultName `
    -OperationsSecretName $operationsSecretName `
    -IntegrationSecretName $integrationSecretName `
    -RecoverySecretName $recoverySecretName `
    -PropagationMaxAttempts 12 `
    -PropagationDelaySeconds 10
```

Do not enable transcript, verbose, or debug output. The physical names must be unique and must differ case-insensitively from all public logical IDs: `demo-operations-note`, `demo-integration-note`, and `demo-recovery-note`.

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

Each secret is enabled, has one initial version, uses `text/plain; purpose=synthetic-demo`, and expires 90 days after creation in UTC. Physical secret names remain local and separate from every public logical `NoteId`. The scripts never create a fourth probe secret.

## Direct and inherited RBAC

A direct assignment has a scope exactly equal to the individual vault. An inherited effective assignment originates at the Resource Group, subscription, or another parent scope. The workflows do not treat these as interchangeable:

- bootstrap and cleanup enumerate all direct vault assignments, disable principal-name filling, and filter the exact vault scope locally;
- final validation requires exactly one direct `Key Vault Secrets User` assignment for the current development user;
- final validation requires no direct `Key Vault Secrets Officer` and no direct application or Managed Identity assignment at the vault; and
- final validation separately queries inherited assignments effective for the current development user and its transitive groups, then rejects any inherited role containing Key Vault data actions.

The direct vault inspection remains global so a milestone-created Officer or application-identity assignment cannot be missed. The inherited inspection is principal-specific: unrelated assignments inherited by other users, groups, or workloads do not represent effective access for the development user and are excluded. An inherited Key Vault data-plane role effective for the user or its transitive groups is an unsupported precondition because a successful read would no longer prove the intended vault-scoped reader assignment. Remove or narrow that inherited access through an independently reviewed administrative change before rerunning validation.

## Security and failure behavior

The Key Vault uses Azure RBAC, purge protection, seven-day soft-delete retention, and Standard SKU in West Europe. Public network access is enabled only as a local-development exception; it is not the production network posture.

Bootstrap refuses a non-empty vault so reruns cannot silently create extra versions. If a partial bootstrap creates one or more secrets and then fails, the next run stops at the non-empty-vault guard. Do not delete, overwrite, or rerun blindly. Privately inspect the vault, confirm which intended names and versions exist, and decide on a separately authorized recovery or teardown action without publishing the findings.

Temporary Officer propagation, final reader propagation, and cleanup validation use bounded retries. A retry waits only after a failed attempt and stops immediately on success. If propagation times out, confirm the pinned subscription, signed-in user, direct role scope, and absence of inherited data-plane access privately, then wait for Azure RBAC convergence before rerunning the relevant validation step.

The temporary Officer cleanup is attempted in `finally` using an assignment resource ID known before creation. Cleanup is best effort because Azure can be unavailable; it is not guaranteed. The bootstrap script still exits non-zero unless a complete direct vault-scope query proves the Officer assignment is absent.

The scripts capture Azure responses locally and emit only coarse markers. Do not enable debug or verbose CLI output, copy raw terminal failures, or publish identifiers, vault URLs, physical names, role objects, secret values, or personal information as evidence.

For safe manual investigation, use the Azure portal or Azure CLI only in a private local session. Privately verify the active subscription before tenant-bound `az ad` commands; keep the captured subscription explicit on subscription- and resource-bound commands, disable principal-name filling, use narrow sanitized queries, and redirect raw errors away from shared output. Record only a coarse conclusion such as subscription mismatch, permission missing, propagation pending, vault non-empty, direct role invalid, or inherited data-plane permission present. Never paste raw errors, command arguments containing local values, IDs, URLs, principal data, physical names, or role-assignment objects into Issues, pull requests, chat, screenshots, or documentation.

## Teardown constraint

B4-D7 provides no deletion workflow. Purge protection prevents immediate purge, and deleting the Resource Group leaves the vault recoverable for the configured seven-day retention period. Follow the focused cost and teardown guide after validation.
