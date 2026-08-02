targetScope = 'resourceGroup'

@description('Name of the Linux App Service Plan.')
param appServicePlanName string

@allowed([
  'westeurope'
])
@description('Azure region for the App Service Plan.')
param location string

@description('Non-identifying resource tags.')
param tags object

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  tags: tags
  sku: {
    name: 'F1'
    tier: 'Free'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

output planResourceId string = appServicePlan.id
