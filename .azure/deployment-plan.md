# B4-D10B deployment preparation plan

## Status

Ready for Owner Validation (repository-local validation passed)

## Project profile

| Attribute | Decision |
| --- | --- |
| Path | Modify existing Azure learning application |
| Classification | Development / learning project |
| Scale | Small |
| Budget | Cost-optimized; preserve the existing F1 plan |
| Subscription | Owner-private active context; never committed or queried by Codex |
| Location | Existing `westeurope` deployment |
| Recipe | Standalone Bicep plus owner-run PowerShell gates |
| Hosting | Existing Linux Azure App Service running .NET 10 |

No new Azure resource is provisioned by B4-D10B, so subscription quota and regional
capacity checks are not applicable. The only Bicep mutation prepared here is an
exact App Settings replacement on the existing Web App, disabled by default.

## Scope

- Mode: modify the existing ASP.NET Core Razor Pages application and existing Azure infrastructure definitions.
- Target: the existing Linux Web App; no resource recreation and no cloud execution by Codex.
- Infrastructure path: Bicep, composed from `infra/main.bicep` through a separately gated existing-resource runtime configuration module.
- Identity path: a separate cloud browser-authentication App Registration and Enterprise Application, using the Web App system-assigned Managed Identity as a federated confidential-client assertion source.
- Runtime boundary: `NoteContent__Provider=InMemory`; no Key Vault runtime access or RBAC until B4-D11.

## Planned repository work

1. Add owner-gated cloud Entra bootstrap and read-only validation scripts.
2. Add exact, replacement-semantics App Settings management for the existing Web App behind a disabled-by-default gate.
3. Add owner-gated runtime configuration deployment and read-only post-publication validation scripts.
4. Add static tests for identity separation, secretless authentication, exact runtime settings, sanitized markers, workflow invariants, and excluded capabilities.
5. Document the four identities, owner-run gates, controlled roleless/reader validation, recovery, teardown, and B4-D11 handoff.
6. Run only the repository-local validation commands authorized by the task.

## Security and operational constraints

- Do not change `Program.cs`, base local `ClientSecret` configuration, or the manual-only deployment workflow unless local evidence proves a minimal need.
- Do not add secrets, real identifiers, hostnames, API permissions, certificates, Key Vault references/RBAC, telemetry, networking, slots, connection strings, or automatic deployment triggers.
- All mutations in scripts require explicit `-Apply`; Codex will not invoke those paths.
- Fail closed on duplicate, additional, or mismatched Entra state and emit only sanitized markers.
- Treat App Service App Settings deployment as replacement of the persistent set and define the exact five-setting state.
- Preserve disabled SCM and FTP basic publishing credentials.

## Validation and handoff

- Validate Bicep and the committed example parameter file locally.
- Restore, build, and test the .NET solution in Release.
- Run whitespace, status, diff, static security, and secret-pattern review.
- Commit the completed local foundation on `codex/b4-d10b-cloud-entra-publication`.
- Leave cloud bootstrap, cloud validation, Bicep what-if/apply, workflow dispatch, endpoint validation, and browser authorization checks to the owner.

## Repository-local validation proof

| Check | Command | Result | Date |
| --- | --- | --- | --- |
| Bicep template compilation | `az bicep build --file infra/main.bicep --stdout` | Pass | 2026-08-04 |
| Example parameter compilation | `az bicep build-params --file infra/environments/development.example.bicepparam --stdout` | Pass | 2026-08-04 |
| PowerShell parse | PowerShell parser over scripts 11–14 and the common helper | Pass | 2026-08-04 |
| Restore | `dotnet restore SecretNotesViewer.slnx` | Pass | 2026-08-04 |
| Release build | `dotnet build SecretNotesViewer.slnx --configuration Release --no-restore` | Pass | 2026-08-04 |
| Release tests | `dotnet test SecretNotesViewer.slnx --configuration Release --no-build` | Pass, 101 tests | 2026-08-04 |
| Whitespace | `git diff --check` | Pass | 2026-08-04 |

The historical `development.bicepparam.example` name failed the first parameter
compile because Bicep requires a filename ending in `.bicepparam`; the committed
`development.example.bicepparam` compile target resolves that tooling constraint.

## Static role verification

- The new runtime configuration module contains no role assignment resource.
- The Web App Managed Identity intentionally has no Key Vault role in B4-D10B.
- The GitHub deployment identity remains limited by the unchanged B4-D10A owner workflow to `Website Contributor` at the exact Web App.
- The existing development-user Key Vault assignment is unchanged.
- Scripts 12–14 validate absence of direct Key Vault RBAC for the identities relevant to their gates.

Live ARM validation, what-if, role verification, endpoint checks, and browser checks
remain owner-run by explicit task boundary. This plan is therefore not marked
`Validated` or `Deployed`, and the Azure deployment skill is intentionally not
invoked.

## Deployment execution

No Azure deployment is authorized for this Codex run. The finished repository state will be prepared for owner validation only.

## Research summary

- The existing App Service and Bicep composition are retained; a child configuration resource can target the existing site without changing plan, identity, networking, or site configuration.
- Microsoft.Identity.Web supports `SignedAssertionFromManagedIdentity`; a system-assigned identity is selected by omitting `ManagedIdentityClientId`, so `Program.cs` requires no change.
- Microsoft Graph supports an application federated identity credential with one issuer, subject, and audience. The bootstrap will accept exactly one credential and reject additional or mismatched state.
- The cloud Enterprise Application will require assignment and the application will expose exactly one user-only `SecretNotes.Reader` role with no API permissions or application credentials.
