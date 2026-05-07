output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "kubectl_config_command" {
  description = "Command to configure kubectl to access the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "test_app_command" {
  description = "Command to test the internal service via port-forwarding"
  value       = "kubectl port-forward svc/hello-world-svc -n hello-world 8080:80"
}

output "public_app_url" {
  description = "The public URL to access the application via ALB"
  value       = try("http://${kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname}", "ALB is provisioning. Run `kubectl get ingress -n hello-world` to get the URL.")
}
