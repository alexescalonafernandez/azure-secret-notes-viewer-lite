# Local Key Vault note provider

## Status and boundaries

B4-D8 repository implementation, Azure-free validation, and owner-run interactive validation against the existing development Key Vault are complete. The milestone is ready for pull-request review but is not merged. The procedure below remains the reusable private validation runbook.

`InMemory` is the committed default. Selecting `KeyVault` is an explicit local override with no fallback. Startup then validates one HTTPS vault URI and exactly three distinct physical secret names. The code-owned mapping is closed:

```text
NoteId.Operations  → KeyVault:SecretNames:Operations
NoteId.Integration → KeyVault:SecretNames:Integration
NoteId.Recovery    → KeyVault:SecretNames:Recovery
```

`ClosedNoteCatalog` still owns membership and order. Browser input cannot select a physical name or expand the catalog. The provider registers one reusable `SecretClient`, uses only active-version `GetSecretAsync`, never enumerates secrets or versions, and does not cache or log note content. Expected Azure failures and unavailable values become the fixed `NoteContentUnavailableException`; there is no raw Azure diagnostic, physical name, vault URI, or inner exception in that application exception.

Local Key Vault mode uses `AzureCliCredential` only. It must run with the same Azure CLI identity that received and validated the B4-D7 vault-scoped `Key Vault Secrets User` assignment. The Microsoft Entra browser user, browser token, local web-app client secret, and `SecretNotes.Reader` role are not Key Vault credentials or RBAC grants.

App Service, system-assigned Managed Identity, its RBAC assignment, and deployed credential composition remain deferred.

## Configure private local values

Run these commands with private values substituted locally. Never publish the commands after substitution or commit the resulting User Secrets.

```powershell
dotnet user-secrets set "NoteContent:Provider" "KeyVault" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "KeyVault:VaultUri" "<private-key-vault-uri>" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "KeyVault:SecretNames:Operations" "<private-operations-secret-name>" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "KeyVault:SecretNames:Integration" "<private-integration-secret-name>" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj

dotnet user-secrets set "KeyVault:SecretNames:Recovery" "<private-recovery-secret-name>" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

Do not use a physical name equal, case-insensitively, to any public `demo-*` logical ID. Do not put these values in `appsettings.json`, shell history shared as evidence, Issues, pull requests, logs, screenshots, or recordings.

## Owner-run validation sequence

This remains an intentionally owner-run procedure and must not be automated by Codex. The repository owner completed it successfully for B4-D8; the unchecked items below preserve a reusable checklist rather than private execution records.

1. Privately confirm that the active Azure CLI identity is the same identity validated in B4-D7. Do not print or publish account metadata.
2. Set the five User Secrets above with the real private local values.
3. Start the application with the existing HTTPS development launch profile:

   ```powershell
   dotnet run `
       --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj `
       --launch-profile https
   ```

4. Complete the validation checklist:

   - [ ] The application starts with `Provider=KeyVault`.
   - [ ] `GET /` remains available.
   - [ ] `GET /Privacy` remains available.
   - [ ] `GET /health` remains available.
   - [ ] Anonymous `/Notes` still initiates the Microsoft Entra challenge.
   - [ ] An assigned user can open `/Notes`.
   - [ ] Exactly three notes are displayed.
   - [ ] Catalog order is unchanged.
   - [ ] All three expected synthetic values are retrieved from Key Vault.
   - [ ] `/Notes?noteId=unknown` does not alter membership, order, or selection.
   - [ ] `/Notes?secretName=arbitrary` does not alter membership, order, or selection.
   - [ ] `/Notes` responses retain `Cache-Control: no-store` behavior.
   - [ ] No identity, role, claim, token, vault URI, physical secret name, or Azure identifier is rendered.
   - [ ] Application logs contain no note values or physical secret names.
   - [ ] No raw Azure diagnostic is published.

5. Stop the application. Record only a sanitized pass/fail conclusion. Do not publish screenshots, HTTP headers containing private data, logs, User Secrets, account metadata, Azure errors, or note values.

## Sanitized validation result

The completed owner-run validation produced only these approved coarse conclusions:

```text
branch-head-valid
azure-cli-identity-valid
user-secrets-configured
key-vault-mode-started
public-endpoints-valid
anonymous-challenge-valid
authorized-notes-valid
key-vault-values-valid
closed-catalog-valid
no-store-valid
sensitive-rendering-absent
sensitive-logging-absent
in-memory-mode-valid
```

Private User Secrets, Azure identifiers, resource names, secret values, screenshots, logs, terminal output, and raw diagnostics were intentionally not recorded. After validation, the owner switched only `NoteContent:Provider` back to `InMemory`; the runbook does not claim that the private User Secrets were deleted.

## Return to the committed default

Switch the local override back without deleting the private mapping:

```powershell
dotnet user-secrets set "NoteContent:Provider" "InMemory" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

The application then registers only `InMemoryNoteContentProvider`; it does not bind Key Vault options or register `AzureCliCredential` or `SecretClient`.

Validate this explicit startup provider selection:

- [ ] The application starts without requiring Key Vault configuration or Azure access.
- [ ] `INoteContentProvider` resolves to the deterministic in-memory path.
- [ ] `/Notes` retains the same fixed catalog and authorization behavior.
