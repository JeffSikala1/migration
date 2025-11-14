variable "vpc_id" {
   type = string
}
provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amzn-linux-2023-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "experiement" {
  ami = data.aws_ami.amzn-linux-2023-ami.id
  instance_type = "t2.micro"
  
  vpc_security_group_ids = ["${aws_security_group.instance.id}"]
  subnet_id = "subnet-0d4df1cc1b29d0b5f"
  key_name = "kundalam01"
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello Howdy!" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF

  tags = {
    Name = "terraform-experiement"
  }
}

resource "aws_security_group" "instance" {
  name = "terraform-experiement-instance"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = "0" 
    to_port = "65535"
    protocol = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
}

