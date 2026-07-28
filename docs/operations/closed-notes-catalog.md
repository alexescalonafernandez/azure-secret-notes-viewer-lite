# Closed notes catalog and application service boundary

## Milestone

`B4-D6 — Closed Notes Catalog and Application Service Boundary`

## Purpose and scope

B4-D6 implements the application-owned closed catalog and its minimal service
and provider boundary:

```text
Razor Page
→ IReadNotesService
→ ClosedNoteCatalog
→ INoteContentProvider
→ InMemoryNoteContentProvider
```

This milestone does not implement Azure Key Vault, an Azure SDK adapter, Managed
Identity, Azure RBAC, deployment, or Azure infrastructure.

## Implemented flow

```text
Razor Page
→ IReadNotesService
→ ClosedNoteCatalog
→ INoteContentProvider
→ InMemoryNoteContentProvider
```

An authorized `/Notes` request reaches the PageModel only after the existing
`ReadSecretNotes` policy succeeds. The PageModel accepts no identifier input and
loads the complete catalog through `IReadNotesService`.

`ClosedNoteCatalog` owns exactly three definitions, including their membership,
order, and display names. Each definition uses one of the known `NoteId` members.
Only known `NoteId` values are valid. Their safe logical representations are not
physical Key Vault names.

`ReadNotesService` reads definitions only from the catalog, requests content in
catalog order, and returns immutable `NoteItem` records through a read-only
collection. It accepts no external identifier and contains no authorization,
Azure, caching, or persistence logic.

`INoteContentProvider` accepts only `NoteId` and cannot enumerate notes. Raw
identifier strings never reach the provider. The current
`InMemoryNoteContentProvider` returns deterministic, explicitly synthetic content
without configuration, Azure dependencies, logging, or mutable state.

## Request-input resistance

Razor defines no identifier route, query binding, form, selection link, or
handler argument. Query strings therefore cannot alter or expand the catalog.
Requests such as `?noteId=unknown` and `?secretName=arbitrary` still render only
the three application-owned catalog items for an authorized user.

The provider never receives raw request input or a raw identifier string. Note
content is never logged. The `/Notes` no-store response-cache policy remains in
place.

## Running validation

Run the complete automated validation from the repository root:

```bash
dotnet restore SecretNotesViewer.slnx

dotnet build SecretNotesViewer.slnx \
  --configuration Release \
  --no-restore

dotnet test SecretNotesViewer.slnx \
  --configuration Release \
  --no-build

git diff --check
```

## Manual validation

Start the application with the existing HTTPS launch profile:

```bash
dotnet run \
  --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj \
  --launch-profile https
```

Use this sanitized checklist without recording authentication URLs, identity
values, claims, tokens, cookies, or User Secrets:

```text
[ ] / remains public
[ ] /Privacy remains public
[ ] /health remains public
[ ] signed-out /Notes starts Microsoft Entra sign-in
[ ] assigned user completes sign-in
[ ] assigned user can open /Notes
[ ] exactly three catalog items are displayed
[ ] each item displays its logical ID, display name, and synthetic content
[ ] /Notes?noteId=unknown does not change or expand the catalog
[ ] /Notes?secretName=arbitrary does not change or expand the catalog
[ ] no user, role, claim, token, tenant, credential, or physical secret name is displayed
[ ] Cache-Control contains no-store
[ ] sign-out returns to /
[ ] final home page displays Not signed in
```

## Identity and permissions

Microsoft Entra authentication and `SecretNotes.Reader` authorization are
unchanged. Authorization still occurs before service execution. The application
role grants access only to the application feature. Human users receive no Azure
permissions and are not Key Vault callers.

## Security limitations

- `InMemoryNoteContentProvider` is demonstration-only.
- Its explicitly synthetic content is not representative of production secret
  material.
- There is no Key Vault adapter.
- There is no logical-to-physical name mapping.
- There is no Azure SDK integration.
- There is no Managed Identity or Azure RBAC integration.
- No arbitrary identifier can reach the provider.
- Authorization remains the PageModel's `ReadSecretNotes` policy.
- No note content is logged.
- Future retrieved note values must never be committed or captured as evidence.

## Deferred flow

```text
INoteContentProvider
→ Key Vault provider adapter
→ logical-to-physical mapping
→ SecretClient
→ Managed Identity
→ Azure Key Vault
```

The Key Vault provider adapter, physical-name mapping, Azure SDK, Managed
Identity, Azure RBAC, infrastructure, deployment, telemetry, and CI/CD remain
deferred.
