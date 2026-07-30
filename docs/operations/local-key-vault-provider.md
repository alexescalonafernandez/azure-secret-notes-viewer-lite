# Local Key Vault note provider

## Status and boundaries

B4-D8 repository implementation and Azure-free validation are present. Owner-run interactive validation against the existing development Key Vault is pending; do not treat the milestone as complete until the repository owner performs the sequence below.

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

This is intentionally an owner-run procedure. It must not be automated by Codex.

1. Privately confirm that the active Azure CLI identity is the same identity validated in B4-D7. Do not print or publish account metadata.
2. Set the five User Secrets above with the real private local values.
3. Start the application with the existing HTTPS development launch profile:

   ```powershell
   dotnet run `
       --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj `
       --launch-profile https
   ```

4. Sign in through the browser with a user assigned `SecretNotes.Reader`.
5. Open `/Notes` and confirm the fixed three-note order and expected synthetic values without copying values into evidence.
6. Confirm that arbitrary `noteId` and `secretName` query strings do not change membership, order, or content selection.
7. Stop the application. Record only a sanitized pass/fail conclusion; do not capture raw Azure errors or note content.

## Return to the committed default

Switch the local override back without deleting the private mapping:

```powershell
dotnet user-secrets set "NoteContent:Provider" "InMemory" `
    --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

The application then registers only `InMemoryNoteContentProvider`; it does not bind Key Vault options or register `AzureCliCredential` or `SecretClient`.
