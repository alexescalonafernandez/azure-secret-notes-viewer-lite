# GitHub Actions OIDC deployment foundation

## Purpose and checkpoint boundary

B4-D10A prepares a secretless, manual deployment path from GitHub Actions to the existing Azure Linux Web App. The repository now contains owner-run Azure bootstrap and validation scripts, a `workflow_dispatch`-only deployment workflow, and repository-local static checks.

This checkpoint prepares automation; it does not prove cloud state. The deployment App Registration, Service Principal, federated credential, Web App-scoped RBAC assignment, GitHub Environment, workflow run, application publication, and Azure validation do not exist merely because these files are present. Their creation and validation remain explicit owner actions.

B4-D10B remains responsible for the separate cloud browser-authentication identity, persistent non-secret runtime App Settings, application publication evidence, endpoint validation beyond the workflow smoke check, and browser authentication/authorization validation. B4-D11 remains responsible for Web App Managed Identity Key Vault authorization and deployed Key Vault reads.

## Identity boundaries

Three identity paths remain separate:

```text
Human browser user
→ separate cloud application identity
→ application authentication and SecretNotes.Reader authorization
→ deferred to B4-D10B

GitHub Actions
→ GitHub OIDC
→ dedicated deployment App Registration and Service Principal
→ Website Contributor at the exact Web App scope

Azure Web App runtime
→ existing system-assigned Managed Identity
→ no Key Vault role until B4-D11
```

The local-development App Registration is also separate. Script validation requires its client ID as a private comparison input and fails if it is reused as the deployment application. The scripts also fail if the deployment Service Principal is the Web App Managed Identity.

## Why GitHub OIDC

GitHub OIDC exchanges the workflow job's short-lived identity token for Azure access through an exact federated trust. It avoids long-lived deployment credentials in GitHub.

The deployment path prohibits publish profiles, `AZURE_CREDENTIALS`, Azure client secrets, SCM credentials, FTP, and basic publishing authentication. The dedicated deployment application is expected to have no password credential. Its Azure authorization is limited to code deployment at one Web App.

## GitHub Environment trust boundary

The workflow job uses the GitHub Environment named `dev`. The federated credential therefore trusts this exact subject:

```text
repo:alexescalonafernandez/azure-secret-notes-viewer-lite:environment:dev
```

The remaining fixed trust values are:

```text
issuer:   https://token.actions.githubusercontent.com
audience: api://AzureADTokenExchange
```

Changing the repository, owner, or Environment changes the OIDC subject and requires a separately reviewed trust update. Environment protection rules and authorized reviewers, where used, are GitHub-side controls configured manually by the owner.

## Azure RBAC boundary

The only accepted direct assignment for the dedicated deployment Service Principal in the active subscription is:

```text
role:  Website Contributor
scope: /subscriptions/<private>/resourceGroups/<private>/providers/Microsoft.Web/sites/<private>
```

The scripts reject duplicate assignments and any other direct assignment visible in the active subscription. They do not create subscription-, Resource Group-, App Service Plan-, or Key Vault-scoped roles. They never grant `Owner`, `User Access Administrator`, broad `Contributor`, or a Key Vault role.

## Private inputs

Real Azure names and identifiers are mandatory explicit PowerShell parameters. They have no committed defaults and must remain in the owner's private terminal context:

- Resource Group name;
- Web App name;
- dedicated deployment App Registration display name;
- local-development application client ID, used only for separation validation.

No deployment identity name or identifier is added to Bicep. The scripts suppress Azure CLI stderr, parse JSON locally, and emit only fixed markers and sanitized failure categories. Do not paste command lines containing real parameter values into Issues, pull requests, documentation, screenshots, or shared logs.

## Owner-run Azure sequence

Before running either script, the owner must privately confirm the intended Azure CLI tenant and active subscription and use an identity authorized to manage Entra applications, Service Principals, federated credentials, and Web App-scoped RBAC. These are not Codex-run steps.

1. Review the branch, scripts, workflow, tests, and complete diff.
2. Run the bootstrap without `-Apply`. This is the non-mutating default. If state is missing, it emits `github-oidc-apply-required` and stops.
3. Review the intended private inputs and active Azure context again.
4. Rerun the bootstrap with `-Apply` to authorize the bounded mutations.
5. Allow for Entra and Azure RBAC propagation.
6. Run the read-only validation script.
7. Retain only coarse markers as shareable evidence.

Command shape, with placeholders only:

```powershell
pwsh ./infra/scripts/09-bootstrap-github-oidc.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -DeploymentAppRegistrationName '<private>' `
  -LocalDevelopmentAppClientId '<private-guid>'

