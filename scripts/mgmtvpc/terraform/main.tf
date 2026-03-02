locals {

  vpc_name = "fcs-conexus-mgmt-M"
  ec2_cidr_blocks = [ "10.56.112.0/24", "10.56.113.0/24" ]
  intnlb_cidr_blocks = [ "10.56.119.0/28", "10.56.119.16/28" ]
  pubnlb_cidr_blocks = [ "10.56.82.64/26", "10.56.82.192/26" ]
  intnlb_az4_ipv4_address = "10.56.119.8"
  intnlb_az6_ipv4_address = "10.56.119.26"
  lpvtsvcaz4="Private-Services-az4"
  lpvtsvcaz6="Private-Services-az6"
}


data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [ data.aws_vpc.vpc.id ]
  }
}


output "subnets_out" {
  value = data.aws_subnets.subnets
}

data "aws_subnet" "subnet" {
  for_each = toset(data.aws_subnets.subnets.ids)
  id       = each.value
}

output "subnet" {
  value = [for subnet in data.aws_subnet.subnet : subnet.arn]
}

output "subnetcidr" {
  value = [for subnet in data.aws_subnet.subnet : subnet.cidr_block]
}

resource "aws_eip" "extnlbeipaz4" {
  domain = "vpc"
  tags = {
    Name = "Ext-NLB-EIP-az4"
  }
}
resource "aws_eip" "extnlbeipaz6" {
  domain = "vpc"
  tags = {
    Name = "Ext-NLB-EIP-az6"
  }
}
resource "aws_lb" "extnlb" {

    name               = "${ local.vpc_name }-extnlb"
    //subnets            = [ "subnet-08802ca3ed4143108", "subnet-0f68ebb0567bd4460" ]
    subnet_mapping {
      subnet_id            = "subnet-08802ca3ed4143108"
      allocation_id = aws_eip.extnlbeipaz4.id
    }

    subnet_mapping {
      subnet_id            = "subnet-0f68ebb0567bd4460"
      allocation_id = aws_eip.extnlbeipaz6.id
    }
    internal           = "false"
    load_balancer_type = "network"
    enable_cross_zone_load_balancing = "true"
    depends_on = [aws_eip.extnlbeipaz4, aws_eip.extnlbeipaz6]
}


resource "aws_lb" "intnlb" {

    name               = "${ local.vpc_name }-intnlb"
    //subnets            = [ "${ aws_subnet.pvtintnlbaz4.id }", "${ aws_subnet.pvtintnlbaz6.id }" ]
    internal           = "true"
    load_balancer_type = "network"
    enable_cross_zone_load_balancing = "true"

    subnet_mapping {
      subnet_id = "subnet-01b5aa20b85bb2876"
      private_ipv4_address = local.intnlb_az4_ipv4_address
    }

    subnet_mapping {
      subnet_id = "subnet-013df1d8815ef772b"
      private_ipv4_address = local.intnlb_az6_ipv4_address
    }

}

// LB has target groups -> Listeners -> Target group attachments(final destination)
// -------------Target groups-------
//Ext
resource "aws_lb_target_group" "extnlbtargetgroup" {
  name     = "extnlbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}
resource "aws_lb_target_group" "extnlbhttptargetgroup" {
  name     = "extnlbhttptargetgroup"
  port     = 80
  protocol = "TCP"
  target_type = "instance"
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

//Int
resource "aws_lb_target_group" "intnlbtargetgroup" {
  name     = "intnlbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "instance"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}
resource "aws_lb_target_group" "intnlbhttptargetgroup" {
  name     = "intnlbhttptargetgroup"
  port     = 80
  protocol = "TCP"
  target_type = "instance"
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

// -----------Target group attachements-------

//Targetgroup -> Listener -> Targetgroup attachment

resource "aws_lb_target_group_attachment" "exttoec2nlbtarget" {
  target_group_arn = aws_lb_target_group.extnlbtargetgroup.arn
  //target_id        =  local.intnlb_az4_ipv4_address //aws_lb.intnlb.id
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
resource "aws_lb_target_group_attachment" "inttoec2nlbtarget" {
  target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
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
  target_id        = aws_instance.ec2proxyhost.id
  port             = 22
}

//-----Listeners---------

//Ext
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

//Int
resource "aws_lb_listener" "inttoec2" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
  }
}
resource "aws_lb_listener" "inttoec2http" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbhttptargetgroup.arn
  }
}
resource "aws_lb_listener" "inttoec2ssh" {
  load_balancer_arn = aws_lb.intnlb.arn
  port              = "22"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbsshtargetgroup.arn
  }
}

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

