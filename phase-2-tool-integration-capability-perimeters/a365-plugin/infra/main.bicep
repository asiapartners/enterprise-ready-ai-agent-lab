// =============================================================================
// openclaw-a365-agent-lab — Phase 1 infrastructure
//
// Provisions:
//   - Virtual Network + Subnet
//   - Static Public IP with DNS label
//   - Network Security Group (SSH from your IP, HTTPS from anywhere)
//   - Network Interface
//   - Linux VM (Ubuntu 22.04 LTS, system-assigned Managed Identity)
//   - cloud-init customData → installs Docker, Caddy, systemd unit
//   - Azure Key Vault (RBAC, soft-delete + purge protection)
//   - VM MI granted "Key Vault Secrets User" on the vault
//
// Deployment:  infra/deploy.sh dev
// =============================================================================

@description('Environment short name (dev, staging, prod). Used in resource names.')
param env string = 'dev'

@description('Azure region for all resources.')
param location string = 'swedencentral'

@description('VM admin username.')
param adminUsername string = 'azureuser'

@description('Public SSH key for the VM admin user.')
@secure()
param adminPublicKey string

@description('CIDR allowed to SSH (port 22). Set to your current public IP /32 for safety.')
param sshSourceAddressPrefix string

@description('Suffix for globally-unique names (kv, pip dns label). Default = take(uniqueString(rg.id), 6).')
param suffix string = take(uniqueString(resourceGroup().id), 6)

@description('VM size. B2ms = 2 vCPU / 8 GB, ~$60/mo.')
param vmSize string = 'Standard_B2ms'

@description('Object ID of the user/group to grant initial Key Vault Secrets Officer role (so deploy.sh can write secrets). Typically the deploying user\'s AAD Object ID.')
param deployerPrincipalId string

// ---------------------------------------------------------------------------
// Resource names (deterministic from env + suffix)
// ---------------------------------------------------------------------------
var prefix       = 'openclaw'
var vnetName     = '${prefix}-vnet-${env}'
var subnetName   = 'default'
var pipName      = '${prefix}-pip-${env}'
var dnsLabel     = '${prefix}-${suffix}'                                   // FQDN: openclaw-<suffix>.swedencentral.cloudapp.azure.com
var nsgName      = '${prefix}-nsg-${env}'
var nicName      = '${prefix}-nic-${env}'
var vmName       = '${prefix}-vm-${env}'
var kvName       = '${prefix}-kv-${suffix}'                                // ≤24 chars, lowercase

// Built-in role definition IDs
var role_KV_SecretsUser    = '4633458b-17de-408a-b874-0445c86b69e6'        // Key Vault Secrets User
var role_KV_SecretsOfficer = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'        // Key Vault Secrets Officer

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.10.0.0/16' ] }
    subnets: [
      {
        name: subnetName
        properties: { addressPrefix: '10.10.1.0/24' }
      }
    ]
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: pipName
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: dnsLabel }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh-from-deployer'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: sshSourceAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'allow-https'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-http-letsencrypt'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'                                     // ACME HTTP-01
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: '${vnet.id}/subnets/${subnetName}' }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
    networkSecurityGroup: { id: nsg.id }
  }
}

// ---------------------------------------------------------------------------
// Key Vault (RBAC, purge protection, soft-delete)
// ---------------------------------------------------------------------------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'                                       // Phase 3 → Private Endpoint
  }
}

// Grant the deployer Secrets Officer so deploy.sh can write secrets
resource kvRoleDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, deployerPrincipalId, role_KV_SecretsOfficer)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role_KV_SecretsOfficer)
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// ---------------------------------------------------------------------------
// VM with cloud-init bootstrap
// ---------------------------------------------------------------------------
var cloudInit = loadTextContent('./cloud-init.yaml')
// Substitute placeholders in cloud-init at deploy time
var cloudInitRendered = replace(replace(cloudInit, '__KV_NAME__', kvName), '__DNS_LABEL__', '${dnsLabel}.${location}.cloudapp.azure.com')

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
      customData: base64(cloudInitRendered)
    }
    networkProfile: {
      networkInterfaces: [ { id: nic.id } ]
    }
  }
}

// Grant VM MI Secrets User on the vault
resource kvRoleVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, vm.id, role_KV_SecretsUser)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role_KV_SecretsUser)
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output fqdn          string = '${dnsLabel}.${location}.cloudapp.azure.com'
output messagingUrl  string = 'https://${dnsLabel}.${location}.cloudapp.azure.com/api/messages'
output keyVaultName  string = kvName
output vmPrincipalId string = vm.identity.principalId
output sshCommand    string = 'ssh ${adminUsername}@${dnsLabel}.${location}.cloudapp.azure.com'
