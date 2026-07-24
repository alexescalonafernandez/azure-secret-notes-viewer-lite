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

Azure CLI 2.85.0 did not recognize the newer `--runtime` and `--support` filters. The compatible unfiltered Linux runtime command succeeded, and its flat output was filtered locally to the relevant .NET entries. The detailed-output option returned the same flat values.

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

The compatible Azure CLI command for viewing supported App Service Linux runtimes returned these relevant .NET entries:

| .NET version | Value returned by Azure CLI |
| --- | --- |
| .NET 10 | `DOTNETCORE:10.0` |
| .NET 9 | `DOTNETCORE:9.0` |
| .NET 8 | `DOTNETCORE:8.0` |

Azure CLI 2.85.0 returned a flat list of runtime arguments rather than separate display names and configuration fields. The two deployment syntaxes have distinct purposes:

| Purpose | Value |
| --- | --- |
| Azure CLI runtime argument, including `az webapp create --runtime` | `DOTNETCORE:10.0` |
| App Service `linuxFxVersion`, including Bicep, ARM, site configuration, and `az webapp config set --linux-fx-version` | `DOTNETCORE|10.0` |

`DOTNETCORE:10.0` is the canonical Azure CLI runtime argument observed directly from `az webapp list-runtimes`. `DOTNETCORE|10.0` is the App Service `linuxFxVersion` intended for later Bicep configuration. These values are not interchangeable strings.

## Runtime decision

**Confirmed.** The project accepts .NET 10 as its target.

```text
Target framework: net10.0
Azure CLI runtime argument: DOTNETCORE:10.0
Bicep/App Service linuxFxVersion: DOTNETCORE|10.0
Decision: Confirmed
```

The local toolchain includes .NET SDK `10.0.301`, Azure CLI authentication was valid, and the compatible App Service Linux runtime query succeeded and returned `DOTNETCORE:10.0`. Local SDK availability and App Service runtime availability were validated separately, and both conditions were satisfied.

## Security and redaction controls

Raw command output was not copied into this record. Validation output was reduced to versions, coarse operating-system information, authentication validity, and the relevant runtime values.

The following were deliberately omitted: subscription and tenant details, account and cloud identifiers, client IDs, email addresses, usernames, machine names, local paths, installation paths, workload manifest paths, resource IDs, tokens, cookies, credentials, secrets, and personal data. No screenshots were captured.

## Limitations and deferred validation

- Azure CLI 2.85.0 did not recognize the newer `--runtime` and `--support` filters. The compatible unfiltered Linux runtime command succeeded, and its flat output was filtered locally to the relevant .NET entries.
- This milestone confirms toolchain and runtime availability only. It does not validate application compilation, deployment, execution in App Service, Azure resource configuration, authentication flows, authorization policies, Managed Identity, Key Vault access, or telemetry.
- Later Bicep work must use `DOTNETCORE|10.0` for `linuxFxVersion`, not the colon-form Azure CLI runtime argument.
- No tool was installed or upgraded during this milestone.
- No Azure resources were created, updated, restarted, deployed, assigned permissions, or deleted.
