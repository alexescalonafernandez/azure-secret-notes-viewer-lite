# Development Key Vault bootstrap

## Status boundary

- **Implemented in repository:** subscription-scope Bicep and six focused PowerShell workflow scripts.
- **Owner-run result so far:** preflight, the initial infrastructure deployment, and the negative control/data-plane separation check succeeded. A corrected bootstrap created all three secrets, then failed during secret validation; its `finally` cleanup removed the temporary Officer assignment. A normal retry was safely rejected because the vault was non-empty.
- **Planned manual execution:** the repository owner runs the explicit read-only recovery path, performs the final reader-role deployment, and runs final validation while retaining only sanitized shared evidence.
- **Validated only after the remaining owner-run steps:** persisted secret values and metadata, one-version state, final reader access, inherited-access assumptions, and the complete final Azure RBAC state.

No Azure or Microsoft Entra mutation was executed while preparing this repository correction. Separately, the owner-run bootstrap created the intended three active secrets before validation failed, and the temporary `Key Vault Secrets Officer` assignment was removed. The final reader assignment has not been deployed, final validation has not run, and the corrected recovery path has not yet completed successfully. The application remains on `InMemoryNoteContentProvider`; Key Vault application integration is deferred to B4-D8.

## Tool responsibilities

- Bicep is the persistent desired-state source of truth for the Resource Group, Standard Key Vault, vault configuration, and optional final reader assignment.
- PowerShell owns execution, procedural checks, sanitized subscription-scope `what-if`, deployment, bounded RBAC propagation, temporary access, local comparisons, cleanup, and sanitized evidence.
- All six workflows are `.ps1` files because they contain validation and control flow. `.azcli` is reserved for genuinely linear Azure CLI scrapbooks.
- Each script is intentionally independent and readable; the repository does not use a shared command framework.

## Prerequisites

The locally validated baseline is Azure CLI 2.85.0, Bicep CLI 0.45.15, and PowerShell 7.6.4. Use those versions or compatible later versions that provide `az bicep build`, `az bicep build-params`, subscription deployments, `az ad signed-in-user show`, and role-assignment listing with scoped, inherited, group-expansion, and principal-name-filling controls.

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

Copy the committed example to `infra/environments/development.bicepparam`, which is ignored by Git, and replace only the Resource Group name, vault name, and deployment-phase boolean. The file links to `main.bicep` with `using '../main.bicep'` and is the complete deployment parameter source. It contains no principal value. Scripts 01 and 02 pass only `--parameters $parameterFile`; `--template-file`, a second parameter source, and inline principal overrides must not accompany this linked-file workflow.

Bicep obtains the deployment identity through `deployer().objectId`. The final human reader role therefore targets the identity executing the final deployment. Never publish the local parameter file or its values, and do not change the signed-in Azure CLI identity between the initial deployment, bootstrap, final deployment, and validation.

## Owner-run sequence

Run each step selectively from the repository root in a PowerShell terminal. Stop on any failure.

1. Privately select and verify the intended Azure CLI active subscription, then copy the example parameter file to the ignored local filename.
2. Set the local Resource Group name and vault name. Keep `assignDevelopmentReaderRole = false`.
3. Run `infra/scripts/00-preflight.ps1`; it validates both `infra/main.bicep` and the ignored local `.bicepparam`.
4. Run `infra/scripts/01-what-if-development-key-vault.ps1` and review the sanitized change and resource types. Investigate any Azure CLI diagnostics only in the private terminal.
5. Run `infra/scripts/02-deploy-development-key-vault.ps1`.
6. Run `infra/scripts/03-validate-control-data-plane-separation.ps1` with the local vault name. Its only successful output is `data-plane-denied-before-assignment`.
7. For a new empty vault, run `infra/scripts/04-bootstrap-synthetic-secrets.ps1` with the local Resource Group name, vault name, and three private physical secret names. Do not pass `-ResumeExistingSecrets`.
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

