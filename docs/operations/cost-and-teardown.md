# Cost and teardown operations

This document is non-executable. The accumulated owner-validated state is one development Resource Group, one Standard Key Vault containing the three synthetic secret fixtures and versions, and the validated development-user reader role. B4-D9 App Service resources remain pending owner deployment.

## Current and pending Azure resources

- Development Resource Group: deployed.
- Standard Key Vault: deployed, purge protected, and validated.
- Development-user vault-scoped `Key Vault Secrets User`: deployed and validated.
- Linux App Service Plan F1 and empty Linux Web App: repository implementation present; owner deployment and Azure validation pending.
- Web App system-assigned Managed Identity: created only when the pending Web App deployment occurs; B4-D9 assigns it no role.
- Application Insights and Log Analytics: not introduced and deferred.

## Expected sources of cost

The F1 plan has no fixed plan charge for this learning scenario, subject to Azure Free tier quotas, availability, and service limits. It is a learning-only tier with no production recommendation or production availability claim. Related services, usage beyond free limits, a later paid tier, telemetry, networking, or retained data may introduce costs.

The deployed Standard Key Vault can incur operation and retained-version costs. Future Application Insights and Log Analytics usage would introduce ingestion and retention charges, but B4-D9 creates neither service.

## Rules for keeping costs low

- Keep `provisionAppServiceHosting = false` until an owner deliberately prepares and reviews the private parameters.
- Use F1 only for the scoped learning validation; do not represent it as production hosting.
- Do not publish the application merely to validate the empty hosting foundation.
- Deploy only resources required by the active milestone.
- Avoid duplicate environments, paid scaling, slots, telemetry, and networking features unless separately approved.
- Keep only the three required synthetic secrets and their single initial versions.

## Teardown implications

Capture only sanitized evidence before teardown. Remove the Web App before its plan when dismantling only the hosting foundation. Deleting the Web App also deletes its system-assigned identity. B4-D9 creates no assignment for that identity, but any future RBAC assignment introduced by B4-D10 or another milestone must be reviewed and removed as part of teardown so a deleted principal does not leave an orphaned assignment.

The Key Vault is independent of the App Service lifecycle. Removing the Web App or plan must not remove, recreate, or modify the vault, its three synthetic secret versions, or the development-user reader assignment. The vault remains purge protected with seven-day soft-delete retention. Deleting the Resource Group would delete both hosting and vault resources and leave the vault recoverable until retention completes, so a hosting-only teardown must not delete the Resource Group.

No teardown command or automation is supplied by B4-D9. Resource deletion requires a separately reviewed owner action.

## Conceptual hosting-only teardown order

1. Capture sanitized validation evidence without names, identifiers, hostnames, principals, or settings.
2. Review and remove any future direct or inherited RBAC assignment involving the Web App identity.
3. Delete the Web App, which also removes its system-assigned identity.
4. Delete the now-unused App Service Plan.
5. Confirm privately that the development Resource Group, Key Vault, synthetic secrets, and development-user reader assignment remain intact.

## Full-environment considerations

Microsoft Entra application registrations, service principals, app-role assignments, future redirect URIs, CI/CD identities, and federated credentials may outlive Azure resource deletion. They require separate owner review. Purge protection deliberately prevents immediate Key Vault purge and name reuse. Never publish resource names, IDs, tenant metadata, principals, tokens, connection strings, or raw teardown diagnostics as evidence.
