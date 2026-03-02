resource "aws_security_group" "ingresssftpefs" {
  name   = "ingresssftpefs"
  vpc_id = data.aws_vpc.vpc.id

  // Let NFS incoming
  ingress {
    description = "Security Group for letting in NFS requests"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Out from NFS/EFS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ingress_efs_sftp"
  }

}
resource "aws_efs_file_system" "efschroot" {
  creation_token = "Conexus SFTP Data"
  encrypted      = true
  tags = {
    Name = "Conexus SFTP Data"
  }
}
resource "aws_efs_file_system" "efsquarantine" {
  creation_token = "Conexus SFTP reject"
  encrypted      = true
  tags = {
    Name = "Conexus SFTP reject"
  }
}
resource "aws_efs_file_system" "efsdatabase" {
  creation_token = "Conexus SFTP Database"
  encrypted      = true
  tags = {
    Name = "Conexus SFTP Database"
  }
}
resource "aws_efs_file_system" "efsattachments" {
  creation_token = "Conexus Order attachments"
  encrypted      = true
  tags = {
    Name = "Conexus Order attachments"
  }
}
resource "aws_efs_file_system" "efsreports" {
  creation_token = "Conexus UI Reports"
  encrypted      = true
  tags = {
    Name = "Conexus UI Reports"
  }
}

resource "aws_efs_file_system" "bitbucket_fs" {
  count          = var.enable_bitbucket ? 1 : 0
  creation_token = "bitbucket-shared-home"
  encrypted      = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = { Name = "bitbucket-shared-home" }
}

// mount targets in each worker subnet (only when enabled)
resource "aws_efs_mount_target" "bitbucket_fs_mt" {
  for_each       = var.enable_bitbucket ? toset(values(var.svcsubnetids)) : toset([])
  file_system_id = aws_efs_file_system.bitbucket_fs[0].id
  subnet_id      = each.value
  security_groups = [
    module.eks.node_security_group_id
  ]
}

# EFS chroot policy -Allow role/cnxs-transferfamily-sftp-role
resource "aws_efs_file_system_policy" "policy" {
  file_system_id = aws_efs_file_system.efschroot.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "SFTPChrootPolicy",
    "Statement": [
        {
            "Sid": "NFS-client-read-write-via-fsmt",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "elasticfilesystem:ClientRootAccess",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:ClientMount"
            ],
            "Condition": {
                "Bool": {
                    "elasticfilesystem:AccessedViaMountTarget": "true"
                }
            }
        },
        {
            "Sid": "SFTPChrootPolicyStatement",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${var.awsaccountid}:role/cnxs-transferfamily-sftp-role"
            },
            "Resource": "${aws_efs_file_system.efschroot.arn}",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
            ]
        }
    ]
}
POLICY
}

# EFS targets 
resource "aws_efs_mount_target" "efstargetchroot" {
  for_each        = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efschroot.id
  subnet_id       = each.value
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetquarantine" {
  for_each        = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsquarantine.id
  subnet_id       = each.value
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetdatabase" {
  for_each        = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsdatabase.id
  subnet_id       = each.value
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetattachments" {
  for_each        = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsattachments.id
  subnet_id       = each.value
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetreports" {
  for_each        = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsreports.id
  subnet_id       = each.value
  security_groups = [aws_security_group.ingresssftpefs.id]
}


output "efsid" {
  description = "Mount Target IDs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.id }
}

output "efsdnsnames" {
  description = "Mount Target DNS names"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.dns_name }
}

output "efstargetdnsnames" {
  description = "Mount Target names"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.mount_target_dns_name }
}
output "efsnetids" {
  description = "Mount Target network IDs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.network_interface_id }
}
output "efsazids" {
  description = "Mount Target AZs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.availability_zone_id }
}

# give the IRSA role unconditional EFS-AP permissions
resource "aws_iam_policy" "efs_csi_unrestricted" {
  name = "efs-csi-unrestricted"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "elasticfilesystem:CreateAccessPoint",
        "elasticfilesystem:DeleteAccessPoint",
        "elasticfilesystem:DescribeAccessPoints",
        "elasticfilesystem:DescribeFileSystems",
        "elasticfilesystem:TagResource"
      ],
      Resource = "*"
    }]
  })
}


resource "aws_iam_role_policy_attachment" "efs_csi_extra_attach" {
  role       = module.efs_csi_irsa.iam_role_name
  policy_arn = aws_iam_policy.efs_csi_unrestricted.arn
}

module "efs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "EFS-CSI-IRSA"
  attach_efs_csi_policy = true # <─ correct policy for EFS

  oidc_providers = {
    efs = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}