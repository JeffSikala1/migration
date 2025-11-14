#
# Some resources, like developer ec2 resource will only be created in devvpc where as dbadmin host will be created in four release environments
# Thus exists the boolean flag variable createdevec2s
#

data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}



//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "dbadminec2cloudshellkey"
  public_key = file("${path.module}/../cloudshellkey.pub")
}


resource "aws_security_group" "cnxsdevasg" {
  count = var.createdevec2s ? 1 : 0
  name = "cnxsdeveloperec2sg"
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

resource "aws_security_group" "dbadminsg" {
  name = "dbadminhostsg"
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

resource "aws_network_interface" "ec2dbahostinterfaceaz2" {
  subnet_id = var.svcsubnetids.az2
  private_ips = var.dbadminipaddress.az2
  security_groups =  [
    aws_security_group.dbadminsg.id,
  ]

  tags = {
    Name = "Ec2dbadminhost_primary_network_interface"
  }
}

resource "aws_network_interface" "ec2devahostinterfaceaz2" {
  count = var.createdevec2s ? 1 : 0
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = var.svcsubnetids.az2
  private_ips = var.ec2devaipaddress.az2
  security_groups =  [
    aws_security_group.cnxsdevasg[0].id,
  ]

  tags = {
    Name = "Ec2devA_primary_network_interface"
  }
}

resource "aws_network_interface" "ec2devbhostinterfaceaz2" {
  count = var.createdevec2s ? 1 : 0
  // subnet_id   = aws_subnet.privateservicesaz4.id
  subnet_id = var.svcsubnetids.az2
  private_ips = var.ec2devbipaddress.az2
  security_groups =  [
    aws_security_group.cnxsdevasg[0].id,
  ]

  tags = {
    Name = "Ec2devB_primary_network_interface"
  }
}

# DB Admin instance A
resource "aws_instance" "ec2dbadmin" {
  ami = var.dbadminamiid
  instance_type = var.ec2dbinstancetype
  root_block_device {
    volume_size = 200
  }
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2dbahostinterfaceaz2.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  iam_instance_profile = aws_iam_instance_profile.ec2-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdatadb.sh", {}))
  disable_api_termination = true
  tags = {
    Name = "ec2dbadminhost"
  }
}

# Instance A
resource "aws_instance" "ec2deva" {
  count = var.createdevec2s ? 1 : 0
  ami = var.amiid
  instance_type = var.ec2instancetype
  root_block_device {
    volume_size = 200
  }
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2devahostinterfaceaz2[0].id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  iam_instance_profile = aws_iam_instance_profile.ec2-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdataa.sh", {}))

  disable_api_termination = true
  
  tags = {
    Name = "ec2devahost"
  }
}

# Instance B
resource "aws_instance" "ec2devb" {
  count = var.createdevec2s ? 1 : 0
  ami = var.amiid
  instance_type = var.ec2instancetype
  root_block_device {
    volume_size = 200
  }
  key_name = aws_key_pair.deployer.key_name

  network_interface {
    network_interface_id = aws_network_interface.ec2devbhostinterfaceaz2[0].id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  iam_instance_profile = aws_iam_instance_profile.ec2-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdatab.sh", {}))

  disable_api_termination = true
  
  tags = {
    Name = "ec2devbhost"
  }
}

resource "aws_iam_instance_profile" "ec2-resources-iam-profile" {
  name = "ec2s_profile"
  role = aws_iam_role.ec2-resources-iam-role.name
}

resource "aws_iam_role" "ec2-resources-iam-role" {
  name        = "ec2s-ssm-role"
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
  name = "ec2sssmpolicy"

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
resource "aws_iam_role_policy_attachment" "ec2-resources-ssm-policy" {
  role       = aws_iam_role.ec2-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2-resources-ssm-policy-b" {
  role       = aws_iam_role.ec2-resources-iam-role.name
  policy_arn = aws_iam_policy.ssmpolicy.arn
}

resource "aws_iam_role_policy_attachment" "ec2-resources-logwatch-policy" {
  role       = aws_iam_role.ec2-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}



resource "aws_route53_record" "dbadminarecord" {
  zone_id = var.dnszone.int 
  name    = "dbadmin.${var.dnsdomain}" 
  type    = "A"
  ttl     = "300"
  records = var.dbadminipaddress.az2
}

resource "aws_route53_record" "ec2devarecord" {
  count = var.createdevec2s ? 1 : 0
  zone_id = var.dnszone.int 
  name    = "ec2deva.${var.dnsdomain}" 
  type    = "A"
  ttl     = "300"
  records = var.ec2devaipaddress.az2
}


resource "aws_route53_record" "ec2devbrecord" {
  count = var.createdevec2s ? 1 : 0
  zone_id = var.dnszone.int 
  name    = "ec2devb.${var.dnsdomain}" 
  type    = "A"
  ttl     = "300"
  records = var.ec2devbipaddress.az2
}


# Attach EFS file system to dbadmin host
# Targets are coded in parent efs.tf and output for database az2 mounttarget  is saved manually
#  to <env>vpc.tfvars file as the variable databaseaz2mtid

/*data "aws_efs_mount_target" "databaseaz2mtby_id" {
  mount_target_id = var.databaseaz2mtid
}*/


