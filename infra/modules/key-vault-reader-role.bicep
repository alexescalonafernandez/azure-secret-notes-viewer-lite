targetScope = 'resourceGroup'

@description('Name of the existing Key Vault.')
param keyVaultName string

@description('Object ID of the individual development user.')
param principalId string

var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

resource developmentKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource developmentReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(developmentKeyVault.id, principalId, keyVaultSecretsUserRoleDefinitionId)
  scope: developmentKeyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: principalId
    principalType: 'User'
  }
}
