targetScope = 'subscription'

@description('Name of the dedicated development resource group.')
param resourceGroupName string

@description('Globally unique name of the development Key Vault.')
param keyVaultName string

@description('Whether to persist the final Key Vault Secrets User assignment for the development user.')
param assignDevelopmentReaderRole bool = false

@description('Whether to provision the B4-D9 App Service hosting foundation.')
param provisionAppServiceHosting bool = false

@description('Name of the Linux App Service Plan. Required when App Service hosting is enabled.')
param appServicePlanName string = ''

@description('Globally unique name of the Linux Web App. Required when App Service hosting is enabled.')
param webAppName string = ''

@allowed([
  'westeurope'
])
@description('Azure region for the development resources.')
param location string = 'westeurope'

var tags = {
  environment: 'development'
  workload: 'secret-notes-viewer-lite'
  managedBy: 'bicep'
}

module developmentResourceGroup 'modules/resource-group.bicep' = {
  name: 'development-resource-group'
  params: {
    resourceGroupName: resourceGroupName
    location: location
    tags: tags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'development-key-vault'
  scope: resourceGroup(resourceGroupName)
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
  }
  dependsOn: [
    developmentResourceGroup
  ]
}

module keyVaultReaderRole 'modules/key-vault-reader-role.bicep' = if (assignDevelopmentReaderRole) {
  name: 'development-key-vault-reader-role'
  scope: resourceGroup(resourceGroupName)
  params: {
    keyVaultName: keyVaultName
    principalId: deployer().objectId
  }
  dependsOn: [
    keyVault
  ]
}

module appServicePlan 'modules/app-service-plan.bicep' = if (provisionAppServiceHosting) {
  name: 'development-app-service-plan'
  scope: resourceGroup(resourceGroupName)
  params: {
    appServicePlanName: appServicePlanName
    location: location
    tags: tags
  }
  dependsOn: [
    developmentResourceGroup
  ]
}

module webApp 'modules/web-app.bicep' = if (provisionAppServiceHosting) {
  name: 'development-web-app'
  scope: resourceGroup(resourceGroupName)
  params: {
    webAppName: webAppName
    appServicePlanId: appServicePlan!.outputs.planResourceId
    location: location
    tags: tags
  }
}
