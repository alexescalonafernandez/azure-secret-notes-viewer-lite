targetScope = 'subscription'

@description('Name of the resource group.')
param resourceGroupName string

@allowed([
  'westeurope'
])
@description('Azure region for the resource group.')
param location string

@description('Non-identifying resource tags.')
param tags object

resource developmentResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}
