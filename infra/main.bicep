targetScope = 'subscription'

@description('Name of the dedicated development resource group.')
param resourceGroupName string

@description('Globally unique name of the development Key Vault.')
param keyVaultName string

@description('Object ID of the individual development user who may receive final read access.')
param developmentReaderPrincipalId string

@description('Whether to persist the final Key Vault Secrets User assignment for the development user.')
param assignDevelopmentReaderRole bool = false

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
    principalId: developmentReaderPrincipalId
  }
  dependsOn: [
    keyVault
  ]
}
