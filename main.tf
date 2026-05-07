data "aws_availability_zones" "available" {}

locals {
  name     = var.cluster_name
  vpc_cidr = var.vpc_cidr
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}

# ------------------------------------------------------------------------------
# VPC MODULE
# ------------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ------------------------------------------------------------------------------
# EKS CLUSTER MODULE
# ------------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = "1.35"

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  #cluster_endpoint_public_access_cidrs = ["<IP OF MY LAPTOP OR GITHUB ACTIONS>/32"]

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["t3.micro"]

    iam_role_additional_policies = {
      CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
  }

  eks_managed_node_groups = {
    main = {
      min_size     = 3
      max_size     = 3
      desired_size = 3
    }
  }

  enable_cluster_creator_admin_permissions = true
  cluster_enabled_log_types                = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # ----------------------------------------------------------------------------
  # ADDITIONAL SECURITY GROUPS / RULES
  # ----------------------------------------------------------------------------
  # Explicitly allow internal VPC traffic to the nodes for internal tooling
  node_security_group_additional_rules = {
    ingress_vpc_internal = {
      description = "Allow all internal VPC traffic to nodes"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [local.vpc_cidr]
    }
  }

  # Explicitly allow VPC traffic to hit the EKS control plane API
  cluster_security_group_additional_rules = {
    ingress_vpc_internal = {
      description = "Allow internal VPC traffic to control plane API"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [local.vpc_cidr]
    }
  }
}

