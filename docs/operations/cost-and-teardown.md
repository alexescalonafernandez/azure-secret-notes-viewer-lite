# Cost and teardown operations

This document is conceptual for the B4-D0 baseline. It does not include executable deployment or deletion commands.

## Planned Azure resources

- Resource Group.
- Azure App Service Plan for low-cost learning usage.
- Azure App Service with system-assigned Managed Identity.
- Azure Key Vault using Azure RBAC.
- Optional Application Insights or Log Analytics in a later milestone.
- Microsoft Entra ID application registration, service principal, and app role created through manual documented bootstrap.

## Expected sources of cost

- App Service Plan compute charges while allocated.
- Application Insights or Log Analytics ingestion and retention if enabled later.
- Key Vault operations, storage, and optional retention-related costs.
- Incidental costs from diagnostic settings or retained logs.

## Rules for keeping costs low

- Use the smallest appropriate App Service Plan for the learning scenario.
- Deploy only the resources required for the active milestone.
- Avoid duplicate environments unless explicitly needed.
- Keep observability moderate and avoid verbose request, dependency, or custom-event logging.
- Remove resources promptly when validation is complete.
- Do not use production-grade scale, premium tiers, or long retention unless a later decision explicitly requires them.

## Moderate observability and telemetry usage

Telemetry should help validate authentication, authorization, Managed Identity, and Key Vault behavior without collecting secrets or sensitive identifiers. Sampling, retention, and log categories should be conservative. Secret values must never appear in Application Insights telemetry, custom properties, metrics, events, exceptions, traces, screenshots, or terminal evidence.

## When resources should be removed

Remove Azure resources when:

- A milestone demonstration is complete.
- The environment is no longer actively used.
- Cost monitoring indicates unexpected spend.
- Identity or permission experiments create uncertainty about the current state.
- A teardown validation is required before rebuilding from documentation.

## Conceptual teardown order

1. Capture only non-sensitive validation evidence.
2. Remove app-role assignments that are no longer needed.
3. Remove Key Vault Azure RBAC assignments for the Managed Identity.
4. Delete the App Service to remove the system-assigned Managed Identity.
5. Delete or purge Key Vault according to the documented retention and recovery plan.
6. Delete the App Service Plan when no apps depend on it.
7. Delete the Resource Group after confirming no required resources remain.
8. Manually review Microsoft Entra ID objects and remove application registrations or service principals that are no longer needed.

## Possible orphaned resources or identities

- Microsoft Entra ID application registrations and service principals created manually.
- App-role assignments on users or groups.
- Azure RBAC role assignments whose principal was deleted with the App Service Managed Identity.
- Retained Key Vault instances or soft-deleted vaults.
- Log Analytics workspaces, Application Insights components, or diagnostic settings created later.

## Validation after teardown

- Confirm the Resource Group no longer contains active resources.
- Confirm the App Service endpoint is unavailable.
- Confirm the Managed Identity can no longer access Key Vault.
- Confirm there are no unexpected Azure RBAC assignments for deleted principals.
- Confirm telemetry resources are deleted or retained intentionally with safe retention settings.
- Confirm no secret values were captured in teardown evidence.

## Manual cleanup of Entra ID objects

Entra ID objects may outlive Azure resource deletion. Manual cleanup should review application registrations, enterprise applications, app roles, app-role assignments, owners, redirect URIs, and any future CI/CD federated credentials. Cleanup evidence must not include tenant IDs, client IDs, tokens, personal data, or other sensitive identifiers.
