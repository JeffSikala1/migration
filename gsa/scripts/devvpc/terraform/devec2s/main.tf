
data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}



//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "devec2cloudshellkey"
  public_key = file("${path.module}/../cloudshellkey.pub")
}


resource "aws_security_group" "cnxsdevasg" {
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

resource "aws_network_interface" "ec2devahostinterfaceaz1" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = var.svcsubnetids.az1
  private_ips = var.ec2devaipaddress.az1
  security_groups =  [
    aws_security_group.cnxsdevasg.id,
  ]

  tags = {
    Name = "Ec2devA_primary_network_interface"
  }
}
resource "aws_network_interface" "ec2devbhostinterfaceaz1" {
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = var.svcsubnetids.az1
  private_ips = var.ec2devbipaddress.az1
  security_groups =  [
    aws_security_group.cnxsdevasg.id,
  ]

  tags = {
    Name = "Ec2devB_primary_network_interface"
  }
}

# Instance A
resource "aws_instance" "ec2deva" {
  ami = var.amiid
  instance_type = var.ec2instancetype #"r6a.xlarge"
  root_block_device {
    volume_size = 200
  }
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2devahostinterfaceaz1.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  iam_instance_profile = aws_iam_instance_profile.dev-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdataa.sh", {}))

  tags = {
    Name = "ec2devahost"
  }
}

# Instance B
resource "aws_instance" "ec2devb" {
  ami = var.amiid
  instance_type = var.ec2instancetype
  root_block_device {
    volume_size = 200
  }
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2devbhostinterfaceaz1.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  iam_instance_profile = aws_iam_instance_profile.dev-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdatab.sh", {}))

  tags = {
    Name = "ec2devbhost"
  }
}

resource "aws_iam_instance_profile" "dev-resources-iam-profile" {
  name = "ec2deva_profile"
  role = aws_iam_role.dev-resources-iam-role.name
}

resource "aws_iam_role" "dev-resources-iam-role" {
  name        = "ec2dev-ssm-role"
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

resource "aws_iam_policy" "ssmpolicy" {
  name = "ssmpolicy"
  //role = aws_iam_role.dev-resources-iam-role.id

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
resource "aws_iam_role_policy_attachment" "dev-resources-ssm-policy" {
  role       = aws_iam_role.dev-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "dev-resources-ssm-policy-b" {
  role       = aws_iam_role.dev-resources-iam-role.name
  policy_arn = aws_iam_policy.ssmpolicy.arn
}


resource "aws_route53_record" "ec2devarecord" {
  zone_id = var.dnszone.int # Replace with your zone ID
  name    = "ec2deva.${var.dnsdomain}" # Replace with your subdomain, Note: not valid with "apex" domains, e.g. example.com
  type    = "A"
  ttl     = "300"
  records = var.ec2devaipaddress.az1
}


resource "aws_route53_record" "ec2devbrecord" {
  zone_id = var.dnszone.int 
  name    = "ec2devb.${var.dnsdomain}" 
  type    = "A"
  ttl     = "300"
  records = var.ec2devbipaddress.az1
}
