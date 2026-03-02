
data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [ data.aws_vpc.vpc.id ]
  }
}

data "aws_subnet" "subnet" {
  for_each = toset(data.aws_subnets.subnets.ids)
  id       = each.value
}

/* 
resource "aws_lb" "extnlb" {

  name = "${ var.vpc_name }-extnlb"
  subnets = [for k, v in var.extnlbsubnetids : "${v}"]
  internal           = "true"
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = "true"
  
} 

resource "aws_lb" "intnlb" {

  name               = "${ var.vpc_name }-intnlb"
  internal           = "true"
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = "true"
  subnets = [for k, v in var.intnlbsubnetids : "${v}"]
}

// LB has target groups -> Listeners -> Target group attachments(final destination)
// Target groups
//External lb to pvt services 443, 80 and 22
//Internal lb to pvt services 443, 80 and 22

resource "aws_lb_target_group" "extnlbtargetgroup" {
  name     = "extnlbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}

resource "aws_lb_target_group" "extnlbhttptargetgroup" {
  name     = "extnlbhttptargetgroup"
  port     = 80 
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}


resource "aws_lb_target_group" "extnlbsshtargetgroup" {
  name     = "extnlbsshtargetgroup"
  port     = 22
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}

// Internal NLB target groups

resource "aws_lb_target_group" "intnlbtargetgroup" {
  name     = "intnlbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}

resource "aws_lb_target_group" "intnlbhttptargetgroup" {
  name     = "intnlbhttptargetgroup"
  port     = 80
  protocol = "TCP"
  target_type = "alb"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}

resource "aws_lb_target_group" "intnlbsshtargetgroup" {
  name     = "intnlbsshtargetgroup"
  port     = 22
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}
*/
// Target group attachements

//Targetgroup -> Listener -> Targetgroup attachment
/*
resource "aws_lb_target_group_attachment" "exttoec2nlbtarget" {
  target_group_arn = aws_lb_target_group.extnlbtargetgroup.arn
  //target_id        =  var.intnlb_az4_ipv4_address //aws_lb.intnlb.id
  target_id        = aws_instance.ec2proxyhost.id
  port             = 443
}
resource "aws_lb_target_group_attachment" "exttoec2httpnlbtarget" {
  target_group_arn = aws_lb_target_group.extnlbhttptargetgroup.arn
  target_id        = aws_instance.ec2proxyhost.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "exttoec2sshnlbtarget" {
  target_group_arn = aws_lb_target_group.extnlbsshtargetgroup.arn
  target_id        = aws_instance.ec2proxyhost.id
  port             = 22 
}
*/
//Internal nlb to proxy host
/*
resource "aws_lb_target_group_attachment" "inttoec2nlbtarget" {
  target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
  //target_id        =  var.intnlb_az4_ipv4_address //aws_lb.intnlb.id
  target_id        = aws_instance.ec2proxyhost.id
  port             = 443
}
resource "aws_lb_target_group_attachment" "inttoec2httpnlbtarget" {
  target_group_arn = aws_lb_target_group.intnlbhttptargetgroup.arn
  target_id        = aws_instance.ec2proxyhost.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "inttoec2sshnlbtarget" {
  target_group_arn = aws_lb_target_group.intnlbsshtargetgroup.arn
  // target_id        = aws_instance.ec2dbjumphost.id
  target_id        = aws_instance.ec2proxyhost.id
  port             = 22
}
*/

/*
//Listeners
resource "aws_lb_listener" "exttoec2" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "443"
  protocol          = "TCP"
  //certificate_arn   = "arn:aws:iam::
  //alpn_policy       = "HTTP2Preferred"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extnlbtargetgroup.arn
  }
}

resource "aws_lb_listener" "exttoec2http" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extnlbhttptargetgroup.arn
  }
}

resource "aws_lb_listener" "exttoec2ssh" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extnlbsshtargetgroup.arn
  }
}
*/
/*
resource "aws_lb_listener" "inttodbjump" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
  }
}

resource "aws_lb_listener" "inttodbjumphttp" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbhttptargetgroup.arn
  }
}
*/
/*
resource "aws_lb_listener" "inttodbjumpssh" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbsshtargetgroup.arn
  }
}
*/

//EC2

//Future use
data "aws_ami" "al2023" {
  most_recent = true
  owners = ["amazon"]
  name_regex = "^al2023-ami-2023*"
  filter {
    name = "architecture"
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
  vpc_id            = data.aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "cloudshellkey"
  public_key = file("${path.module}/cloudshellkey.pub")
}

resource "aws_key_pair" "mgmttoenv" {
  key_name = "mgmgtoenvkey"
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
  name        = "${var.vpc_name}-ssm-role"
  description = "The role for the developer resources EC2"
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


