# Cloud Entra authentication and publication foundation

## Status and checkpoint boundary

B4-D10B adds a repository-local foundation for a separate cloud browser-authentication identity, secretless confidential-client authentication, exact App Service runtime settings, publication validation, and owner-run browser checks. The files do not prove that any cloud state exists.

Codex did not create or modify an Azure resource, Microsoft Entra object, Microsoft Graph object, Azure RBAC assignment, GitHub Environment, GitHub Actions run, or deployed application. The owner must run every cloud gate below and retain only sanitized evidence.

B4-D10B deliberately keeps `NoteContent:Provider=InMemory`. The Web App Managed Identity receives no Key Vault role and the deployment identity receives no Key Vault role. B4-D11 owns the future decision to authorize deployed Key Vault reads.

## Four identities and their boundaries

| Identity | Purpose | Credential or trust | Explicit prohibition |
| --- | --- | --- | --- |
| Local-development App Registration | Local browser sign-in on the committed localhost callbacks | Short-lived local client secret stored outside source control | Never receives cloud callbacks and is never used for deployment |
| GitHub deployment App Registration and Service Principal | Manual GitHub Actions code publication | GitHub Environment `dev` OIDC federation and `Website Contributor` at the exact Web App | Never authenticates browser users, acts as runtime workload identity, or receives Key Vault access |
| Cloud browser-authentication App Registration and Enterprise Application | Cloud OpenID Connect sign-in and `SecretNotes.Reader` authorization | Web App Managed Identity-backed signed client assertion; no secret or certificate | Never reuses the local or deployment application |
| Web App system-assigned Managed Identity | Runtime workload identity and confidential-client assertion source | Tenant-specific federated trust on the cloud App Registration | No Key Vault RBAC until B4-D11 |

The cloud App Registration and its Enterprise Application are two views of one application identity. The registration defines callbacks, logout, the user-only app role, and the Managed Identity federation. The Enterprise Application enforces `appRoleAssignmentRequired=true` and holds user app-role assignments.

