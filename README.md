# AKS on Azure with Terraform – End‑to‑End Guide (100% `ARM_*`, no scripts)

This README walks you from **zero to a working AKS cluster** using **Terraform only** (no shell wrappers, no `--sdk-auth`). It assumes you’ll authenticate with a **Service Principal** via `ARM_*` environment variables.

> Short on time? Follow the **Quick Start**. Need context? Read **Concepts** and **Troubleshooting**.

---

## 0) Prerequisites

- **Azure Subscription**: You already created an **Enabled** subscription in the Azure Portal.
- **Access**: Your user (or admin) can assign roles at the subscription scope.
- **Tools**:
  - Azure CLI ≥ 2.44 (recommended)
  - Terraform ≥ 1.8.0
  - `kubectl` (optional for validation)

> Tip: If the CLI ever “doesn’t see” the new subscription, `az logout && az login` usually fixes cache/tenant drift.


## 1) Create/Locate the Subscription (Portal – recommended)

1. Azure Portal → **Cost Management + Billing** → ensure you know the **Billing Profile** and **Invoice Section**.
2. Azure Portal → **Subscriptions** → **+ Add** → create the subscription (Production or Dev/Test).
3. After creation, confirm the subscription is **Enabled** and note its **Subscription ID**.
4. (Optional but recommended) In the subscription → **Resource providers**, register:
   - `Microsoft.ContainerService`
   - `Microsoft.Network`
   - (Optional) `Microsoft.OperationalInsights`

> You can also create subscriptions via CLI/API, but the Portal avoids `billingScope` pitfalls.


## 2) Create a Service Principal (SP) and Assign Roles

You can do this via **Portal** or **CLI**.

### 2.1 Portal (Entra ID)
- **Microsoft Entra ID** → **App registrations** → **New registration** → Name: `tf-aks`
- Copy **Application (client) ID** (this will be `ARM_CLIENT_ID`).
- **Certificates & secrets** → **New client secret** → copy **Value** (this will be `ARM_CLIENT_SECRET`).
- **Subscriptions** → your subscription → **Access control (IAM)** → **Add role assignment**:
  - Role: **Contributor** (minimum) and, if you’ll assign roles via Terraform later, also **User Access Administrator**.
  - Member: the **App** you just created.

### 2.2 CLI (Alternative)
```bash
SUB_ID="<YOUR_SUBSCRIPTION_ID>"
SP_NAME="tf-aks-$(date +%Y%m%d%H%M%S)"

az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUB_ID" \
  --years 1 -o jsonc
```
From the output:
- `appId`    → `ARM_CLIENT_ID`
- `password` → `ARM_CLIENT_SECRET`
- `tenant`   → `ARM_TENANT_ID`

> If role assignment fails here, assign from the Portal as shown above.


## 3) Export `ARM_*` Environment Variables

Required for the Terraform AzureRM provider (no `--sdk-auth`):

```bash
export ARM_TENANT_ID="<Directory (tenant) ID>"
export ARM_CLIENT_ID="<Application (client) ID>"
export ARM_CLIENT_SECRET="<Client secret VALUE>"
export ARM_SUBSCRIPTION_ID="<Subscription ID>"
```

Validate:
```bash
env | grep ARM_ | sort
```


## 4) Terraform Project Layout

Create a new folder, e.g. `aks-tf/`:

```
aks-tf/
├─ versions.tf
├─ providers.tf
├─ variables.tf
├─ main.tf
├─ outputs.tf
└─ terraform.tfvars
```

### 4.1 `versions.tf`
```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }
  }
}
```

### 4.2 `providers.tf`
```hcl
provider "azurerm" {
  features {}

  /*
    Authentication via environment variables:
      ARM_TENANT_ID
      ARM_CLIENT_ID
      ARM_CLIENT_SECRET
      ARM_SUBSCRIPTION_ID
  */
}
```

### 4.3 `variables.tf`
```hcl
variable "location" {
  description = "Azure region (e.g., eastus, brazilsouth, westeurope)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group."
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name (also used as DNS prefix)."
  type        = string
}

variable "kubernetes_version" {
  description = "Exact Kubernetes version (e.g., 1.30.6). If empty, the latest stable patch of the minor prefix is used."
  type        = string
  default     = ""
}

variable "kubernetes_minor_prefix" {
  description = "Minor prefix (e.g., 1.30). Only used when kubernetes_version == \"\"."
  type        = string
  default     = "1.30"
}

variable "node_size" {
  description = "VM size (e.g., Standard_D2s_v4, Standard_D2s_v3, Standard_B4ms)."
  type        = string
}

variable "node_count" {
  description = "Number of nodes for the default pool."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Common tags for resources."
  type        = map(string)
  default = {
    project = "aks-demo"
    env     = "lab"
    owner   = "julio"
  }
}
```

