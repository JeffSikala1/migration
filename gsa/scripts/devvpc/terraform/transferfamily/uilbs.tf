# 
# nlbsubnetids variable decides whether the NLB is created in the GSA subnet(internal subnet) or the External Subnet, the variable is set based on the VPC environment
# 


locals {
  uinlbtag = {
    Name = "out-uinlb"
  }
  uialbtag = {
    Name = "uiwaf-uialb"
  }
  sguiwafuialbtag = {
    Name = "uiwaf-uialb-sg"
    ResourceRole="SG for Conexus Load Balancer"
  }

}

data "aws_lb" "ingressuinlb" {
  tags = {
    "kubernetes.io/service-name" = "ingress-nginx/cilium-gateway-uicilium"
  }
}

# EKS -> Ingress UINLB -> UIALB+WAF -> Out UINLB
# Out UINLB
resource "aws_lb" "outuinlb" {
  name = "${ var.vpc_name }-outuinlb"
  subnets = [for k, v in var.nlbsubnetids : "${v}"]
  internal           = "true"
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = "true"
  tags = merge(var.tags, local.lbtags, local.uinlbtag) 
}
# UIALB for UIWAF
resource "aws_security_group" "uiwafuialb_sg" {
  name   = "${var.vpc_name}-uiwafuialb-sg"
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
  tags = merge(var.tags, local.lbtags, local.sguiwafuialbtag)
}
resource "aws_lb" "uiwafuialb" {
  name = "${ var.vpc_name }-uiwafuialb"
  subnets = [for k, v in var.nlbsubnetids : "${v}"]
  internal           = "true"
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = "true"
  security_groups = [aws_security_group.uiwafuialb_sg.id]
  tags = merge(var.tags,local.lbtags, local.uialbtag)
}
# Ingress NLB target tags
#  kubernetes.io/cluster/cnxsdev-selfmanaged = owned
#  kubernetes.io/service-name = ingess-nginx/cilium-gateway-cilium
#  
# Target groups
#  Out uinlb to uialb
resource "aws_lb_target_group" "outuinlbtouialbtargetgroup" {
  name     = "outuinlbtouialbtargetgroup"
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
resource "aws_lb_target_group" "outuinlbtouialbtargetgrouphttp" {
  name     = "outuinlbtouialbtargetgrouphttp"
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
resource "aws_lb_target_group" "outuinlbtouialbtargetgroupsftp" {
  name     = "outuinlbtouialbtargetgroupsftp"
  port     = 22
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = data.aws_vpc.vpc.id
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  health_check {
    protocol = "TCP"
    port     = "22"
  }
}

#  ALB to ingress nlb
resource "aws_lb_target_group" "uialbtoingressuinlbtargetgroup" {
  name     = "uialbtoingressuinlbtargetgroup"
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

resource "aws_lb_target_group" "uialbtoingressuinlbtghttp" {
  name     = "uialbtoingressuinlbtghttp"
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
resource "aws_lb_target_group_attachment" "outuinlbattachment" {
  target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgroup.arn
  target_id        = aws_lb.uiwafuialb.arn 
  port             = 443
  depends_on = [ aws_lb_listener.outuinlb_listener_https ]
}
resource "aws_lb_target_group_attachment" "outuinlbattachmenthttp" {
  target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgrouphttp.arn
  target_id        = aws_lb.uiwafuialb.arn 
  port             = 80
  depends_on = [ aws_lb_listener.outuinlb_listener_http ]
}
# we need the Tranfer Family VPC end point's ip for target_id. Lets extract it.
data "aws_network_interface" "tfsftp" {
  #for_each = var.subnets
  filter {
    name   = "description"
    values = ["VPC Endpoint Interface ${aws_transfer_server.conexussftp.endpoint_details[0].vpc_endpoint_id}"]
  }
  filter {
    name   = "subnet-id"
    #values = [each.value]
    values = [var.nlbsubnetids.az2]
  }
}
resource "aws_lb_target_group_attachment" "outuinlbattachmentsftp" {
  target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgroupsftp.arn
  target_id        = data.aws_network_interface.tfsftp.private_ip 
  port             = 22
}

# we need the ip for target_id. Lets extract it.
data "aws_network_interface" "uinlb" {
  #for_each = var.subnets
  filter {
    name   = "description"
    values = ["ELB ${data.aws_lb.ingressuinlb.arn_suffix}"]
  }
  filter {
    name   = "subnet-id"
    #values = [each.value]
    values = [var.nlbsubnetids.az2]
  }
}

resource "aws_lb_target_group_attachment" "uiwafuialbattachment" {
  target_group_arn = aws_lb_target_group.uialbtoingressuinlbtargetgroup.arn
  target_id        = data.aws_network_interface.uinlb.private_ip
  port             = 443
}
resource "aws_lb_target_group_attachment" "uiwafuialbattachmenthttp" {
  target_group_arn = aws_lb_target_group.uialbtoingressuinlbtghttp.arn
  target_id        = data.aws_network_interface.uinlb.private_ip
  port             = 80
}

# Listeners
resource "aws_lb_listener" "outuinlb_listener_https" {
  load_balancer_arn = aws_lb.outuinlb.arn
  port              = "443"
  protocol          = "TCP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgroup.arn
  }
}
resource "aws_lb_listener" "outuinlb_listener_http" {
  load_balancer_arn = aws_lb.outuinlb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgrouphttp.arn
  }
}
resource "aws_lb_listener" "outuinlb_listener_sftp" {
  load_balancer_arn = aws_lb.outuinlb.arn
  port              = "22"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.outuinlbtouialbtargetgroupsftp.arn
  }
}

resource "aws_lb_listener" "uiwafuialb_listener_https" {
  load_balancer_arn = aws_lb.uiwafuialb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.wildcardcert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.uialbtoingressuinlbtargetgroup.arn
  }
}

resource "aws_lb_listener" "uiwafuialb_listener_http" {
  load_balancer_arn = aws_lb.uiwafuialb.arn
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


