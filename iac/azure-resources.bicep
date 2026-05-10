// ============================================================
// azure-resources.bicep
// Resources for openclaw-agent365 on Azure Container Apps
//
// Provisions:
//   - Azure Container Registry (ACR)
//   - Azure Container Apps Environment + Container App
//   - Key Vault (with Key Vault references for secrets)
//   - Application Insights (workspace-based)
//   - Log Analytics Workspace
//   - App Registration outputs (manual step documented below)
//
// Deploy:
//   az deployment group create \
//     --resource-group <rg> \
//     --template-file iac/azure-resources.bicep \
//     --parameters @iac/parameters.json
// ============================================================

targetScope = 'resourceGroup'

@description('Environment: development | staging | production')
@allowed(['development', 'staging', 'production'])
param environment string = 'development'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Short name prefix for all resources (3-8 alphanum)')
@maxLength(8)
param namePrefix string = 'oca365'

@description('Container image to deploy, e.g. <acr>.azurecr.io/openclaw-agent365:v1.0.0')
param containerImage string

@description('Agentic App ID (A365_APP_ID) — from App Registration')
param a365AppId string

@description('Autonomous Agent Instance ID (AA_INSTANCE_ID) — from Agent365 registration')
param aaInstanceId string

@description('Agent identity UPN, e.g. agent@contoso.com')
param agentIdentity string

@description('Owner UPN, e.g. user@contoso.com')
param owner string

@description('Owner Entra ID Object ID')
param ownerAadId string

@description('OpenClaw primary LLM model')
param openclawModel string = 'anthropic/claude-opus-4-6'

var suffix = '${namePrefix}-${environment}'
var acrName = replace('acr${namePrefix}${environment}', '-', '')

// ─── Log Analytics Workspace ─────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${suffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ─── Application Insights ────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${suffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ─── Azure Container Registry ────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false   // Use managed identity, not admin creds
  }
}

// ─── Key Vault ───────────────────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${suffix}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true    // Use RBAC, not access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ─── Container Apps Environment ──────────────────────────────────────────────
resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${suffix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ─── Container App ───────────────────────────────────────────────────────────
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${suffix}'
  location: location
  identity: {
    type: 'SystemAssigned'   // Used to pull ACR images and read Key Vault
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3978
        transport: 'http'
        // Health probe — aligns with acceptance criteria
      }
      // Secrets resolved from Key Vault via Key Vault references
      secrets: [
        {
          name: 'a365-app-password'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/A365-APP-PASSWORD'
          identity: 'system'
        }
        {
          name: 'anthropic-api-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/ANTHROPIC-API-KEY'
          identity: 'system'
        }
        {
          name: 'appinsights-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/APPINSIGHTS-CONNECTION-STRING'
          identity: 'system'
        }
      ]
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ]
    }
    template: {
      scale: {
        minReplicas: 1
        maxReplicas: 5
      }
      containers: [
        {
          name: 'openclaw-agent365'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'APP_ENV',                    value: environment }
            { name: 'PORT',                       value: '3978' }
            { name: 'OPENCLAW_MODEL',             value: openclawModel }
            { name: 'A365_APP_ID',                value: a365AppId }
            { name: 'A365_APP_PASSWORD',          secretRef: 'a365-app-password' }
            { name: 'A365_TENANT_ID',             value: subscription().tenantId }
            { name: 'MICROSOFT_APP_TYPE',         value: 'SingleTenant' }
            { name: 'AA_INSTANCE_ID',             value: aaInstanceId }
            { name: 'AGENT_IDENTITY',             value: agentIdentity }
            { name: 'OWNER',                      value: owner }
            { name: 'OWNER_AAD_ID',               value: ownerAadId }
            { name: 'ANTHROPIC_API_KEY',          secretRef: 'anthropic-api-key' }
            { name: 'NETWORK_MODE',               value: 'unrestricted' }
            { name: 'KEY_VAULT_URI',              value: keyVault.properties.vaultUri }
            { name: 'OTEL_SERVICE_NAME',          value: 'openclaw-agent365' }
            { name: 'APPINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3978
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 3978
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
    }
  }
}

// ─── Azure Bot Service ───────────────────────────────────────────────────────
// Registers the agent with the Bot Framework; required for Teams channel
resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: 'bot-${suffix}'
  location: 'global'       // Bot Service is a global resource
  sku: {
    name: 'F0'             // Free tier; switch to S1 for SLA
  }
  kind: 'azurebot'
  properties: {
    displayName: 'OpenClaw Agent 365 (${environment})'
    description: 'Autonomous AI assistant powered by OpenClaw + Agent 365'
    endpoint: 'https://${containerApp.properties.configuration.ingress.fqdn}/api/messages'
    msaAppId: a365AppId
    msaAppType: 'SingleTenant'
    msaAppTenantId: subscription().tenantId
    schemaTransformationVersion: '1.3'
    isStreamingSupported: false
  }
}

// Register the Microsoft Teams channel on the Bot Service
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  name: 'MsTeamsChannel'
  parent: botService
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      enableCalling: false
      isEnabled: true
    }
  }
}

// ─── RBAC: Container App → ACR (AcrPull) ─────────────────────────────────────
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerApp.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ─── RBAC: Container App → Key Vault (Key Vault Secrets User) ────────────────
resource kvSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, containerApp.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output acrLoginServer string = acr.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output containerAppPrincipalId string = containerApp.identity.principalId
output botServiceName string = botService.name
output botMessagingEndpoint string = botService.properties.endpoint

// ─── Post-deployment steps ───────────────────────────────────────────────────
// The following operations are automated by scripts/ — do not run them by hand.
//
//   App Registration + FIC + admin consent:
//     pnpm run az:app-reg -- --display-name "openclaw-agent365-${environment}" \
//                            --agent-identity <upn> --write-env
//
//   Seed Key Vault from .env (A365_APP_PASSWORD, ANTHROPIC_API_KEY,
//   APPINSIGHTS_CONNECTION_STRING, optional LLM keys):
//     pnpm run az:kv-seed
//
//   Build image + roll out new Container App revision:
//     pnpm run az:deploy
//
//   Tear down (development RGs only):
//     pnpm run az:teardown -- --resource-group <rg>
//
// See README → "Azure CLI setup" and docs/release-checklist.md.
