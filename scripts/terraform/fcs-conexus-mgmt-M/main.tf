terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

locals{
  vpc_name = "fcs-conexus-mgmt-M"
  ec2_cidr_blocks = [ "10.56.112.0/24", "10.56.113.0/24" ]
  intnlb_cidr_blocks = [ "10.56.119.0/28", "10.56.119.16/28" ]
  pubnlb_cidr_blocks = [ "10.56.82.64/26", "10.56.82.192/26" ]
  intnlb_az4_ipv4_address = "10.56.119.8"
  intnlb_az6_ipv4_address = "10.56.119.26"
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
 
resource "aws_lb" "extnlb" {

    name               = "${ local.vpc_name }-extnlb"
    subnets            = [ "subnet-08802ca3ed4143108", "subnet-0f68ebb0567bd4460" ]
    internal           = "false"
    load_balancer_type = "network"


} 

resource "aws_subnet" "pvtintnlbaz4" {
  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = "10.56.119.0/28"

  tags = {
    Name = "Private-Int-NLB-az4"
  }
}

resource "aws_subnet" "pvtintnlbaz6" {
  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = "10.56.119.16/28"

  tags = {
    Name = "Private-Int-NLB-az6"
  }
}

resource "aws_lb" "intnlb" {

    name               = "${ local.vpc_name }-intnlb"
    //subnets            = [ "${ aws_subnet.pvtintnlbaz4.id }", "${ aws_subnet.pvtintnlbaz6.id }" ]
    internal           = "true"
    load_balancer_type = "network"

    subnet_mapping {
      subnet_id = aws_subnet.pvtintnlbaz4.id
      private_ipv4_address = local.intnlb_az4_ipv4_address
    }

    subnet_mapping {
      subnet_id = aws_subnet.pvtintnlbaz6.id
      private_ipv4_address = local.intnlb_az6_ipv4_address
    } 

}


// Targets
resource "aws_lb_target_group" "extnlbtargetgroup" {
  name     = "extnlbtargetgroup"
  port     = 443
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = data.aws_vpc.vpc.id

  target_health_state {
    enable_unhealthy_connection_termination = false
  }
}

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

resource "aws_lb_target_group_attachment" "exttointnlbtarget" {
  target_group_arn = aws_lb_target_group.extnlbtargetgroup.arn
  target_id        =  local.intnlb_az4_ipv4_address //aws_lb.intnlb.id
  port             = 443
}

resource "aws_lb_target_group_attachment" "inttoinstancetarget" {
  target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
  target_id        = aws_instance.ec2proxyhost.id
  port             = 443
}


//Listeners
resource "aws_lb_listener" "exttoint" {
  load_balancer_arn = aws_lb.extnlb.arn
  port              = "443"
  protocol          = "TCP"
  //certificate_arn   = "arn:aws:iam::
  //alpn_policy       = "HTTP2Preferred"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.intnlbtargetgroup.arn
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

  tags = {
    Name = "ec2_proxy_host_subnet_az4"
  }
}

resource "aws_network_interface" "ec2proxyhostinterfaceaz4" {
  subnet_id   = aws_subnet.privateservicesaz4.id
  private_ips = ["10.56.112.11"]

  tags = {
    Name = "ec2_proxy_primary_network_interface"
  }
}


resource "aws_security_group" "nginxbitbucket" {
  name_prefix = data.aws_vpc.vpc.id
  vpc_id            = data.aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "cloudshellkey"
  public_key = file("${path.module}/id_rsa.pub")
}
//al2023-ami-2023.4.20240429.0-kernel-6.1-x86_64
resource "aws_instance" "ec2proxyhost" {
  ami           = "ami-07caf09b362be10b8"
  instance_type = "t3a.medium"
  key_name = aws_key_pair.deployer.key_name

  //network_interface {
    //network_interface_id = aws_network_interface.ec2proxyhostinterfaceaz4.id
    //device_index         = 0
  //}

  credit_specification {
    cpu_credits = "unlimited"
  }

  vpc_security_group_ids = [
    aws_security_group.nginxbitbucket.id,
  ]
  subnet_id =  aws_subnet.privateservicesaz4.id
  user_data = <<-EOF
              #!/bin/bash
              yum install -y docker
              systemctl enable docker
              systemctl start docker
              sudo chown $USER /var/run/docker.sock
              docker run -p 80:80 -d nginx
              EOF
}

output "ec2_proxy_host_ip" {
  value = aws_instance.ec2proxyhost.public_ip
}