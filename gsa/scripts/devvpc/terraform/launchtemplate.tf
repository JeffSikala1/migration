data "template_file" "launch_template_userdata" {
  template = file("${path.module}/nodeuserdata.sh.tpl")

  vars = {
    cluster_name        = var.eksclustername
    endpoint            = aws_eks_cluster.eks_cluster.endpoint
    cluster_auth_base64 = aws_eks_cluster.eks_cluster.certificate_authority[0].data

    bootstrap_extra_args = " --use-max-pods false"
    kubelet_extra_args   = ""
  }
}

resource "aws_launch_template" "eks_nodes" {
  name = "eksnode-launch-template"
  image_id = var.eksamiid
  description = "Default EKS Node Launch Template"
  instance_type = var.eksinstancetype[0]
  key_name = var.sshpubkeyname
  vpc_security_group_ids = [aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id, aws_security_group.ingressnodessh.id] #For cluster to worker node access

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type = "gp3"
      volume_size = "100"
      delete_on_termination = true
    }
  }
  monitoring {
    enabled = true
  }
  
  placement {
    availability_zone = var.ekslaunchtemplatezone
  }

/*  iam_instance_profile {
    name = "node_profile"
  }
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
  }
*/
  # If you use a custom AMI, you need to supply via user-data, the bootstrap script as EKS DOESNT merge its managed user-data then
  # you can add more than the minimum code you see in the template, e.g. install SSM agent, see https://github.com/aws/containers-roadmap/issues/593#issuecomment-577181345
  #
  # (optionally you can use https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/cloudinit_config to render the script, example: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/997#issuecomment-705286151)

  /*user_data = base64encode(
    data.template_file.launch_template_userdata.rendered,
    )
  */
  #user_data = base64encode("${path.module}/nodeuserdata.sh")
  user_data = base64encode(<<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/node.eks.aws

---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${var.eksclustername}
    apiServerEndpoint: ${aws_eks_cluster.eks_cluster.endpoint}
    certificateAuthority: ${aws_eks_cluster.eks_cluster.certificate_authority[0].data}
    cidr: ${var.services_ec2_cidr_blocks[0]}
  kubelet:
    config:
      clusterDNS:
      - 172.20.0.10
    flags:
    - --cluster-dns=172.20.0.10

--BOUNDARY
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -o xtrace
yum install wireguard-tools -y  
/build-artifacts/sectools-registration.sh -r arn:aws:iam::752281881774:role/ise-sectool-registration-role -e ${var.sectoolregenv} -x NIL -t Q-Conexus -f Q-Conexus -o Q-Conexus 2>&1

--BOUNDARY--

EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = var.tags
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "optional"
  }
  tag_specifications {
    resource_type = "network-interface"
    tags = var.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags = var.tags
  }
/*  lifecycle {
    create_before_destroy = true
  }
*/
}
