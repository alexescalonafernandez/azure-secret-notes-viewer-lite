# Local Development

## Purpose

This guide describes how to restore, build, run, and smoke-test the Secret Notes Viewer Lite Razor Pages application locally.

## Prerequisites

- .NET 10 SDK
- Git

Azure CLI authentication and Azure resources are not required for this milestone.

## Repository structure

```text
SecretNotesViewer.slnx
└── src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

The repository currently contains one solution and one Razor Pages web project. Operational and architecture documentation is under `docs`.

## Restore

From the repository root:

```bash
dotnet restore SecretNotesViewer.slnx
```

## Build

Build the solution in Release mode using the restored dependencies:

```bash
dotnet build SecretNotesViewer.slnx \
  --configuration Release \
  --no-restore
```

## Run

Start the application from the repository root:

```bash
dotnet run \
  --project src/SecretNotesViewer.Web/SecretNotesViewer.Web.csproj
```

ASP.NET Core prints one or more `Now listening on:` messages. Use the loopback URL shown there, such as `http://localhost:5046`. The exact port can differ if the launch profile changes or an explicit URL is supplied.

## Local smoke validation

With the application running, verify these requests against the printed loopback URL:

```text
GET /
GET /health
```

For example, in Windows PowerShell:

```powershell
$baseUrl = "http://localhost:5046"
$home = Invoke-WebRequest -Uri "$baseUrl/"
$health = Invoke-WebRequest -Uri "$baseUrl/health"

$home.StatusCode
$home.Content -match "Secret Notes Viewer Lite"
$health.StatusCode
$health.Content
```

Expected results:

- `/` returns HTTP 200.
- The home page contains `Secret Notes Viewer Lite`.
- `/health` returns HTTP 200.
- The health response is minimal and contains no diagnostics, environment details, configuration, dependency details, identifiers, or sensitive information.

## Stop the application

Return to the terminal running the application and press `Ctrl+C`. Confirm the process exits before closing the terminal.

## Security rules

Use only loopback addresses for local validation. Never place secrets, credentials, tokens, passwords, personal information, Azure identifiers, or realistic secret values in source files, configuration, command output, screenshots, or documentation.

## Current limitations

This milestone provides only the local application skeleton and a process health endpoint. `/Notes`, Microsoft Entra ID authentication, `SecretNotes.Reader` authorization, Managed Identity, Azure Key Vault integration, Azure infrastructure, telemetry, deployment automation, and CI/CD remain deferred.
