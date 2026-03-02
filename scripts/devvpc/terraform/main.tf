data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }
}

data "aws_subnet" "subnet" {
  for_each = toset(data.aws_subnets.subnets.ids)
  id       = each.value
}

data "aws_route53_zone" "public_zone" {
  name         = "conexus-dev-sandbox.org"
  private_zone = false
}

data "aws_instances" "ingress_nodes" {
  filter {
    name   = "tag:ingress"
    values = ["true"]
  }
  filter { # keep only running nodes
    name   = "instance-state-name"
    values = ["running"]
  }
}

locals {
  ingress_node_ips = toset(data.aws_instances.ingress_nodes.private_ips)
}

########################################
# EXTERNAL NLB (Public)
########################################
resource "aws_lb" "extnlb" {
  name                             = "${var.vpc_name}-extnlb"
  subnets                          = [for k, v in var.extnlbsubnetids : "${v}"]
  internal                         = "false"
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = "true"
}

resource "aws_lb_target_group" "extnlb_tg_https" {
  name        = "${var.vpc_name}-extnlb-tg-https"
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "alb"

  health_check {
    protocol = "HTTPS"
    port     = "443"
  }
}

resource "aws_lb_target_group" "extnlb_tg_http" {
  name        = "${var.vpc_name}-extnlb-tg-http"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "alb"

  health_check {
    protocol = "HTTP"
    port     = "80"
  }
}

resource "aws_lb_listener" "extnlb_listener_https" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extnlb_tg_https.arn
  }
}

resource "aws_lb_listener" "extnlb_listener_http" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extnlb_tg_http.arn
  }
}

resource "aws_lb_target_group_attachment" "extnlb_ga_http_attachment" {
  target_group_arn = aws_lb_target_group.extnlb_tg_http.arn
  target_id        = aws_lb.alb_with_waf.arn
  port             = 80
}

resource "aws_lb_target_group_attachment" "extnlb_ga_https_attachment" {
  target_group_arn = aws_lb_target_group.extnlb_tg_https.arn
  target_id        = aws_lb.alb_with_waf.arn
  port             = 443
}

resource "aws_security_group_rule" "eks_nodes_ingress_alb_http" {
  description              = "Allow HTTP NodePort 30080 from ALB"
  security_group_id        = module.eks.node_security_group_id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 30080
  to_port                  = 30080
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "eks_nodes_ingress_alb_https" {
  description              = "Allow HTTPS NodePort 30443 from ALB"
  security_group_id        = module.eks.node_security_group_id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 30443
  to_port                  = 30443
  source_security_group_id = aws_security_group.alb_sg.id
}

/*
resource "aws_lb_target_group_attachment" "alb_to_nginx_node1" {
  target_group_arn = aws_lb_target_group.alb_to_nginx_tg.arn
  target_id        = "10.20.30.34" # First node IP
  port             = 30080         # Updated to HTTP NodePort
}

resource "aws_lb_target_group_attachment" "alb_to_nginx_node2" {
  target_group_arn = aws_lb_target_group.alb_to_nginx_tg.arn
  target_id        = "10.20.40.81" # Second node IP
  port             = 30080         # Updated to HTTP NodePort
}
*/
########################################
# ALB (With WAF)
########################################

resource "aws_security_group" "alb_sg" {
  name   = "${var.vpc_name}-alb-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.vpc_name}-alb-sg"
  }

}

