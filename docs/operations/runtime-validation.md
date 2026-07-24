# Local Toolchain and App Service Runtime Validation

## Purpose

This record establishes the local engineering toolchain and the Azure App Service Linux .NET runtime available for later deployment configuration. It contains only reproducible, non-sensitive evidence and does not create application code or Azure resources.

## Validation context

- Validation date: 2026-07-24 UTC.
- Operating system: Windows 11.
- Repository state: clean at the initial preflight.
- Git isolation: validation and documentation changes used the isolated branch `codex/b4-d1-runtime-validation` in a separate worktree based on the latest available local `main` and `origin/main`, which matched at preflight.
- No local repository path is recorded.

## Commands executed

The validation used these read-only commands:

```text
git status --short
git branch --show-current
git log -1 --oneline
git --version
dotnet --info
dotnet --list-sdks
dotnet --list-runtimes
az version
az account show --query state -o tsv
az webapp list-runtimes --os-type linux --runtime dotnet --support supported --output json
az webapp list-runtimes --help
az webapp list-runtimes --os-type linux --output json --only-show-errors
az webapp list-runtimes --os-type linux --show-runtime-details --output json --only-show-errors
```

The installed Azure CLI rejected the `--runtime` and `--support` arguments because those filters are not available in version 2.85.0. Its command help identifies the unfiltered form as the compatible read-only command for listing available built-in stacks, so the unfiltered Linux result was parsed locally and reduced to .NET entries only. The detailed-output option returned the same flat values.

## Local toolchain results

| Check | Redacted result |
| --- | --- |
| Git | `2.47.1.windows.2` |
| .NET SDKs | `8.0.406`, `9.0.313`, `10.0.301` |
| Relevant ASP.NET Core runtimes | `6.0.36`, `8.0.13`, `8.0.26`, `8.0.28`, `9.0.15`, `10.0.9` |
| Relevant .NET runtimes | `6.0.36`, `8.0.13`, `8.0.26`, `8.0.28`, `9.0.15`, `10.0.9` |
| .NET 10 SDK locally installed | Yes |
| Azure CLI | `2.85.0` |
| Azure CLI authentication | Valid |

The local .NET 10 SDK check establishes build-tool availability only. It does not, by itself, establish App Service runtime support.

## App Service Linux runtime results

The installed CLI did not return explicit support-status fields, so no supported-only entries could be established. Its compatible available-runtime query returned these relevant App Service Linux .NET values:

| .NET version | Value returned by Azure CLI |
| --- | --- |
| .NET 10 | `DOTNETCORE:10.0` |
| .NET 9 | `DOTNETCORE:9.0` |
| .NET 8 | `DOTNETCORE:8.0` |

Azure CLI 2.85.0 returned a flat list of configuration values rather than structured objects. It therefore returned no separate display-name field. `DOTNETCORE:10.0` is the exact value observed for .NET 10 and the unambiguous candidate deployment/runtime value, but it is not selected while support status remains unconfirmed.

## Runtime decision

**Not confirmed.** The project does not yet accept .NET 10 as its final target.

The local toolchain includes .NET SDK `10.0.301`, Azure CLI authentication was valid, and the compatible available-runtime query succeeded and returned `DOTNETCORE:10.0`. However, Azure CLI 2.85.0 rejected the required `--runtime dotnet --support supported` filters and did not return support-status metadata. The required supported-only evidence is therefore missing, so the observed value is not promoted to the selected canonical deployment value.

Local SDK availability and App Service support are separate conditions. Local availability is confirmed; App Service supported-runtime classification is not.

## Security and redaction controls

Raw command output was not copied into this record. Validation output was reduced to versions, coarse operating-system information, authentication validity, and the relevant runtime values.

The following were deliberately omitted: subscription and tenant details, account and cloud identifiers, client IDs, email addresses, usernames, machine names, local paths, installation paths, workload manifest paths, resource IDs, tokens, cookies, credentials, secrets, and personal data. No screenshots were captured.

## Limitations and deferred validation

- Azure CLI 2.85.0 predates the structured output and `--runtime`/`--support` filters described by its own forthcoming breaking-change notice. The CLI-documented compatible list operation supplied candidate configuration values but could not prove their support classification.
- Revalidation is deferred until a permitted environment has an Azure CLI version that returns explicit support status. No tool was installed or upgraded during this milestone.
- This milestone does not validate application compilation, target-framework configuration, deployment, App Service behavior, Azure resource configuration, authentication flows, authorization policies, Managed Identity, Key Vault access, or telemetry.
- No Azure resources were created, updated, restarted, deployed, assigned permissions, or deleted.