# Use only for the documented partial-bootstrap state after privately
# confirming that the three supplied names are the intended fixtures.
& ./infra/scripts/04-bootstrap-synthetic-secrets.ps1 `
    -ResourceGroupName $resourceGroupName `
    -VaultName $vaultName `
    -OperationsSecretName $operationsSecretName `
    -IntegrationSecretName $integrationSecretName `
    -RecoverySecretName $recoverySecretName `
    -ResumeExistingSecrets `
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

Each secret is enabled, has one initial version, uses `text/plain; purpose=synthetic-demo`, and expires approximately 90 days after its persisted creation timestamp in UTC. Validation allows a tolerance of 0.001 days (86.4 seconds) for service and CLI timestamp normalization. Physical secret names remain local and separate from every public logical `NoteId`. The scripts never create a fourth probe secret.

## Direct and inherited RBAC

A direct assignment has a scope exactly equal to the individual vault. An inherited effective assignment originates at the Resource Group, subscription, or another parent scope. The workflows do not treat these as interchangeable:

- bootstrap and cleanup query `--scope <vault-scope>` without `--all` or `--include-inherited`, disable principal- and role-name filling, and filter the exact vault scope locally;
- final validation requires exactly one direct `Key Vault Secrets User` assignment for the current development user;
- final validation requires no direct `Key Vault Secrets Officer` and no direct application or Managed Identity assignment at the vault; and
- final validation separately queries `--scope <vault-scope>` with `--assignee-object-id`, `--include-groups`, and `--include-inherited`, but without `--all`, then rejects any inherited role effective for the current development user or its transitive groups that contains Key Vault data actions.

Azure CLI rejects the combination of `az role assignment list --all --scope <vault-scope>`; the owner-run failure exposed this compatibility issue rather than an Azure RBAC permission failure. The direct vault inspection remains global across principals so a milestone-created Officer or application-identity assignment cannot be missed. The inherited inspection is principal-specific: unrelated assignments inherited by other users, groups, or workloads do not represent effective access for the development user and are excluded. An inherited Key Vault data-plane role effective for the user or its transitive groups is an unsupported precondition because a successful read would no longer prove the intended vault-scoped reader assignment. Remove or narrow that inherited access through an independently reviewed administrative change before rerunning validation.

## Security and failure behavior

The Key Vault uses Azure RBAC, purge protection, seven-day soft-delete retention, and Standard SKU in West Europe. Public network access is enabled only as a local-development exception; it is not the production network posture.

Normal bootstrap is intentionally non-idempotent: it requires zero active secrets and refuses a non-empty vault so reruns cannot silently create extra versions. `-ResumeExistingSecrets` is an explicit recovery path only for the partial state in which all three creation commands succeeded but later validation failed. Recovery requires exactly three active secrets and a case-insensitive name set exactly equal to the three supplied private names. Missing names, unexpected names, and a fourth active secret cause sanitized failure.

Recovery performs no secret writes: it does not call secret set or set-attributes, and it does not delete, purge, recover, disable, overwrite, or create a version. Normal and recovery modes share the same read-only validation of fixed values, enabled state, content type, persisted creation/expiration relationship, and exactly one version. Deleting or purging secrets is not part of this recovery. For any other partial state, stop and use a separately authorized investigation or teardown decision rather than forcing resume mode.

Temporary Officer propagation, final reader propagation, and cleanup validation use bounded retries. A retry waits only after a failed attempt and stops immediately on success. If propagation times out, confirm the pinned subscription, signed-in user, direct role scope, and absence of inherited data-plane access privately, then wait for Azure RBAC convergence before rerunning the relevant validation step.

The temporary Officer cleanup is attempted in `finally` using an assignment resource ID known before creation, including when recovery-state, field, version, or normal creation validation fails. Cleanup is best effort because Azure can be unavailable; it is not guaranteed. The bootstrap script still exits non-zero unless a complete direct vault-scope query proves the Officer assignment is absent. A cleanup failure has its own `bootstrap-cleanup-failure-reason:<reason>` marker and never replaces an earlier `bootstrap-failure-reason:<reason>`.

Scripts 01 and 02 intentionally leave Azure CLI errors visible in the owner's private local terminal so deployment diagnostics remain actionable. Scripts 04 and 05 continue suppressing raw Azure errors and now preserve only script-generated sanitized reasons before their coarse failure markers, such as `bootstrap-failure-reason:role-assignment-query-failed` or `development-key-vault-failure-reason:vault-role-state-invalid`. Shared evidence for every workflow must contain only sanitized conclusions, change/resource types where already designed, and coarse markers.

For safe manual investigation, use the Azure portal or Azure CLI only in a private local session. Privately verify the active subscription before tenant-bound `az ad` commands; keep the captured subscription explicit on subscription- and resource-bound commands, disable principal-name filling, and use narrow queries. Inspect raw `what-if` or deployment errors only in that private terminal. Record only a coarse conclusion such as parameter source invalid, subscription mismatch, permission missing, propagation pending, vault non-empty, direct role invalid, or inherited data-plane permission present. Never paste raw errors, command arguments containing local values, IDs, URLs, principal data, physical names, screenshots, or role-assignment objects into Issues, pull requests, chat, or documentation.

## Teardown constraint

B4-D7 provides no deletion workflow. Purge protection prevents immediate purge, and deleting the Resource Group leaves the vault recoverable for the configured seven-day retention period. Follow the focused cost and teardown guide after validation.
