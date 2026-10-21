locals {
  name_prefix = "${var.project}-${var.environment}"

  # Mandatory tags last so callers cannot override them
  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "networking"
    },
  )

  # NodePort range used by the ALB to reach worker nodes
  nodeport_from = 30000
  nodeport_to   = 32767
}

# -----------------------------------------------------------------------------
# VPC, subnets, Internet Gateway, route table
# All-public design: no NAT Gateway, no private subnets (see ADR-0001).
# Security groups below are the access-control perimeter.
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "public_subnet_cidrs and availability_zones must have the same length."
    }
    precondition {
      condition     = alltrue([for c in var.public_subnet_cidrs : cidrcontains(var.vpc_cidr, c)])
      error_message = "Every public subnet CIDR must be inside vpc_cidr."
    }
  }
}

# Lock down the default SG: no rules, so nothing can accidentally use it.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-default-sg"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = { for i, az in var.availability_zones : az => var.public_subnet_cidrs[i] }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  # Required: nodes and ALBs live here and need public IPs (no NAT)
  map_public_ip_on_launch = true # checkov:skip=CKV_AWS_130:All-public subnet design, see ADR-0001

  tags = merge(local.tags, {
    Name                                         = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })

}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Security groups (see technical-spec.md#security-groups)
# Groups are created empty and rules are attached as standalone resources so the
# groups can reference each other without dependency cycles.
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane - API access from worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker nodes - cluster, inter-node and ALB traffic"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL - reachable only from EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public ALB - HTTP/HTTPS from the internet"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# --- EKS cluster SG ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_api_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "API server (443) from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-cluster-api-from-nodes" })
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-cluster-all-out" })
}

# --- EKS node SG ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from EKS cluster SG"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-from-cluster" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication (self)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-self" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet API (10250) from EKS cluster SG"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-kubelet" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort range from ALB SG"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.nodeport_from
  to_port                      = local.nodeport_to

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-nodeport-from-alb" })
}

# The ALB egress rule for health checks (8080) is only useful if nodes accept it.
resource "aws_vpc_security_group_ingress_rule" "eks_node_health_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "ALB health checks / target traffic (8080) from ALB SG"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-health-from-alb" })
}

resource "aws_vpc_security_group_egress_rule" "eks_node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (ECR, S3, Secrets Manager via IGW)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-all-out" })
}

# --- RDS SG -----------------------------------------------------------------
# Ingress only from EKS nodes. No egress rules: RDS never initiates connections.

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL (3306) from EKS node SG only"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-mysql-from-nodes" })
}

# --- ALB SG -----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-http" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-https" })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodeports" {
  security_group_id            = aws_security_group.alb.id
  description                  = "NodePort range to EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = local.nodeport_from
  to_port                      = local.nodeport_to

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-to-nodeports" })
}

resource "aws_vpc_security_group_egress_rule" "alb_health_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks (8080) to EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-health-to-nodes" })
}
