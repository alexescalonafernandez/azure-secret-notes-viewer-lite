# AI-Assisted Engineering Guide

## Project purpose

Secret Notes Viewer Lite is a security-focused Azure learning project built with ASP.NET Core Razor Pages. Future milestones will add Microsoft Entra ID authentication, app-role authorization, Managed Identity, and Azure Key Vault integration.

## Current structure

- One `SecretNotesViewer.slnx` solution.
- One Razor Pages project at `src/SecretNotesViewer.Web`.
- Documentation under `docs`.
- No architectural project split yet.

## Engineering rules

- Target `net10.0`.
- Keep changes small and scoped to the current milestone.
- Do not introduce projects or architectural layers without explicit authorization.
- Do not add packages without a concrete requirement.
- Preserve readable, conventional C#.
- Update documentation when behavior or operational workflows change.
- Inspect the final Git diff.

## Required validation

For application changes, normally run:

```bash
dotnet restore SecretNotesViewer.slnx
dotnet build SecretNotesViewer.slnx --configuration Release --no-restore
git diff --check
```

Add meaningful automated tests when project-owned behavior is introduced. Do not create artificial tests for unchanged framework-generated boilerplate.

## Security rules

Never commit or expose secrets, credentials, tokens, passwords, tenant IDs, subscription IDs, client IDs, account email addresses, personal information, real Azure resource identifiers, or realistic secret values.

Do not perform Azure write operations unless the current task explicitly authorizes them.
