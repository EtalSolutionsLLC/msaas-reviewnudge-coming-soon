targetScope = 'subscription'

param location string
param resourceGroupName string
param containerEnvironmentName string
param logAnalyticsName string
param acrName string
param acrSku string = 'Basic'
param keyVaultName string
param identityName string
param includeServiceBus bool = false
param serviceBusNamespaceName string
param serviceBusSku string = 'Standard'
param serviceBusQueues array = []
param deploymentPrincipalId string

@allowed([
  'User'
  'ServicePrincipal'
])
param deploymentPrincipalType string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
}

module platformResources './modules/platform-resources.bicep' = {
  name: '${resourceGroupName}-platform'
  scope: resourceGroup
  params: {
    location: location
    containerEnvironmentName: containerEnvironmentName
    logAnalyticsName: logAnalyticsName
    acrName: acrName
    acrSku: acrSku
    keyVaultName: keyVaultName
    identityName: identityName
    includeServiceBus: includeServiceBus
    serviceBusNamespaceName: serviceBusNamespaceName
    serviceBusSku: serviceBusSku
    serviceBusQueues: serviceBusQueues
    deploymentPrincipalId: deploymentPrincipalId
    deploymentPrincipalType: deploymentPrincipalType
  }
}

output resourceGroupName string = resourceGroup.name
output containerEnvironmentName string = platformResources.outputs.containerEnvironmentName
output containerEnvironmentId string = platformResources.outputs.containerEnvironmentId
output acrName string = platformResources.outputs.acrName
output acrId string = platformResources.outputs.acrId
output acrLoginServer string = platformResources.outputs.acrLoginServer
output keyVaultName string = platformResources.outputs.keyVaultName
output keyVaultId string = platformResources.outputs.keyVaultId
output identityName string = platformResources.outputs.identityName
output identityId string = platformResources.outputs.identityId
output identityPrincipalId string = platformResources.outputs.identityPrincipalId
output identityClientId string = platformResources.outputs.identityClientId
output serviceBusNamespaceName string = platformResources.outputs.serviceBusNamespaceName