resource "aws_subnet" "privateservicesaz4" {
  vpc_id            = data.aws_vpc.vpc.id
  cidr_block        = "10.56.112.0/24"
  availability_zone = "us-east-1b"
#
#  tags = {
#    Name = "ec2_proxy_host_subnet_az4"
#  }
  lifecycle {
    ignore_changes = all
      # Ignore changes to tags, e.g. because a management agent
      # updates these based on some ruleset managed elsewhere.
     
   
  }
}

resource "aws_route_table_association" "ec2hostsubnetaz4" {
  subnet_id = aws_subnet.privateservicesaz4.id
  # existing route table for az4, private workload (rtb-04889e96a4849f095 / fcs-conexus-mgmt-M-use1-az4-priv-work-rt)
  route_table_id = "rtb-04889e96a4849f095"
  lifecycle {
    ignore_changes = all
  }
}

resource "aws_network_interface" "ec2proxyhostinterfaceaz4" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = "subnet-03dfb5138b5df60b6"
  private_ips = ["10.56.112.33"]
  security_groups =  [
    aws_security_group.nginxbitbucket.id,
  ]

  //attachment {
  //  instance     = aws_instance.ec2proxyhost.id
  //  device_index = 1
  //}

  tags = {
    Name = "ec2_proxy_primary_network_interface"
  }
}

resource "aws_network_interface" "ssmhostinterfaceaz4" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = "subnet-03dfb5138b5df60b6"
  private_ips = ["10.56.112.102"]
  security_groups =  [
    aws_security_group.nginxbitbucket.id,
  ]

  tags = {
    Name = "ssmhost_primary_network_interface"
  }
}

resource "aws_network_interface" "cnxsmgmtatlassianinterfaceaz4" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = "subnet-03dfb5138b5df60b6"
  private_ips = ["10.56.112.34"]
  security_groups =  [
    aws_security_group.nginxbitbucket.id,
  ]

  //attachment {
  //  instance     = aws_instance.ec2proxyhost.id
  //  device_index = 1
  //}

  tags = {
    Name = "cnxs_mgmtatlassian_primary_network_interface"
  }
}

resource "aws_network_interface" "cnxsmgmtbuildagentsinterfaceaz4" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = "subnet-03dfb5138b5df60b6"
  private_ips = ["10.56.112.35"]
  security_groups =  [
    aws_security_group.nginxbitbucket.id,
  ]

  //attachment {
  //  instance     = aws_instance.ec2proxyhost.id
  //  device_index = 1
  //}

  tags = {
    Name = "cnxs_mgmtbuildagents_primary_network_interface"
  }
}