resource "aws_lb" "alb_with_waf" {
  name               = "${var.vpc_name}-alb-with-waf"
  load_balancer_type = "application"
  subnets            = [for k, v in var.intnlbsubnetids : "${v}"] # If still using private subnets
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_wafv2_web_acl" "webacls" {
  name  = "${var.vpc_name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.vpc_name}-waf-metrics"
    sampled_requests_enabled   = true
  }

  # 1) All Traffic Rate Limit: 150 req/min => 750 per 5 min
  rule {
    name     = "RateLimitAllTraffic"
    priority = 1
    statement {
      rate_based_statement {
        limit              = 750
        aggregate_key_type = "IP"
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitAllTraffic"
      sampled_requests_enabled   = true
    }
  }

  # 2) Block oversized headers (> 8KB total)
  rule {
    name     = "BlockOversizedHeaders"
    priority = 2
    statement {
      size_constraint_statement {
        field_to_match {
          headers {
            match_scope       = "ALL"
            oversize_handling = "CONTINUE"
            match_pattern {
              all {}
            }
          }
        }
        comparison_operator = "GT"
        size                = 8192
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockOversizedHeaders"
      sampled_requests_enabled   = true
    }
  }

  # 3) Block oversized request bodies (> 20 MB)
  rule {
    name     = "BlockOversizedBody"
    priority = 3
    statement {
      size_constraint_statement {
        field_to_match {
          body {
            oversize_handling = "CONTINUE"
          }
        }
        comparison_operator = "GT"
        size                = 20971520
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockOversizedBody"
      sampled_requests_enabled   = true
    }
  }

  # 4) Block requests with a user-agent header containing "BadBot"
  rule {
    name     = "BlockBadBot"
    priority = 4
    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = "user-agent"
          }
        }
        positional_constraint = "CONTAINS"
        search_string         = "BadBot"
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockBadBot"
      sampled_requests_enabled   = true
    }
  }

  # 5) Block requests with oversized cookie header (> 4KB)
  rule {
    name     = "BlockHugeCookieHeader"
    priority = 5
    statement {
      size_constraint_statement {
        field_to_match {
          single_header {
            name = "cookie"
          }
        }
        comparison_operator = "GT"
        size                = 4096
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockHugeCookieHeader"
      sampled_requests_enabled   = true
    }
  }

  # 6) Block XSS (allow specific path prefix)
  rule {
    name     = "BlockXSS"
    priority = 6
    statement {
      and_statement {
        statement {
          xss_match_statement {
            field_to_match {
              body {
                oversize_handling = "CONTINUE"
              }
            }
            text_transformation {
              priority = 0
              type     = "HTML_ENTITY_DECODE"
            }
            text_transformation {
              priority = 1
              type     = "URL_DECODE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              byte_match_statement {
                field_to_match {
                  uri_path {}
                }
                search_string         = "/eas/conexus/"
                positional_constraint = "STARTS_WITH"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockXSS"
      sampled_requests_enabled   = true
    }
  }

  # 7) Block SQLi
  rule {
    name     = "BlockSQLi"
    priority = 7
    statement {
      sqli_match_statement {
        field_to_match {
          all_query_arguments {}
        }
        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }
        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }
    action {
      block {}
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockSQLi"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  resource_arn = aws_lb.alb_with_waf.arn
  web_acl_arn  = aws_wafv2_web_acl.webacls.arn
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.vpc_name}-app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    port                = "traffic-port"
    protocol            = "HTTP"
    path                = "/nginx-health"
  }
}

resource "random_string" "tg_suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "aws_lb_target_group" "alb_to_nginx_tg" {
  name        = "${var.vpc_name}-ngtg-${random_string.tg_suffix.result}"
  port        = 30443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    protocol            = "HTTPS"
    port                = "30443"
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  lifecycle {
    create_before_destroy = true
  }
}

# attach ALB to all EKS nodes via private IPs
resource "aws_lb_target_group_attachment" "alb_to_nginx_nodes" {
  for_each         = local.ingress_node_ips
  target_group_arn = aws_lb_target_group.alb_to_nginx_tg.arn
  target_id        = each.key # host IP
  port             = 30443
}

############################
# ACM certificate (auto-renew)
############################
resource "aws_acm_certificate" "sandbox" {
  domain_name = "conexus-dev-sandbox.org"
  subject_alternative_names = [
    "app.conexus-dev-sandbox.org",
    "argocd.conexus-dev-sandbox.org",
    "bitbucket.conexus-dev-sandbox.org"
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # zero downtime on rotation
  }
}

# one Route 53 record per validation token
resource "aws_route53_record" "sandbox_validation" {
  for_each = {
    for dvo in aws_acm_certificate.sandbox.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.public_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "sandbox" {
  certificate_arn         = aws_acm_certificate.sandbox.arn
  validation_record_fqdns = [for r in aws_route53_record.sandbox_validation : r.fqdn]
}


resource "aws_lb_listener" "alb_with_waf_http" {
  load_balancer_arn = aws_lb.alb_with_waf.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "alb_with_waf_https" {
  load_balancer_arn = aws_lb.alb_with_waf.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.sandbox.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_to_nginx_tg.arn
  }
  lifecycle {
    create_before_destroy = true # forces attach-new before detach-old
  }
  depends_on = [aws_acm_certificate_validation.sandbox]
}


resource "aws_security_group_rule" "alb_ingress_extnlb_http" {
  description       = "Allow HTTP from external NLB subnet(s)"
  security_group_id = aws_security_group.alb_sg.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = var.extnlb_cidr_blocks
}

resource "aws_security_group_rule" "alb_ingress_extnlb_https" {
  description       = "Allow HTTPS from external NLB subnet(s)"
  security_group_id = aws_security_group.alb_sg.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = var.extnlb_cidr_blocks
}

########################################
# NGINX Ingress Controller
########################################

## NGINX Ingress Controller in EKS
resource "helm_release" "nginx_ingress" {
  name             = "conexus-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.12.0"
  create_namespace = true
  namespace        = "ingress-nginx"
  values = [
    file("../${path.module}/helm/ingress-nginx/values.yaml"),
    yamlencode({
      controller = {
        nginxStatus = {
          allowCidrs = "127.0.0.1/32"
        }
      }
    })
  ]
  timeout = 900
  wait    = true
  depends_on = [
    module.eks,
    helm_release.argocd # Ensure ArgoCD is deployed first
  ]
  replace         = true
  cleanup_on_fail = true
  atomic          = true
  force_update    = true
}

########################################
# Argo CD
########################################
resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.52.1"
  create_namespace = true
  cleanup_on_fail  = true
  atomic           = true
  values = [
    file("../${path.module}/helm/argo-cd/values.yaml")
  ]

  # wait until all pods are ready
  timeout = 600
  wait    = true
  depends_on = [
    module.eks
  ]
}

#######################
#  Bitbucket (Data Center) via Helm
#######################
resource "helm_release" "bitbucket" {
  count            = var.enable_bitbucket ? 1 : 0
  name             = "bitbucket"
  repository       = "https://atlassian.github.io/data-center-helm-charts"
  chart            = "bitbucket"
  version          = "1.17.0"
  namespace        = "bitbucket"
  create_namespace = true

  values           = [file("../${path.module}/helm/bitbucket/values.yaml")]
  timeout          = 300
  wait             = true
  atomic           = true
  force_update     = true
  replace          = true        
  cleanup_on_fail  = true
  max_history      = 10

  set {
    name  = "testPods.enabled"
    value = "false"
  }
  set {
    name  = "atlassianAnalyticsAndSupport.analytics.enabled"
    value = "false"
  }

  depends_on = [
    helm_release.nginx_ingress,
    aws_eks_addon.aws_efs_csi_driver,
    aws_eks_addon.aws_ebs_csi_driver,
    kubernetes_secret.bitbucket_license
  ]
}

resource "kubernetes_secret" "bitbucket_license" {
  count = var.enable_bitbucket ? 1 : 0
  metadata {
    name      = "bitbucket-license"
    namespace = "bitbucket"
  }
  type = "Opaque"

  data = {
    "license.txt" = file("../${path.module}/helm/bitbucket/license.txt")
  }

  depends_on = [helm_release.nginx_ingress]
}


data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^al2023-ami-2023*"
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
/*
resource "aws_network_interface" "ec2proxyhostinterfaceaz1" {
  subnet_id = var.svcsubnetids.az1 != "" ? var.svcsubnetids.az1 : "${var.svcsubnetids.az4}"
  private_ips = var.svcjumpipaddress.az1 != "" ? var.svcjumpipaddress.az1 : "${var.svcjumpipaddress.az4}"
  security_groups =  [
    aws_security_group.bastionhostsg.id,
  ]

  //attachment {
  //  instance     = aws_instance.ec2proxyhost.id
  //  device_index = 1
  //}

  tags = {
    Name = "ec2_proxy_primary_network_interface"
  }
}

resource "aws_network_interface" "ec2dbjumphostinterfaceaz1" {
  subnet_id = var.dbsubnetids.az1 != "" ? var.dbsubnetids.az1 : "${var.dbsubnetids.az4}"
  private_ips = var.dbjumpipaddress.az1 != "" ? var.dbjumpipaddress.az1 : "${var.dbjumpipaddress.az4}"
  security_groups =  [
    aws_security_group.bastionhostsg.id,
  ]

  tags = {
    Name = "ec2_dbjumphost_primary_network_interface"
  }
}

*/

resource "aws_security_group" "bastionhostsg" {
  name_prefix = data.aws_vpc.vpc.id
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "cloudshellkey"
  public_key = file("${path.module}/cloudshellkey.pub")
}

resource "aws_key_pair" "mgmttoenv" {
  key_name   = "mgmgtoenvkey"
  public_key = file("${path.module}/mgmttodev.pub")
}
//al2023-ami-2023.4.20240429.0-kernel-6.1-x86_64
//resource "aws_iam_instance_profile" "ssminstanceprofile" {
//  name = "ssminstanceprofile"
//  role = "arn:aws:iam::339713019047:role/SSMInstanceProfile"
//}

resource "aws_iam_instance_profile" "env-resources-iam-profile" {
  name = "ec2_profile"
  role = aws_iam_role.env-resources-iam-role.name
}

resource "aws_iam_role" "env-resources-iam-role" {
  name               = "${var.vpc_name}-ssm-role"
  description        = "The role for the developer resources EC2"
  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": {
"Effect": "Allow",
"Principal": {"Service": "ec2.amazonaws.com"},
"Action": "sts:AssumeRole"
}
}
EOF

  tags = {
    stack = "test"
  }

}

resource "aws_iam_role_policy_attachment" "env-resources-ssm-policy" {
  role       = aws_iam_role.env-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# Bastion host module removed for all the app environments except for mgmtvpc
#
/*module "bastion" {
  #source = "./aws-bastion"
  source  = "Guimove/bastion/aws"
  version = "3.0.6"
  bucket_name = var.bastion_s3
  region = var.region
  vpc_id = data.aws_vpc.vpc.id
  bastion_host_key_pair = aws_key_pair.deployer.key_name
  create_dns_record = "true"
  hosted_zone_id = var.dnszone.int
  bastion_record_name = "bastion.${var.dnsdomain}"
  bastion_iam_role_name = "BastionHostRole"
  bastion_iam_policy_name = "BastionHostPolicy"
  instance_type = "t3a.medium"
  bastion_ami = var.bastionami
  disk_encrypt = "false"
  disk_size = "100"
  create_elb = "true"
  is_lb_private = "true"
  associate_public_ip_address = "false"
  elb_subnets = [for k, v in var.intnlbsubnetids : "${v}"]
  bastion_security_group_id = aws_security_group.bastionhostsg.id
  auto_scaling_group_subnets = [for k, v in var.svcsubnetids : "${v}"]
  cidrs = var.services_ec2_cidr_blocks
  extra_user_data_content = "perl -pi -e 's:/usr/sbin/adduser:/usr/sbin/adduser -U:g' /usr/bin/bastion/sync_users"
  tags = {
    "name" = "Cnxs Jump Host ${var.dnsdomain}",
    "description" = "Bastion host for ${var.vpc_name} vpc environment"
  }
}

#locals {
#  object_source = "${path.module}/kundm01.pub"
#}

resource "aws_s3_object" "file_upload" {
  for_each    = fileset("./", "*pub")
  bucket      = var.bastion_s3
  key         = "public-keys/${each.value}"
  source      = "./${each.value}"
  source_hash = filemd5("./${each.value}")
  depends_on = [
    module.bastion
  ] 

}



//DNS
resource "aws_route53_record" "bastionhostrecord" {
  zone_id = var.dnszone.ext # Replace with your zone ID
  name    = "bastion.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.extnlb.dns_name]
}
*/

/*
resource "aws_route53_record" "dbjumphostrecord" {
  zone_id = var.dnszone.int # Replace with your zone ID
  name    = "dbjump.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.intnlb.dns_name]
}
*/
// EKS in eks.tf

resource "aws_route53_record" "bastionhostrecord" {
  zone_id = var.dnszone.ext            # Replace with your zone ID
  name    = "bastion.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "300"
  records = [aws_lb.extnlb.dns_name]
}

# Conexus domain
resource "aws_route53_record" "extnlb_record" {
  zone_id = data.aws_route53_zone.public_zone.zone_id
  name    = "app.conexus-dev-sandbox.org"
  type    = "A"

  alias {
    name                   = aws_lb.extnlb.dns_name
    zone_id                = aws_lb.extnlb.zone_id
    evaluate_target_health = true
  }
}

# Argo CD domain
resource "aws_route53_record" "argocd_record" {
  zone_id = data.aws_route53_zone.public_zone.zone_id
  name    = "argocd.conexus-dev-sandbox.org"
  type    = "A"

  alias {
    name                   = aws_lb.extnlb.dns_name # the public NLB
    zone_id                = aws_lb.extnlb.zone_id
    evaluate_target_health = true
  }
}

#######################
#  ECR
#######################
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.vpc_name}-app-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Environment = "all"
  }
}

