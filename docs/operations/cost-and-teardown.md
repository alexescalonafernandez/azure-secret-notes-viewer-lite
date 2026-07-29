# Cost and teardown operations

This document remains non-executable. B4-D7 adds a repository definition for one development Resource Group and one Standard Key Vault, but the repository owner has not deployed them at branch-publication time.

## Planned Azure resources

- Development Resource Group and Standard Key Vault: implemented in Bicep; planned manual deployment.
- Azure App Service Plan for low-cost learning usage.
- Azure App Service with system-assigned Managed Identity.
- Application Insights connected to a Log Analytics workspace, with implementation deferred to a later milestone.
- Microsoft Entra ID application registration, service principal, and app role created through manual documented bootstrap.

## Expected sources of cost

- App Service Plan compute charges while allocated.
- Application Insights and connected Log Analytics workspace ingestion, sampling, and retention when implemented later.
- Standard Key Vault operations and retained secret versions after owner deployment.
- Incidental costs from diagnostic settings or retained logs.

## Rules for keeping costs low

- Use the smallest appropriate App Service Plan for the learning scenario.
- Deploy only the resources required for the active milestone.
- Avoid duplicate environments unless explicitly needed.
- Keep observability moderate and avoid verbose request, dependency, or custom-event logging.
- Remove resources promptly when validation is complete.
- Keep only the three required synthetic secrets and their single initial versions.
- Do not use production-grade scale, premium tiers, or long retention unless a later decision explicitly requires them.

## Moderate observability and telemetry usage

Telemetry should help validate authentication, authorization, Managed Identity, and Key Vault behavior without collecting secrets or sensitive data. The planned baseline is Application Insights connected to a Log Analytics workspace, implemented in a later milestone. Sampling, retention, log categories, and cost controls should be conservative. Secret values must never appear in Application Insights telemetry, Log Analytics data, custom properties, metrics, events, exceptions, traces, screenshots, or terminal evidence.

## When resources should be removed

Remove Azure resources when:

- A milestone demonstration is complete.
- The environment is no longer actively used.
- Cost monitoring indicates unexpected spend.
- Identity or permission experiments create uncertainty about the current state.
- A teardown validation is required before rebuilding from documentation.

## Conceptual teardown order

1. Capture only non-sensitive validation evidence.
2. Confirm the temporary `Key Vault Secrets Officer` assignment is absent.
3. Remove the development user's final vault-scoped `Key Vault Secrets User` assignment when it is no longer needed.
4. Delete the development Resource Group only after confirming it contains no required resources.
5. Allow the purge-protected Key Vault to complete its seven-day soft-delete retention period; it cannot be purged early.
6. For later milestones, remove application RBAC, App Service, plan, telemetry, and Entra objects in dependency order.

Deleting the Resource Group does not make the vault name immediately reusable. Purge protection deliberately trades rapid teardown for recovery safety. B4-D7 includes no deletion or purge script, and repository automation must not be treated as authorization to perform teardown.

## Possible orphaned resources or identities

- Microsoft Entra ID application registrations and service principals created manually.
- App-role assignments on users or groups.
- Azure RBAC role assignments that were not removed before resource deletion.
- The soft-deleted, purge-protected Key Vault during its seven-day retention period.
- Application Insights components, connected Log Analytics workspaces, or diagnostic settings created later.

## Validation after teardown

- Confirm the Resource Group no longer contains active resources.
- Confirm the App Service endpoint is unavailable.
- Confirm the Managed Identity can no longer access Key Vault.
- Confirm there are no unexpected Azure RBAC assignments for deleted principals.
- Confirm telemetry resources are deleted or retained intentionally with safe retention settings.
- Confirm no secret values were captured in teardown evidence.

## Manual cleanup of Entra ID objects

Entra ID objects may outlive Azure resource deletion. Manual cleanup should review application registrations, enterprise applications, app roles, app-role assignments, owners, redirect URIs, and any future CI/CD federated credentials. Cleanup evidence must not include tenant IDs, client IDs, tokens, personal data, or other sensitive identifiers.
