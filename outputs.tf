/*
  Identidad del cliente que ejecuta Terraform.
  Útil para confirmar la suscripción en uso.
*/
data "azurerm_client_config" "current" {}

output "subscription_id" {
  description = "Subscription ID usado por azurerm"
  value       = data.azurerm_client_config.current.subscription_id
}

output "resource_group" {
  description = "Nombre del Resource Group creado"
  value       = azurerm_resource_group.rg.name
}

output "aks_name" {
  description = "Nombre del cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "k8s_version" {
  description = "Versión efectiva de Kubernetes desplegada"
  value       = azurerm_kubernetes_cluster.aks.kubernetes_version
}

/*
  Kubeconfig de usuario (no admin).
  Puedes escribirlo a un archivo y usarlo con kubectl sin 'az aks get-credentials'.
*/
output "kube_config_raw" {
  description = "Kubeconfig de usuario para kubectl"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

/*
  Si prefieres admin kubeconfig, descomenta este bloque:

output "kube_admin_config_raw" {
  description = "Kubeconfig admin para kubectl"
  value       = azurerm_kubernetes_cluster.aks.kube_admin_config_raw
  sensitive   = true
}
*/

