provider "azurerm" {
  features {}

  /*
    Auth esperada por variables de entorno:

      ARM_TENANT_ID
      ARM_CLIENT_ID
      ARM_CLIENT_SECRET
      ARM_SUBSCRIPTION_ID

    No usamos --sdk-auth.
  */
}

