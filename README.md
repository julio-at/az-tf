# AKS on Azure with Terraform — Clone & Run

This repository lets you deploy an **AKS cluster** on Azure using **Terraform only** (no shell scripts, no `--sdk-auth`). You’ll authenticate with a **Service Principal** via `ARM_*` environment variables.

> TL;DR: **Clone → set `ARM_*` → edit `terraform.tfvars` → `terraform init/plan/apply` → `kubectl get nodes`.


## 1) Clone this repo

```bash
git clone https://github.com/julio-at/az-tf.git 
cd az-tf
```

> The project expects a standard Terraform layout and no one-liners in `.tf` files for readability.


## 2) Repository layout

```
az-tf/
├─ versions.tf
├─ providers.tf
├─ variables.tf
├─ main.tf
├─ outputs.tf
└─ terraform.tfvars
```

- `versions.tf` — pins Terraform & providers.
- `providers.tf` — AzureRM provider using `ARM_*` env vars.
- `variables.tf` — inputs for region, names, versions, VM size, etc.
- `main.tf` — RG + AKS (Managed Identity, RBAC, Azure CNI Overlay, OIDC issuer).
- `outputs.tf` — helpful outputs including kubeconfig (user).
- `terraform.tfvars` — your real values (edit this).


## 3) Prerequisites

- **Azure Subscription**: must be **Enabled**. If you just created it, allow a few minutes for provider registration.
- **Access**: your user/admin can assign roles on the subscription.
- **Tools**:
  - Azure CLI ≥ 2.44 (for validations and optional provider registration)
  - Terraform ≥ 1.8.0
  - `kubectl` (optional, for validation)


## 4) Create/Use a Service Principal (SP)

### Option A — Azure Portal
1. **Microsoft Entra ID** → **App registrations** → **New registration** → Name `tf-aks`.
2. Copy **Application (client) ID**.
3. **Certificates & secrets** → **New client secret** → copy the **Value**.
4. **Subscriptions** → your subscription → **Access control (IAM)** → **Add role assignment**:
   - Role: **Contributor** (and optionally **User Access Administrator** if you’ll assign RBAC with TF).
   - Member: the App you just created.

### Option B — Azure CLI
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


## 5) Export `ARM_*` environment variables

```bash
export ARM_TENANT_ID="<Directory (tenant) ID>"
export ARM_CLIENT_ID="<Application (client) ID>"
export ARM_CLIENT_SECRET="<Client secret VALUE>"
export ARM_SUBSCRIPTION_ID="<Subscription ID>"
```

Quick check:
```bash
env | grep ARM_ | sort
```


## 6) Edit `terraform.tfvars`

Set region, names, version policy, and node size. Example (adjust to your case):

```hcl
location            = "eastus"          # e.g., eastus / eastus2 / westeurope / brazilsouth
resource_group_name = "aks-rg-demo"
cluster_name        = "aks-demo"

# Option A: keep empty to use latest stable patch of the minor prefix
kubernetes_version       = ""
# Option B: define minor prefix (used only when kubernetes_version == "")
kubernetes_minor_prefix  = "1.30"

# IMPORTANT: choose a size allowed in your subscription/region:
# e.g., Standard_D2s_v4 or Standard_D2s_v3 are broadly available; Standard_B4ms for labs.
node_size  = "Standard_D2s_v4"
node_count = 3

tags = {
  project = "aks-demo"
  env     = "lab"
  owner   = "julio"
}
```

> If you need exact version pinning for production, set `kubernetes_version = "1.30.x"` and ignore the minor prefix.


## 7) Initialize, plan, and apply

```bash
terraform init -upgrade
terraform validate
terraform plan -out tfplan
terraform apply -auto-approve tfplan
```

Provisioning notes:
- New subscriptions may need provider registration; see Troubleshooting.
- If a VM size is not allowed in your region, switch to a listed size or a different region.


## 8) Use `kubectl` (without Azure CLI)

```bash
terraform output -raw kube_config_raw > kubeconfig
export KUBECONFIG="$PWD/kubeconfig"

kubectl cluster-info
kubectl get nodes -o wide
```

> The kubeconfig output is **sensitive** — keep it private.


## 9) How to see the deployed regions

**Portal**
- Search `aks-demo` → **Overview** → **Region**
- Open resource group `aks-rg-demo` → **Overview** → **Location**
- `Kubernetes services → aks-demo → Properties` → **Node resource group**

**CLI**
```bash
az group show -n aks-rg-demo --query location -o tsv
az aks show  -g aks-rg-demo -n aks-demo --query location -o tsv
az resource list -g aks-rg-demo -o table
NRG=$(az aks show -g aks-rg-demo -n aks-demo --query nodeResourceGroup -o tsv); echo $NRG
az group show -n "$NRG" --query location -o tsv
```


## 10) Troubleshooting (quick)

- **Subscription not visible in CLI**  
  `az logout && az login` (ensure correct tenant). Confirm you have **Contributor/Owner** on the subscription.

- **Provider not registered**  
  In Portal → Subscription → **Resource providers** → register
  - `Microsoft.ContainerService`, `Microsoft.Network`  
  Or via CLI:
  ```bash
  az provider register --namespace Microsoft.Network --wait
  az provider register --namespace Microsoft.ContainerService --wait
  ```

- **VM size not allowed / quota**  
  Choose a size from the error’s allow-list (e.g., `Standard_D2s_v4`, `Standard_D2s_v3`) or switch region. Review quotas:
  ```bash
  az vm list-usage -l <region> -o table
  ```

- **OIDC issuer requires >= 1.21**  
  Set `kubernetes_version` to a supported patch (recommend 1.28+; e.g., `1.30.x`).

- **Data source version mismatch**  
  If `kubernetes_version = ""` and the minor prefix isn’t available in your region, pick a valid minor or pin an exact patch.


## 11) Clean up

```bash
terraform destroy -auto-approve
```

> This deletes the AKS cluster and its node resource group.


## 12) Next steps (optional)

- Add a **workload node pool** (`azurerm_kubernetes_cluster_node_pool`) and keep `sysnp` for critical add-ons.
- Configure **Workload Identity** (OIDC) for workloads that need Azure APIs.
- Add **Log Analytics** / **Container Insights** and **Budgets/Alerts** — all via Terraform.
