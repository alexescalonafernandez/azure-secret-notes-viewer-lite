# Closed notes catalog and application service boundary

## Milestone

`B4-D6 — Closed Notes Catalog and Application Service Boundary`

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

## Identity and permissions

Microsoft Entra authentication and `SecretNotes.Reader` authorization are
unchanged. Authorization still occurs before service execution. The application
role grants access only to the application feature. Human users receive no Azure
permissions and are not Key Vault callers.

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
