targetScope = 'resourceGroup'

@description('Name of the existing Linux Web App whose persistent App Settings are replaced.')
param webAppName string

@secure()
@description('Private Microsoft Entra tenant ID for cloud browser authentication.')
param cloudTenantId string

@secure()
@description('Private client ID of the cloud browser-authentication App Registration.')
param cloudAppClientId string

resource existingWebApp 'Microsoft.Web/sites@2025-03-01' existing = {
  name: webAppName
}

// Microsoft.Web/sites/config replaces the complete persistent App Settings set.
// Keep this object as the exact B4-D10B state; do not merge unknown settings here.
resource exactRuntimeAppSettings 'Microsoft.Web/sites/config@2025-03-01' = {
  parent: existingWebApp
  name: 'appsettings'
  properties: {
    ASPNETCORE_ENVIRONMENT: 'Production'
    AzureAd__TenantId: cloudTenantId
    AzureAd__ClientId: cloudAppClientId
    AzureAd__ClientCredentials__0__SourceType: 'SignedAssertionFromManagedIdentity'
    NoteContent__Provider: 'InMemory'
  }
}