resource "aws_ecr_repository_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name
  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid    = "AllowEKS"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.awsaccountid}:role/${var.adminrole}"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

resource "aws_route53_record" "bitbucket_record" {
  count   = var.enable_bitbucket ? 1 : 0
  zone_id = data.aws_route53_zone.public_zone.zone_id
  name    = "bitbucket.conexus-dev-sandbox.org"
  type    = "A"
  alias {
    name                   = aws_lb.extnlb.dns_name
    zone_id                = aws_lb.extnlb.zone_id
    evaluate_target_health = true
  }
}

resource "kubernetes_storage_class" "efs_sc" {
  count               = var.enable_bitbucket ? 1 : 0
  metadata { name = "efs-sc" }
  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "Immediate"
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.bitbucket_fs[0].id
    uid              = "2003"
    gid              = "2003"
    directoryPerms   = "0770"
  }
  depends_on = [
    aws_eks_addon.aws_efs_csi_driver,
    aws_efs_mount_target.bitbucket_fs_mt
  ]
}

resource "aws_route53_record" "bamboo_record" {
  zone_id = data.aws_route53_zone.public_zone.zone_id
  name    = "bamboo.conexus-dev-sandbox.org"
  type    = "A"

  alias {
    name                   = aws_lb.extnlb.dns_name # reuse the external NLB
    zone_id                = aws_lb.extnlb.zone_id
    evaluate_target_health = true
  }
}