pwsh ./infra/scripts/09-bootstrap-github-oidc.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -DeploymentAppRegistrationName '<private>' `
  -LocalDevelopmentAppClientId '<private-guid>' `
  -Apply

pwsh ./infra/scripts/10-validate-github-oidc.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -DeploymentAppRegistrationName '<private>' `
  -LocalDevelopmentAppClientId '<private-guid>'
```

The bootstrap creates an application, Service Principal, federated credential, or exact Web App-scoped assignment only when absent and only with `-Apply`. Matching state is reused. Duplicate or malformed objects, a mismatched named credential, another federated credential, an existing client secret, or an unexpected direct role assignment cause a sanitized failure; the script does not repair, overwrite, broaden, or delete that state.

## Manual GitHub Environment setup

After Azure-side validation passes, create or review the GitHub Environment `dev` manually. Do not automate Environment configuration from these scripts.

Configure these Environment secrets by key name:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Configure these Environment variables:

| Key | Expected value or shape |
| --- | --- |
| `AZURE_WEBAPP_NAME` | Private existing Web App name |
| `DOTNET_VERSION` | `10.0.x` |
| `PROJECT_PATH` | `src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj` |

Do not publish the secret values, the Web App name, or a derived hostname. The client, tenant, and subscription identifiers are treated as private deployment metadata even though they are not passwords.

## Manual deployment workflow

The workflow at `.github/workflows/deploy-webapp.yml` has only the `workflow_dispatch` trigger and uses only these top-level permissions:

```yaml
permissions:
  id-token: write
  contents: read
```

Its deployment job uses `environment: dev` and performs this sequence:

1. Check out the repository.
2. Mask the Web App name, derived hostname, and derived health URL.
3. Install the Environment-selected .NET 10 SDK.
4. Restore `SecretNotesViewer.slnx`.
5. Build the solution in Release without restoring again.
6. Test the solution in Release without rebuilding.
7. Publish only the configured Web project.
8. Authenticate with `azure/login@v2` through GitHub OIDC.
9. Deploy the publish directory with `azure/webapps-deploy@v3`.
10. Retry a silent `/health` request a finite number of times with connection and request timeouts.
11. Emit `public-health-valid` only after HTTP success.

The workflow deploys application files only. It does not deploy Bicep, mutate App Settings, manage Entra or RBAC, access Key Vault, or enable another deployment credential.

## Sanitized evidence

Share only fixed markers such as:

```text
github-deployment-app-valid
github-deployment-service-principal-valid
github-federated-credential-valid
github-oidc-subject-valid
website-contributor-valid
deployment-scope-valid
deployment-key-vault-rbac-absent
github-oidc-bootstrap-valid
github-oidc-validation-valid
public-health-valid
```

Do not share raw Azure errors or JSON, real names, hostnames, callback URLs, tenant/subscription/client/object/principal/resource/assignment IDs, tokens, claims, credentials, Environment values, account data, or complete workflow logs containing private metadata.

## Common failure categories

- **Private input rejected:** Check the private values for accidental whitespace, placeholders, or invalid shapes without printing them.
- **Azure context invalid:** Privately select the intended tenant and subscription, then rerun.
- **Duplicate application or Service Principal:** Stop and reconcile the duplicate objects manually; the scripts will not choose one.
- **Federated credential mismatch:** Review issuer, subject, audience, and credential ownership. The bootstrap refuses silent replacement.
- **Existing client secret:** Remove it only after a separate owner review confirms it is unused; the scripts do not delete credentials.
- **Unexpected role assignment:** Review the dedicated identity's assignments. The scripts require exactly one direct assignment in the active subscription.
- **OIDC login failure:** Confirm the `dev` Environment, exact subject, Environment secret values, and propagation state without exposing them.
- **Deployment authorization failure:** Azure RBAC propagation can lag after assignment creation. Wait and retry validation before dispatching again.
- **Health check failure:** Review private App Service diagnostics. Do not publish the URL, response body, raw deployment output, or account metadata.

## Cleanup and teardown

Cleanup is owner-run and should be reviewed in reverse dependency order:

1. Disable further manual dispatches and remove the private `dev` Environment secrets and variables; remove the Environment if it has no other approved use.
2. Remove the exact Web App-scoped role assignment for the dedicated deployment Service Principal.
3. Remove the GitHub federated credential.
4. Remove the dedicated Service Principal and deployment App Registration after confirming nothing else uses them.
5. Review any deployed application content separately.

Ordinary B4-D10A cleanup must not delete the Web App, App Service Plan, Key Vault, synthetic secrets, development-user Key Vault role, local-development App Registration, or Web App Managed Identity. B4-D10B cloud authentication objects and runtime settings, when later introduced, have their own teardown boundary. B4-D11 Key Vault RBAC must be removed before deleting a Managed Identity that consumes it.
