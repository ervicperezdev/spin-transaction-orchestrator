# La identidad administradora de plataforma crea el namespace antes del CI.
# El rol de despliegue solo necesita permisos dentro de este namespace.
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
