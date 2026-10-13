targetScope = 'resourceGroup'

param containerEnvironmentId string
param identityId string
param acrLoginServer string
param services array
param jobReplicaTimeout int = 1800
param jobReplicaRetryLimit int = 1
param jobParallelism int = 1
param jobCompletionCount int = 1

var apps = filter(services, service => service.role != 'jobs')
var jobs = filter(services, service => service.role == 'jobs')

resource containerApps 'Microsoft.App/containerApps@2023-05-01' = [for service in apps: {
  name: service.name
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnvironmentId
    configuration: union({
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: acrLoginServer
          identity: identityId
        }
      ]
      secrets: map(service.secrets, secret => {
        name: secret.name
        keyVaultUrl: secret.keyVaultUrl
        identity: identityId
      })
    }, service.externalIngress ? {
      ingress: {
        external: true
        targetPort: service.targetPort
        transport: 'auto'
        allowInsecure: false
      }
    } : {})
    template: {
      containers: [
        {
          name: service.name
          image: service.image
          command: service.command
          args: service.args
          env: map(service.env, item => contains(item, 'secretRef') ? {
            name: item.name
            secretRef: item.secretRef
          } : {
            name: item.name
            value: item.value
          })
          resources: {
            cpu: service.cpu
            memory: service.memory
          }
        }
      ]
      scale: {
        minReplicas: service.minReplicas
        maxReplicas: service.maxReplicas
      }
    }
  }
}]

resource containerJobs 'Microsoft.App/jobs@2023-05-01' = [for service in jobs: {
  name: service.name
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: containerEnvironmentId
    configuration: union({
      replicaTimeout: jobReplicaTimeout
      replicaRetryLimit: jobReplicaRetryLimit
      registries: [
        {
          server: acrLoginServer
          identity: identityId
        }
      ]
      secrets: map(service.secrets, secret => {
        name: secret.name
        keyVaultUrl: secret.keyVaultUrl
        identity: identityId
      })
    }, empty(service.schedule) ? {
      triggerType: 'Manual'
      manualTriggerConfig: {
        parallelism: jobParallelism
        replicaCompletionCount: jobCompletionCount
      }
    } : {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: service.schedule
        parallelism: jobParallelism
        replicaCompletionCount: jobCompletionCount
      }
    })
    template: {
      containers: [
        {
          name: service.name
          image: service.image
          command: service.command
          args: service.args
          env: map(service.env, item => contains(item, 'secretRef') ? {
            name: item.name
            secretRef: item.secretRef
          } : {
            name: item.name
            value: item.value
          })
          resources: {
            cpu: service.cpu
            memory: service.memory
          }
        }
      ]
    }
  }
}]

output applicationUrls array = [for (service, index) in apps: if (service.externalIngress) 'https://${containerApps[index].properties.configuration.ingress.fqdn}']
output containerAppNames array = [for (service, index) in apps: containerApps[index].name]
output containerJobNames array = [for (service, index) in jobs: containerJobs[index].name]