Primary platform references: [Microsoft.Identity.Web certificateless authentication](https://learn.microsoft.com/entra/msidweb/authentication/certificateless), [Microsoft Graph federated identity credential creation](https://learn.microsoft.com/graph/api/federatedidentitycredential-post?view=graph-rest-1.0), and [restricting an Entra application to assigned users](https://learn.microsoft.com/entra/identity-platform/howto-restrict-your-app-to-a-set-of-users).

## Exact cloud application contract

The owner-run scripts accept the real Resource Group name, Web App name, cloud registration display name, local-development application client ID, and deployment application client ID only as explicit private inputs. They resolve both the application object ID and `appId` for the local, deployment, and cloud App Registrations; both the object ID and `appId` for the deployment and cloud Service Principals; and both the object ID and `appId` for the Web App Managed Identity Service Principal. Separation is checked only within matching identifier domains. They also resolve the existing Web App, its default hostname, the active tenant, and the active subscription without printing them.

The accepted cloud registration has exactly:

- `signInAudience=AzureADMyOrg`;
- Web redirects ending in `/signin-oidc` and `/signout-callback-oidc` on the resolved HTTPS Web App hostname;
- a front-channel logout URL ending in `/signout-oidc` on the same hostname;
- no localhost, SPA, or public-client redirect;
- implicit access-token and ID-token issuance disabled;
- public-client fallback disabled;
- no API permissions;
- no password or key credential;
- one enabled, user-only app role whose display name and value are both `SecretNotes.Reader`.

The Enterprise Application must be enabled, have no password or key credential, and require assignment. The registration must have exactly one federated identity credential:

```text
name:     web-app-system-assigned-managed-identity
issuer:   https://login.microsoftonline.com/<private-tenant-id>/v2.0
subject:  <private-Web-App-system-assigned-principal-id>
audience: api://AzureADTokenExchange
```

The scripts reject duplicate applications or Service Principals, additional callbacks, additional or mismatched federated credentials, existing secrets or certificates, API permissions, implicit grants, public-client flows, or identity reuse. They do not silently repair or delete unexpected state.

## Owner-run cloud application bootstrap

Use an owner identity privately authorized to manage applications and Service Principals. Confirm the intended Azure CLI tenant and subscription before each run. Do not paste commands containing real inputs into shared logs, Issues, pull requests, screenshots, or evidence.

Run the bootstrap first without mutation approval:

```powershell
pwsh ./infra/scripts/11-bootstrap-cloud-entra.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -CloudAppRegistrationName '<private>' `
  -LocalDevelopmentAppClientId '<private-guid>' `
  -DeploymentAppClientId '<private-guid>'
```

Missing state ends with `cloud-entra-apply-required`. After private review, rerun with the same inputs and `-Apply`. That switch permits only creation of the exact registration, exact Enterprise Application, and exact Managed Identity federated credential. The Enterprise Application POST contains only its cloud `appId`; after bounded discovery, the newly created Service Principal alone is patched to require app-role assignment and then boundedly validated as enabled, credential-free application state. Matching state is reused. Unexpected existing state fails closed and is never silently repaired.

After propagation, run read-only validation:

```powershell
pwsh ./infra/scripts/12-validate-cloud-entra.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -KeyVaultName '<private>' `
  -CloudAppRegistrationName '<private>' `
  -LocalDevelopmentAppClientId '<private-guid>' `
  -DeploymentAppClientId '<private-guid>'
```

The validation additionally proves that the Web App Managed Identity has no direct role at the development Key Vault.

## Exact App Service runtime configuration

`infra/modules/web-app-runtime-config.bicep` targets the existing Web App and replaces its complete persistent App Settings set with exactly:

```text
ASPNETCORE_ENVIRONMENT=Production
AzureAd__TenantId=<private>
AzureAd__ClientId=<private>
AzureAd__ClientCredentials__0__SourceType=SignedAssertionFromManagedIdentity
NoteContent__Provider=InMemory
```

App Settings deployment is replacement, not merge. An unrelated setting added manually will be removed on the next approved runtime configuration deployment. Review the exact five-setting object before applying it.

The system-assigned identity is selected by leaving `AzureAd__ClientCredentials__0__ManagedIdentityClientId` absent. No change to `Program.cs` is required: Microsoft.Identity.Web reads the cloud override from App Service. The committed `appsettings.json` retains `ClientSecret` as the local-development base, and no secret value is committed there.

The root template has an independent `configureCloudRuntime=false` gate. Tenant and application client IDs are secure Bicep parameters with no real committed defaults. The focused owner script deploys only the existing-site configuration module, so it does not recreate or modify the Resource Group, Key Vault, App Service Plan, Web App identity, SKU, networking, TLS, publishing policies, slots, telemetry, or RBAC.

## Owner-run runtime validate, what-if, and apply

The runtime script requires private tenant, cloud application, and deployment application identifiers. It compiles the focused Bicep module and performs an ARM group validation. Without `-Apply` it never deploys and ends with `cloud-runtime-apply-required`.

Run a sanitized what-if:

```powershell
pwsh ./infra/scripts/13-cloud-runtime-config-deploy.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -KeyVaultName '<private>' `
  -CloudTenantId '<private-guid>' `
  -CloudAppClientId '<private-guid>' `
  -DeploymentAppClientId '<private-guid>' `
  -WhatIf
```

Review the change privately. It must be limited to the Web App App Settings child configuration. Then rerun the same command with `-Apply` instead of `-WhatIf`. Post-apply validation requires the exact five settings, no connection string, no secret/certificate/ManagedIdentityClientId setting, disabled SCM and FTP basic publishing credentials, and no direct Key Vault role for either the runtime or deployment identity.

## Manual publication boundary

Only after scripts 11, 12, and 13 pass should the owner manually dispatch `.github/workflows/deploy-webapp.yml` from the repository default branch. The workflow remains `workflow_dispatch` only, uses Environment `dev`, requests only `id-token: write` and `contents: read`, restores/builds/tests/publishes the application, signs in with GitHub OIDC, deploys code, and requires exactly HTTP 200 from `/health`.

The workflow does not deploy Bicep or mutate App Settings, Entra, RBAC, Key Vault, networking, telemetry, or infrastructure. Do not dispatch it from this branch merely to test file presence; merge and owner review remain separate gates.

## Post-publication control-plane and anonymous validation

After a successful manual workflow run, execute:

```powershell
pwsh ./infra/scripts/14-cloud-application-validate.ps1 `
  -ResourceGroupName '<private>' `
  -WebAppName '<private>' `
  -KeyVaultName '<private>' `
  -CloudTenantId '<private-guid>' `
  -CloudAppClientId '<private-guid>' `
  -DeploymentAppClientId '<private-guid>'
```

The read-only script verifies .NET 10, the system-assigned identity, exact runtime settings, `InMemory`, absence of connection strings, disabled publishing credentials, absence of direct Key Vault roles for runtime and deployment identities, and absence of cloud application credentials. It then uses bounded retries and timeouts to require HTTP 200 from `/` and `/health`. It requests `/Notes` without following redirects and accepts only the expected HTTPS Microsoft identity platform authorization challenge. It never prints the hostname, complete URL, redirect location, response body, token, or cookie.

These checks establish a structural no-Key-Vault-access boundary: `Provider=InMemory`, the exact setting set contains no Key Vault reference or Key Vault option, and the Managed Identity lacks direct vault RBAC. They do not claim B4-D11 data-plane behavior.

## Owner-controlled roleless and reader browser sequence

Browser authentication cannot be automated safely here because tokens, cookies, account data, and interactive MFA must remain private. Use one existing controlled test user; do not create another account merely for evidence.

An application that exposes `SecretNotes.Reader` cannot rely on a zero-GUID “Default Access” assignment to create a roleless user. Microsoft documents that default assignment for applications without defined app roles. Use this bounded sequence instead:

1. Privately confirm the controlled user has no assignment to the cloud Enterprise Application and close existing application sessions.
2. Temporarily set the Enterprise Application's **Assignment required?** property to **No**. Do not change or remove `SecretNotes.Reader`.
3. Sign in as the controlled user. Confirm `/` and `/health` remain anonymous-capable, `/Notes` authenticates the user but application authorization returns access denied because no `SecretNotes.Reader` claim exists, and no identity, claim, role, tenant, or token is rendered.
4. Sign out and confirm the application returns to anonymous state.
5. Immediately restore **Assignment required?** to **Yes** and rerun script 12. Do not continue until `cloud-assignment-required-valid` is restored.
6. Assign that same controlled user the existing `SecretNotes.Reader` role on the Enterprise Application.
7. Sign in again. Confirm `/Notes` is authorized and shows only the fixed synthetic in-memory notes, then sign out and confirm anonymous state.
8. Keep the reader assignment only if it is the approved minimum final validation access. Otherwise remove that user assignment after evidence capture and rerun script 12. The required final control is always `appRoleAssignmentRequired=true`.

Record only coarse markers such as `roleless-user-forbidden`, `reader-user-authorized`, and `cloud-signout-valid`. Never publish the user name, email, object ID, claims, role payload, tokens, cookies, browser trace, redirect URL, or screenshots containing account data.

## Failure recovery

- **Bootstrap reports apply required:** Review private inputs and rerun with `-Apply` only when the missing object is intended.
- **Duplicate or mismatched Entra state:** Stop. Reconcile it manually after owner review; scripts intentionally do not select, overwrite, or delete an unexpected object.
- **Credential or API permission present:** Confirm ownership and usage before any separate removal action. The bootstrap will not repair it.
- **Runtime what-if contains another category:** Do not apply. Check the focused module, target Resource Group, Web App name, and private parameter values.
- **OIDC challenge fails:** Privately review callbacks, tenant/client settings, application propagation, and App Service diagnostics without publishing raw output.
- **Roleless test interrupted:** Restore assignment required to **Yes** before any other work and rerun script 12.
- **Reader authorization fails:** Confirm the assignment targets the cloud Enterprise Application and exact role, sign out completely, wait for propagation, and retry without inspecting or publishing tokens.

## Sanitized evidence

Acceptable fixed markers include:

```text
cloud-entra-bootstrap-valid
cloud-entra-validation-valid
cloud-runtime-what-if-valid
cloud-runtime-config-valid
public-home-valid
public-health-valid
anonymous-notes-challenge-valid
roleless-user-forbidden
reader-user-authorized
cloud-signout-valid
key-vault-rbac-absent
cloud-application-validation-valid
```

Do not share raw Azure or Graph errors, JSON, App Settings, names, hostnames, callback URLs, tenant/subscription/client/object/principal/resource/assignment IDs, tokens, cookies, authorization codes, personal data, or complete GitHub Actions logs.

## Teardown and B4-D11 handoff

Teardown is a separately reviewed owner action. Remove user app-role assignments first, then the Managed Identity federated credential, Enterprise Application, and cloud App Registration. Remove the five persistent App Settings only if application publication is also being dismantled. Preserve the local-development App Registration, GitHub deployment identity, Web App system-assigned identity, Web App, App Service Plan, Key Vault, synthetic secrets, and development-user vault role unless their own milestone teardown explicitly includes them.

B4-D11 starts only after B4-D10B owner gates pass. It may then grant the Web App Managed Identity the minimum vault-scoped read role and change the deployed provider to `KeyVault`. B4-D10B itself contains no Key Vault reference, Key Vault RBAC mutation, or deployed Key Vault read.
