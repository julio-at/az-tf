/*
  Resource Group
*/
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

/*
  Descubrimiento de versiones AKS en la región,
  filtrado por el "minor" deseado.
*/
data "azurerm_kubernetes_service_versions" "available" {
  location        = var.location
  include_preview = false
  version_prefix  = var.kubernetes_minor_prefix
}

/*
  Resolución de versión efectiva:
  - Si kubernetes_version != "" => usar esa.
  - En caso contrario, usar la última versión estable para el minor indicado.
*/
locals {
  effective_k8s_version = (
    var.kubernetes_version != ""
      ? var.kubernetes_version
      : data.azurerm_kubernetes_service_versions.available.latest_version
  )
}

/*
  Pequeño colchón de consistencia después de crear el RG.
  Evita carreras con el registro de proveedores en suscripciones nuevas.
*/
resource "time_sleep" "after_rg" {
  create_duration = "15s"

  depends_on = [
    azurerm_resource_group.rg
  ]
}

/*
  AKS con:
    - Identidad administrada (SystemAssigned)
    - RBAC nativo habilitado
    - Azure CNI Overlay (sencillo para IPAM)
    - Node pool "solo add-ons críticos"
    - Azure Linux como OS para nodos
    - OIDC issuer (para Workload Identity)
*/
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.cluster_name}-dns"

  kubernetes_version = local.effective_k8s_version

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  network_profile {
    network_plugin       = "azure"
    network_plugin_mode  = "overlay"
    load_balancer_sku    = "standard"
    outbound_type        = "loadBalancer"
  }

  default_node_pool {
    name       = "sysnp"
    vm_size    = var.node_size
    node_count = var.node_count

    /*
      Azure Linux (AL2023).
      Si en el futuro decides mover a AzureLinux3,
      bastará con cambiar el valor aquí.
    */
    os_sku = "AzureLinux"

    upgrade_settings {
      max_surge = "33%"
    }

    /*
      Mantiene este pool como "sistema".
      Luego puedes crear otro pool para workloads.
    */
    only_critical_addons_enabled = true
  }

  /*
    Recomendado para Workload Identity (reemplazo de AAD Pod Identity).
  */
  oidc_issuer_enabled = true

  /*
    Tier de control plane (Free / Paid).
    Free es suficiente para la mayoría de labs y demos.
  */
  sku_tier = "Free"

  tags = var.tags

  depends_on = [
    time_sleep.after_rg
  ]
}

