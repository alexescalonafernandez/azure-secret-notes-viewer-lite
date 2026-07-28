targetScope = 'resourceGroup'

@description('Globally unique name of the Key Vault.')
param keyVaultName string

@allowed([
  'westeurope'
])
@description('Azure region for the Key Vault.')
param location string

@description('Non-identifying resource tags.')
param tags object

resource developmentKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}
