# Based on https://kennybrast.medium.com/deploying-an-aws-eks-cluster-with-self-managed-nodes-using-terraform-077a43764dc0
#
# Cluster role - Control nodes

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.eksclustername}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
	Action = [
	  "sts:AssumeRole",
	  "sts:TagSession"
	]
        Effect = "Allow"
        Principal = {
	  Service = "eks.amazonaws.com"
	}
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# Create cluster - Control nodes

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eksclustername
  role_arn = aws_iam_role.eks_cluster_role.arn 
  version = var.eksclusterversion
  vpc_config {
    subnet_ids = [for k, v in  var.svcsubnetids: "${v}"]
    endpoint_private_access = true
    endpoint_public_access  = true
  }
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  bootstrap_self_managed_addons = false
  tags = var.tags

/*  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${self.name} --region ${var.region}"
  }
*/
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

/*
### OIDC config
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
  url             = aws_eks_cluster.eks_cluster.identity.0.oidc.0.issuer
}
*/

resource "aws_eks_access_entry" "this" {
  cluster_name      = var.eksclustername
  principal_arn     = aws_iam_role.eks_node_role.arn
  #kubernetes_groups = ["system:bootstrappers","system:nodes"]  # not valid groups, valid for aws-auth configmap
  type              = "EC2_LINUX"
  depends_on = [ aws_eks_cluster.eks_cluster ]
}

/* # Policy can not be associated when type(above) is EC2_LINUX
resource "aws_eks_access_policy_association" "this" {
  cluster_name  = var.eksclustername
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_iam_role.eks_node_role.arn

  access_scope {
    type       = "cluster"
  }
  depends_on = [ aws_eks_cluster.eks_cluster ]
}
*/
/*
resource null_resource "awsnodeout" {
  provisioner "local-exec" {
    command = "kubectl delete daemonset -n kube-system --ignore-not-found=true aws-node "
  }
  depends_on = [aws_eks_cluster.eks_cluster]
}
resource null_resource "calicooperatorin" {
  provisioner "local-exec" {
    command = "kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/tigera-operator.yaml"
  }
  depends_on = [null_resource.awsnodeout]
}
resource null_resource "calicoconfigin" {
  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../k8s/calico/calicoconfig.yaml"
  }
  depends_on = [null_resource.calicooperatorin]
}
*/
  

###
# Worker nodes
####

# Node group role
resource "aws_iam_role" "eks_node_role" {
  name = "${var.eksclustername}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
	Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}


resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_instance_profile" "node_profile" {
  name = "node_profile"
  role = aws_iam_role.eks_node_role.name
}

# For ISE Sectool registration 
resource "aws_iam_policy" "eksnodesssmpolicy" {
  name = "eksnodesssmpolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:iam::752281881774:role/ise-sectool-registration-role",
          "arn:aws:iam::752281881774:role/production_elk_logstash"
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_ise_sectools_policy" {
  policy_arn = aws_iam_policy.eksnodesssmpolicy.arn
  role       = aws_iam_role.eks_node_role.name
}

# Launch template in launchtemplate.tf


# Node Group
resource "aws_eks_node_group" "eksnodegroupa" {
  # Change count to 1 after helm cilium has been installed
  count = var.ciliuminstalled ? 1 : 0 
  cluster_name    = "${var.eksclustername}"
  node_group_name = "${var.eksclustername}-nodes-a"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [var.svcsubnetids.az2]
  #version = aws_eks_cluster.eks_cluster.version
  
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    #version = "$Latest"
    version = aws_launch_template.eks_nodes.latest_version
  }
  scaling_config {
    desired_size = 2
    max_size     = 6
    min_size     = 2
  }
/*
  // Not required when addons are not present
  taint {
    key = "node.cilium.io/agent-not-ready"
    value = "true"
    effect = "NO_EXECUTE"
  }
*/
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
    aws_eks_cluster.eks_cluster 
  ]
}

# Security groups


resource "aws_security_group" "ingressnodessh" {
  name = "ingressnodessh"
  vpc_id = data.aws_vpc.vpc.id
  ingress {
    description = "In to node"     
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Out from node"     
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ingress_node_ssh"
    //karpenter.sh/discovery = "cnxscert-karpenter"
  }
}

resource "aws_eks_access_entry" "clusteradmins" {
  for_each = var.adminuser
  cluster_name      = aws_eks_cluster.eks_cluster.name
  principal_arn     = "arn:aws:iam::${var.awsaccountid}:user/${each.value}"
  //kubernetes_groups = ["group-1", "group-2"]
  type              = "STANDARD"
  depends_on = [ aws_eks_cluster.eks_cluster ]
}

/*
resource "aws_security_group" "ingressnodessh" {
  name = "ingressnodessh"
  vpc_id = data.aws_vpc.vpc.id  
  // Let SSH incoming
  ingress {
    description = "Security Group for letting in SSH to worker node"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.56.0.0/16"] 
  }
  
  ingress {
    description = "Allow calico udp"
    from_port = 4789
    to_port = 4789
    protocol = "udp"
    cidr_blocks = ["10.56.0.0/16"]
  }
  ingress {
    description = "Allow calico tcp"
    from_port = 5473
    to_port = 5473
    protocol = "tcp"
    cidr_blocks = ["10.56.0.0/16"]
  }
  ingress {
    from_port = 0
    to_port =0
    protocol = -1
    self = true
  }
  egress {
    description = "Out from node"     
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ingress_node_ssh"
    //karpenter.sh/discovery = "cnxscert-karpenter"
  }
  
}
*/

# Auto Scaling Group
/*
resource "aws_autoscaling_group" "eks_nodes" {
  name                = "${var.eksclustername}-nodes"
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2
  target_group_arns   = []
  vpc_zone_identifier = [var.svcsubnetids.az2]

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.eksclustername}"
    value               = "owned"
    propagate_at_launch = true
  }
}
*/

