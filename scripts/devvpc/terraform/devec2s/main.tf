
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

  //attachment {
  //  instance     = aws_instance.ec2proxyhost.id
  //  device_index = 1
  //}

  tags = {
    Name = "Ec2devA_primary_network_interface"
  }
}

resource "aws_instance" "ec2deva" {
  //ami           = "ami-07caf09b362be10b8"
  ami = var.amiid
  instance_type = "t3a.xlarge"
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

  //vpc_security_group_ids = [
  //  aws_security_group.nginxbitbucket.id,
  //]

  //Not used when network_interface is in use
  //subnet_id =  aws_subnet.privateservicesaz4.id

  //iam_instance_profile ="SSMInstanceProfile"
  //aws_iam_instance_profile.ssminstanceprofile.name
  iam_instance_profile = aws_iam_instance_profile.dev-resources-iam-profile.name
  user_data     = base64encode(templatefile("./userdata.sh", {}))
/*  lifecycle {
    ignore_changes = [user_data]
  }*/
  tags = {
    Name = "ec2devahost"
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

resource "aws_iam_role_policy" "ssmpolicy" {
  name = "ssmpolicy"
  role = aws_iam_role.dev-resources-iam-role.id

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
resource "aws_iam_role_policy_attachment" "dev-resources-ssm-policy" {
  role       = aws_iam_role.dev-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

/*
module "cnxsdeva" {
  source  = "Guimove/bastion/aws"
  version = "3.0.6"
  bucket_name = aws_s3_bucket.cnxsdeva.id
  region = var.region
  vpc_id = data.aws_vpc.vpc.id
  bastion_host_key_pair = aws_key_pair.deployer.key_name
  create_dns_record = "true"
  hosted_zone_id = var.dnszone.int
  bastion_record_name = "cnxsdeva.${var.dnsdomain}"
  bastion_iam_role_name = "BastionHostRole"
  bastion_iam_policy_name = "BastionHostPolicy"
  instance_type = "t3a.xlarge"
  bastion_ami = var.bastionami
  disk_encrypt = "false"
  disk_size = "100"
  create_elb = "true"
  is_lb_private = "true"
  associate_public_ip_address = "false"
  elb_subnets = [for k, v in var.intnlbsubnetids : "${v}"]
  bastion_security_group_id = aws_security_group.cnxsdevasg.id
  auto_scaling_group_subnets = [for k, v in var.svcsubnetids : "${v}"]
  cidrs = var.services_ec2_cidr_blocks
  extra_user_data_content = "perl -pi -e 's:/usr/sbin/adduser:/usr/sbin/adduser -U:g' /usr/bin/bastion/sync_users"
  tags = {
    "name" = "Cnxs Dev A ${var.dnsdomain}",
    "description" = "Devlopment host for ${var.vpc_name} vpc environment"
  }
}

resource "aws_s3_object" "file_upload" {
  for_each    = fileset("./", "*pub")
  bucket      = aws_s3_bucket.cnxsdeva.id
  key         = "public-keys/${each.value}"
  source      = "./${each.value}"
  source_hash = filemd5("./${each.value}")
}
*/
