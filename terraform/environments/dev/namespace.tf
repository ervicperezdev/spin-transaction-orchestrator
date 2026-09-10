# El plan de PR refresca este recurso con la EKS View access entry; el apply
# sigue siendo la única identidad que puede modificar el namespace.
resource "kubernetes_namespace_v1" "application" {
  metadata {
    name = var.application_namespace
    labels = {
      "app.kubernetes.io/part-of"    = var.project
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Esperar a la creación del clúster y de su acceso administrador.
  depends_on = [module.eks]
}
