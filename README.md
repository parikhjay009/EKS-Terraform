# AWS EKS Private Cluster Deployment

This Terraform project provisions an AWS EKS cluster, its foundational networking (VPC, Subnets), and a sample containerized "hello-world" application. It implements basic observability via AWS CloudWatch.

## Key Design Decisions

1. **Private Subnets & NAT Gateway (The "No Internet Gateway" Requirement)**
   * **Networking Approach:** The requirement specified that the cluster should not be publicly exposed, have no internet gateway, but still pull from public repos. 
   * **Implementation:** The EKS nodes and the workload are deployed *exclusively* in private subnets. These subnets do not have a direct route to an Internet Gateway (IGW). To satisfy the need to pull images from public repositories (like Docker Hub), a NAT Gateway is provisioned in an isolated public subnet. This ensures the cluster remains entirely inaccessible from the internet while maintaining the outbound egress required for pulling public images. (Note: If strict compliance requires absolutely zero IGWs in the VPC, one would need to use VPC Endpoints combined with ECR Pull-Through Caches, which limits pulling to pre-configured registries).
   
2. **Public App Exposure (via ALB):**
   * While the worker nodes and the EKS control plane remain strictly private, the "hello-world" application itself is exposed securely to the internet. This is achieved by deploying the AWS Load Balancer Controller and creating a Kubernetes `Ingress` resource. Traffic hits the public-facing Application Load Balancer (ALB) in the public subnet and is routed securely to the pods running in the private subnets.
   
3. **Security Enhancements:**
   * **API Endpoint Restrictions:** The `cluster_endpoint_public_access_cidrs` variable is exposed in `main.tf` to restrict access to the EKS control plane API to specific IP addresses.
   * **Additional Security Groups:** Custom ingress rules are added to both the cluster and node security groups to explicitly allow internal VPC communication.

4. **Observability:**
   * **Control Plane:** EKS control plane logging is enabled for all key components (API, audit, authenticator, controllerManager, scheduler).
   * **Data Plane (Nodes/Pods):** *(Removed for Free Tier Compliance)* Initially, the `amazon-cloudwatch-observability` EKS Add-on was planned. However, the CloudWatch daemon requires more memory than a free-tier eligible `t3.micro` instance provides when running alongside other EKS system pods. It was removed to prevent Out-Of-Memory (OOM) crashes and allow the workload to stay entirely within the AWS Free Tier constraints.

## Prerequisites
- **Terraform** (v1.7.0+)
- **S3 Bucket** (for remote state and native state locking). You must update `providers.tf` with your specific bucket name before initializing.
- **AWS CLI** (configured with appropriate credentials)
- **kubectl**

## Deployment Instructions

### 1. Initialize Terraform
Run the following command to download the required providers and modules:
```bash
terraform init
```

### 2. Plan and Apply the Infrastructure
Execute the plan and apply phases to build the VPC, EKS Cluster, and the application. This process typically takes **15-20 minutes**.
```bash
terraform apply -auto-approve
```

### 3. Connect to the Cluster
Once the apply is complete, update your local `kubeconfig` to communicate with the new cluster:
```bash
$(terraform output -raw kubectl_config_command)
```

### 4. Verify the Deployment
Ensure the nodes are ready and the "hello-world" pods are running:
```bash
kubectl get nodes
kubectl get pods -n hello-world
```

### 5. Access the Application
The application is now exposed to the internet via an AWS Application Load Balancer!

You can find the URL in the Terraform outputs:
```bash
terraform output -raw public_app_url
```
If the output says it's provisioning, you can manually check the address via:
```bash
kubectl get ingress -n hello-world
```
Open the provided URL in your browser to see the NGINX Hello World page.
*(Note: It can take 2-3 minutes for the ALB to provision and register targets before it responds successfully).*

### 6. Clean Up
To destroy all resources and avoid incurring future charges:
```bash
terraform destroy -auto-approve
```

---

## Follow-Up Questions

### 1. How would you expose this application to the internet without a public EKS endpoint?
**Answer:** The "public EKS endpoint" refers to the Kubernetes API server (`cluster_endpoint_public_access`). We can securely set this to `false` (meaning no one on the internet can run `kubectl` against our cluster), while still exposing the actual "hello-world" application to the public internet.
This is achieved by using an **AWS Application Load Balancer (ALB)**. We deploy the AWS Load Balancer Controller inside the cluster, which watches for `Ingress` resources. When we create an Ingress with the `internet-facing` annotation, it provisions an ALB in the **Public Subnets**. The public traffic hits the ALB, and the ALB securely routes the traffic downstream into our pods running safely in the **Private Subnets**.

### 2. Justify any security decisions or tradeoffs you made during this design.
**Answer:**
1. **Private Node Isolation:** Worker nodes are placed entirely in private subnets. This ensures they have no direct internet routes, making them immune to external port-scanning or direct SSH brute-force attacks.
2. **ALB Edge Security:** By exposing the app via an ALB rather than a direct NodePort, we terminate the public connection at the AWS edge. This allows us to easily attach an AWS WAF (Web Application Firewall) or AWS Shield to protect against SQL injections, XSS, and DDoS attacks before traffic ever reaches the cluster.
3. **Tradeoff - NAT Gateway Costs:** To pull public images (like the NGINX image) while keeping the nodes in private subnets, we had to provision a NAT Gateway in the public subnet. While this ensures outbound-only internet access, it introduces a permanent cost overhead (~$32/month).
4. **Tradeoff - TLS Termination:** In this design, TLS would be terminated at the ALB using AWS Certificate Manager. While convenient and performant, traffic inside the VPC between the ALB and the Pods is unencrypted HTTP. In highly regulated environments (e.g., HIPAA), we would have to accept the operational tradeoff of managing internal certificates for "End-to-End Encryption."
