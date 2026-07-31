targetScope = 'resourceGroup'

@description('Globally unique name of the Linux Web App.')
param webAppName string

@description('Resource ID of the App Service Plan that hosts the Web App.')
param appServicePlanId string

@allowed([
  'westeurope'
])
@description('Azure region for the Web App.')
param location string

@description('Non-identifying resource tags.')
param tags object

resource webApp 'Microsoft.Web/sites@2025-03-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
  }
}

resource scmPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}