resource "aws_security_group" "nginxbitbucket" {
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
//al2023-ami-2023.4.20240429.0-kernel-6.1-x86_64
//resource "aws_iam_instance_profile" "ssminstanceprofile" {
//  name = "ssminstanceprofile"
//  role = "arn:aws:iam::339713019047:role/SSMInstanceProfile"
//}

resource "aws_iam_instance_profile" "mgmt-resources-iam-profile" {
name = "ec2_profile"
role = aws_iam_role.mgmt-resources-iam-role.name
}

resource "aws_iam_role" "mgmt-resources-iam-role" {
  name        = "mgmt-ssm-role"
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

resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.mgmt-resources-iam-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:iam::752281881774:role/ise-sectool-registration-role"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "mgmt-resources-ssm-policy" {
  role       = aws_iam_role.mgmt-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_instance" "ec2proxyhost" {
  //ami           = "ami-07caf09b362be10b8"
  //ami = "ami-02d5fbfc6aa8fd511"
  // ISE-AMAZON-LINUX-2023-GSA-HARDENED-24-12-28_03-33
  ami = "ami-0577643dc542a74fc"

  instance_type = "t3a.medium"
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2proxyhostinterfaceaz4.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  root_block_device {
    volume_size = 30 
  }
  //vpc_security_group_ids = [
  //  aws_security_group.nginxbitbucket.id,
  //]

  //Not used when network_interface is in use
  //subnet_id =  aws_subnet.privateservicesaz4.id

  //iam_instance_profile ="SSMInstanceProfile"
  //aws_iam_instance_profile.ssminstanceprofile.name
  iam_instance_profile = aws_iam_instance_profile.mgmt-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdata.sh", {}))
  lifecycle {
    ignore_changes = [user_data]
  }
  tags = {
    Name = "ec2proxyhost"
  }
}

resource "aws_instance" "ssmhost" {
  ami = "ami-00beae93a2d981137"
  instance_type = "t3a.small"
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ssmhostinterfaceaz4.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  //subnet_id =  aws_subnet.privateservicesaz4.id
  //iam_instance_profile = "SSMInstanceProfile"
  iam_instance_profile = aws_iam_instance_profile.mgmt-resources-iam-profile.name
  user_data = base64encode(templatefile("./userdatassmhost.sh", {}))
  lifecycle {
    ignore_changes = [user_data]
  }
  tags = {
    Name = "ssmhost"
  }
}

resource "aws_vpc_endpoint_service" "codeartifact" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.intnlb.arn]
  private_dns_name           = "artifact.cnxs.mgmt.vpcaas.fcs.gsa.gov"
}

module "cnxsmgmtcodeartifact" {
  source = "./codeartifact"
}

//DNS Ext
resource "aws_route53_record" "bitbucketrecordext" {
  zone_id = "Z02311902CPT7WD0A25OG" # Public route 53 zone ID
  name    = "bitbucket.mgmt.cnxs.vpcaas.fcs.gsa.gov" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "60"
  records = [aws_lb.extnlb.dns_name]
}
resource "aws_route53_record" "dmsrecordone" {
  zone_id = "Z02311902CPT7WD0A25OG" # Public route 53 zone ID
  name    = "oirxdatdbadm20.mgmt.cnxs.vpcaas.fcs.gsa.gov"
  type    = "A"
  ttl     = "300"
  records = ["199.134.88.40"]
}
resource "aws_route53_record" "dmsrecordtwo" {
  zone_id = "Z02311902CPT7WD0A25OG" # Public route 53 zone ID
  name    = "oirxdatdbadm21.mgmt.cnxs.vpcaas.fcs.gsa.gov"
  type    = "A"
  ttl     = "300"
  records = ["199.134.88.41"]
}
//DNS Int

resource "aws_route53_record" "bitbucketrecordint" {
  zone_id = "Z0280533GOHHH3O7QRN6" # Private route 53 zone ID
  name    = "bitbucket.mgmt.cnxs.vpcaas.fcs.gsa.gov" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "CNAME"
  ttl     = "60"
  records = [aws_lb.intnlb.dns_name]
}
resource "aws_route53_record" "dmsrecordpvtone" {
  zone_id = "Z0280533GOHHH3O7QRN6" # Private route 53 zone ID
  name    = "oirxdatdbadm20.mgmt.cnxs.vpcaas.fcs.gsa.gov"
  type    = "A"
  ttl     = "300"
  records = ["199.134.88.40"]
}
resource "aws_route53_record" "dmsrecordpvttwo" {
  zone_id = "Z0280533GOHHH3O7QRN6" # Private route 53 zone ID
  name    = "oirxdatdbadm21.mgmt.cnxs.vpcaas.fcs.gsa.gov"
  type    = "A"
  ttl     = "300"
  records = ["199.134.88.41"]
}
output "ec2_proxy_host_ip" {
  value = aws_instance.ec2proxyhost.public_ip
}

output "ec2_ssm_host_ip" {
  value = aws_instance.ssmhost.public_ip
}