### 4.4 `main.tf`
```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_kubernetes_service_versions" "available" {
  location        = var.location
  include_preview = false
  version_prefix  = var.kubernetes_minor_prefix
}

locals {
  effective_k8s_version = (
    var.kubernetes_version != ""
      ? var.kubernetes_version
      : data.azurerm_kubernetes_service_versions.available.latest_version
  )
}

resource "time_sleep" "after_rg" {
  create_duration = "15s"
  depends_on      = [azurerm_resource_group.rg]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.cluster_name}-dns"

  kubernetes_version  = local.effective_k8s_version

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  default_node_pool {
    name        = "sysnp"
    vm_size     = var.node_size
    node_count  = var.node_count
    os_sku      = "AzureLinux"  # Azure Linux (AL2023). Consider AzureLinux3 for new pools in future.
    upgrade_settings {
      max_surge = "33%"
    }
    only_critical_addons_enabled = true
  }

  oidc_issuer_enabled = true
  sku_tier            = "Free"
  tags                = var.tags

  depends_on = [time_sleep.after_rg]
}
```

### 4.5 `outputs.tf`
```hcl
data "azurerm_client_config" "current" {}

output "subscription_id" {
  description = "Subscription ID used by provider."
  value       = data.azurerm_client_config.current.subscription_id
}

output "resource_group" {
  description = "Resource Group name."
  value       = azurerm_resource_group.rg.name
}

output "aks_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "k8s_version" {
  description = "Effective Kubernetes version."
  value       = azurerm_kubernetes_cluster.aks.kubernetes_version
}

output "kube_config_raw" {
  description = "User kubeconfig for kubectl."
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}
```

### 4.6 `terraform.tfvars` (example)
```hcl
location            = "eastus"          # or eastus2 / westeurope / brazilsouth ...

resource_group_name = "aks-rg-demo"
cluster_name        = "aks-demo"

# Option A: leave empty to use the latest stable patch of the minor below
kubernetes_version       = ""

# Option B: define minor prefix
kubernetes_minor_prefix  = "1.30"

# IMPORTANT: choose an allowed size for your subscription/region:
#   Standard_D2s_v4, Standard_D2s_v3, or Standard_B4ms (for labs) are widely available.
node_size   = "Standard_D2s_v4"
node_count  = 3

tags = {
  project = "aks-demo"
  env     = "lab"
  owner   = "julio"
}
```


## 5) Initialize, Plan, Apply

```bash
terraform init -upgrade
terraform validate
terraform plan -out tfplan
terraform apply -auto-approve tfplan
```

Provisioning notes:
- New subscriptions may have **eventual consistency**; the small `time_sleep` helps.
- If you see **SKU not allowed** or **quota** errors, pick an allowed `node_size` or another region; or request quota increases.


## 6) Use `kubectl` without Azure CLI

```bash
terraform output -raw kube_config_raw > kubeconfig
export KUBECONFIG="$PWD/kubeconfig"

kubectl cluster-info
kubectl get nodes -o wide
```

> Prefer **exact version pinning** (`kubernetes_version = "1.30.x"`) for production to avoid drift on future plans.


## 7) Verify Regions (where did resources land?)

**Portal**:
- Search `aks-demo` (Kubernetes services) → **Overview** → **Region**
- `aks-rg-demo` (Resource group) → **Overview** → **Location**
- `Kubernetes services → aks-demo → Properties` → **Node resource group**

**CLI**:
```bash
az group show -n aks-rg-demo --query location -o tsv
az aks show -g aks-rg-demo -n aks-demo --query location -o tsv
az resource list -g aks-rg-demo -o table
NRG=$(az aks show -g aks-rg-demo -n aks-demo --query nodeResourceGroup -o tsv); echo $NRG
az group show -n "$NRG" --query location -o tsv
```


## 8) Common Issues & Fixes

- **OIDCIssuerUnsupportedK8sVersion**  
  Ensure `kubernetes_version >= 1.21` (recommend 1.28+). Pin a valid patch available in your region.

- **VM size not allowed in region**  
  Choose `node_size` from the **allowed list** or switch region. Typical safe picks: `Standard_D2s_v4`, `Standard_D2s_v3`, `Standard_B4ms` (lab).

- **Subscription not visible in CLI**  
  `az logout && az login` (ensure correct tenant). Confirm RBAC (Contributor/Owner) on the new subscription.

- **Provider not registered**  
  Once per subscription, register `Microsoft.ContainerService` and `Microsoft.Network` in Portal, or:
  ```bash
  az provider register --namespace Microsoft.Network --wait
  az provider register --namespace Microsoft.ContainerService --wait
  ```

- **Kubeconfig handling**  
  The output is **sensitive**. Protect the file and avoid committing it.


## 9) Next Steps (Optional)

- **Workload node pool**: Create a separate `azurerm_kubernetes_cluster_node_pool` for apps and keep `sysnp` for critical add-ons.
- **Workload Identity**: With `oidc_issuer_enabled = true`, configure federated credentials per workload (`azurerm_federated_identity_credential`).
- **Observability**: Add Log Analytics workspace and Container Insights in Terraform.
- **Budgets/Alerts**: Define budgets at subscription or resource group scope for FinOps.
- **Upgrades**: For production, pin exact versions and plan controlled upgrades (surge, surge pools).


## 10) Clean Up

To destroy all resources created by this project (AKS and RG):
```bash
terraform destroy -auto-approve
```

> Warning: This deletes the cluster and its node resource group as well.

---

**Author’s note:** This flow was curated for a frictionless “100% Terraform” experience with Azure AKS using `ARM_*` env vars, avoiding `--sdk-auth` and shell wrappers.
