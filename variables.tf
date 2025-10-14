variable "location" {
  description = <<-EOT
    Región de Azure (por ejemplo: eastus, brazilsouth, westeurope).
  EOT
  type = string
}

variable "resource_group_name" {
  description = <<-EOT
    Nombre del Resource Group donde se creará el cluster.
  EOT
  type = string
}

variable "cluster_name" {
  description = <<-EOT
    Nombre del AKS (se usa también como prefijo DNS).
  EOT
  type = string
}

variable "kubernetes_version" {
  description = <<-EOT
    Versión exacta de Kubernetes (por ejemplo: 1.30.6).
    Si se deja en cadena vacía (""), se usará la última versión estable
    disponible en la región que coincida con el "minor prefix" indicado.
  EOT
  type    = string
  default = ""
}

variable "kubernetes_minor_prefix" {
  description = <<-EOT
    Prefijo de versión "minor" para seleccionar el último patch estable
    en la región (por ejemplo: "1.30").
    Solo se usa cuando kubernetes_version == "".
  EOT
  type    = string
  default = "1.30"
}

variable "node_size" {
  description = <<-EOT
    SKU/size de VM para el node pool (por ejemplo: Standard_D2s_v5).
  EOT
  type = string
}

variable "node_count" {
  description = <<-EOT
    Cantidad de nodos del node pool por defecto.
  EOT
  type    = number
  default = 3
}

variable "tags" {
  description = <<-EOT
    Mapa de etiquetas para todos los recursos.
  EOT
  type = map(string)

  default = {
    project = "aks-demo"
    env     = "lab"
    owner   = "julio"
  }
}

