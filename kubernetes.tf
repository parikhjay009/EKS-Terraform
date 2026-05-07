data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# ------------------------------------------------------------------------------
# APPLICATION DEPLOYMENT
# ------------------------------------------------------------------------------
resource "kubernetes_namespace" "app" {
  metadata {
    name = "hello-world"
  }
  depends_on = [module.eks]
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "hello-world"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }

      spec {
        container {
          image = "hashicorp/http-echo"
          name  = "hello-world"
          args  = ["-text=hello world"]

          port {
            container_port = 5678
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "hello-world-svc"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    selector = {
      app = "hello-world"
    }

    port {
      port        = 80
      target_port = 5678
    }

    type = "ClusterIP"
  }
}

# ------------------------------------------------------------------------------
# INGRESS (PUBLIC EXPOSURE VIA ALB)
# ------------------------------------------------------------------------------
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "hello-world-ingress"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
