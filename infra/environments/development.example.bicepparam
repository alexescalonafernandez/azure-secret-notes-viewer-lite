using '../main.bicep'

param resourceGroupName = '<set-local-resource-group-name>'
param keyVaultName = '<set-local-key-vault-name>'
param assignDevelopmentReaderRole = false
param provisionAppServiceHosting = false
param appServicePlanName = '<set-local-app-service-plan-name>'
param webAppName = '<set-local-web-app-name>'
param configureCloudRuntime = false
param cloudTenantId = '<set-private-cloud-tenant-id>'
param cloudAppClientId = '<set-private-cloud-app-client-id>'
