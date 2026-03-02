# 
# nlbsubnetids variable decides whether the NLB is created in the GSA subnet(internal subnet) or the External Subnet, the variable is set based on the VPC environment
# 

data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}

locals {
  nlbtag = {
    Name = "out-nlb"
  }
  albtag = {
    Name = "waf-alb"
  }
  sgwafalbtag = {
    Name = "waf-alb-sg"
    ResourceRole="SG for Conexus Load Balancer"
  }
  lbtags = {
    Terraform   = "true"
    Team = "Ops"
    ResourceRole="Conexus Load balancer"
    Service="LoadBalancer"
    ResourceClass="SystemAdmin"
    Application = "Conexus"
  }

}

data "aws_lb" "ingressnlb" {
  tags = {
    "kubernetes.io/service-name" = "ingress-nginx/cilium-gateway-apicilium"
  }
}

# EKS -> Ingress NLB -> ALB+WAF -> Out NLB
# Out NLB
resource "aws_lb" "outnlb" {
  name = "${ var.vpc_name }-outnlb"
  subnets = [for k, v in var.nlbsubnetids : "${v}"]
  internal           = "true"
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = "true"
  tags = merge(var.tags, local.lbtags, local.nlbtag) 
}
# ALB for WAF
resource "aws_security_group" "wafalb_sg" {
  name   = "${var.vpc_name}-wafalb-sg"
  vpc_id = data.aws_vpc.vpc.id
  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, local.lbtags, local.sgwafalbtag)
}
resource "aws_lb" "wafalb" {
  name = "${ var.vpc_name }-wafalb"
  subnets = [for k, v in var.nlbsubnetids : "${v}"]
  internal           = "true"
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = "true"
  security_groups = [aws_security_group.wafalb_sg.id]
  tags = merge(var.tags,local.lbtags, local.albtag)
}
# Ingress NLB target tags
#  kubernetes.io/cluster/cnxsdev-selfmanaged = owned
#  kubernetes.io/service-name = ingess-nginx/cilium-gateway-cilium
#  
# Target groups
#  Out nlb to alb
resource "aws_lb_target_group" "outnlbtoalbtargetgroup" {
  name     = "outnlbtoalbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  health_check {
    protocol = "HTTP"
    port     = "80"
    matcher  = "200-499"
  }
}
resource "aws_lb_target_group" "outnlbtoalbtargetgrouphttp" {
  name     = "outnlbtoalbtargetgrouphttp"
  port     = 80
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  health_check {
    protocol = "HTTP"
    port     = "80"
    matcher  = "200-499"
  }
}

#  ALB to ingress nlb
resource "aws_lb_target_group" "albtoingressnlbtargetgroup" {
  name     = "albtoingressnlbtargetgroup"
  port     = 443
  protocol = "HTTPS"
  target_type = "ip"
  vpc_id   = data.aws_vpc.vpc.id
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  health_check {
    protocol = "HTTP"
    port = "80"
    matcher  = "200-499"
  }
}

resource "aws_lb_target_group" "albtoingressnlbtargetgrouphttp" {
  name     = "albtoingressnlbtargetgrouphttp"
  port     = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = data.aws_vpc.vpc.id
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  health_check {
    protocol = "HTTP"
    port = "80"
    matcher  = "200-499"        
  }
}

# Targetgroup attachment
resource "aws_lb_target_group_attachment" "outnlbattachment" {
  target_group_arn = aws_lb_target_group.outnlbtoalbtargetgroup.arn
  target_id        = aws_lb.wafalb.arn 
  port             = 443
  depends_on = [ aws_lb_listener.wafalb_listener_https ]
}
resource "aws_lb_target_group_attachment" "outnlbattachmenthttp" {
  target_group_arn = aws_lb_target_group.outnlbtoalbtargetgrouphttp.arn
  target_id        = aws_lb.wafalb.arn 
  port             = 80
  depends_on = [ aws_lb_listener.wafalb_listener_http ]
}

# we need the ip for target_id. Lets extract it.
data "aws_network_interface" "nlb" {
  #for_each = var.subnets
  filter {
    name   = "description"
    values = ["ELB ${data.aws_lb.ingressnlb.arn_suffix}"]
  }
  filter {
    name   = "subnet-id"
    #values = [each.value]
    values = [var.nlbsubnetids.az2]
  }
}

resource "aws_lb_target_group_attachment" "wafalbattachment" {
  target_group_arn = aws_lb_target_group.albtoingressnlbtargetgroup.arn
  target_id        = data.aws_network_interface.nlb.private_ip
  port             = 443
}
resource "aws_lb_target_group_attachment" "wafalbattachmenthttp" {
  target_group_arn = aws_lb_target_group.albtoingressnlbtargetgrouphttp.arn
  target_id        = data.aws_network_interface.nlb.private_ip
  port             = 80
}

# Certificate 
resource "aws_acm_certificate" "wildcardcert" {
  certificate_body = file("./cert4.pem")
  private_key      = file("./privkey4.pem")
  # Optionally, include the certificate chain
  #certificate_chain = file("path/to/your/certificate_chain.pem")
}
# Truststore Load Balancer Listener: CA Bundle for mTLS auth
resource "aws_lb_trust_store" "cnxscabundle" {
  name = "cnxscabundle"

  ca_certificates_bundle_s3_bucket = var.truststore_s3
  ca_certificates_bundle_s3_key    = "mtlscabundle.pem"

}
# Listeners
resource "aws_lb_listener" "outnlb_listener_https" {
  load_balancer_arn = aws_lb.outnlb.arn
  port              = "443"
  protocol          = "TCP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.outnlbtoalbtargetgroup.arn
  }
}
resource "aws_lb_listener" "outnlb_listener_http" {
  load_balancer_arn = aws_lb.outnlb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.outnlbtoalbtargetgrouphttp.arn
  }
}

resource "aws_lb_listener" "wafalb_listener_https" {
  load_balancer_arn = aws_lb.wafalb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.wildcardcert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.albtoingressnlbtargetgroup.arn
  }
  mutual_authentication {
    mode = "verify"
    trust_store_arn=aws_lb_trust_store.cnxscabundle.arn
  }
}

resource "aws_lb_listener" "wafalb_listener_http" {
  load_balancer_arn = aws_lb.wafalb.arn
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


