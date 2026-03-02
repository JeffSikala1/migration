resource "aws_security_group" "ingresssftpefs" {
   name = "ingresssftpefs"
   vpc_id = data.aws_vpc.vpc.id

   // Let NFS incoming
   ingress {
     description = "Security Group for letting in NFS requests"
     from_port = 2049
     to_port = 2049
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"] 
   }
   
   egress {
     description = "Out from NFS/EFS"     
     from_port = 0
     to_port = 0
     protocol = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }
   tags = {
     Name = "ingress_efs_sftp"
   }

}
# KMS Keys with alias
resource "aws_kms_key" "efskeychroot" {
  description             = "EFS Chroot SFTP KMS key"
  //deletion_window_in_days = 10 # Default 30
  //enable_key_rotation     = true # default false
  tags = merge(var.tags, local.kmstags, local.kmschroottag)
}
resource aws_kms_alias "kmsaliaschroot" {
  name          = "alias/efschroot"
  target_key_id = aws_kms_key.efskeychroot.key_id
}
resource "aws_kms_key" "efskeydatabase" {
  description             = "EFS Database KMS key"
  //deletion_window_in_days = 10 # Default 30
  //enable_key_rotation     = true # default false
  tags = merge(var.tags, local.kmstags, local.kmsdatabasetag)
}
resource aws_kms_alias "kmsaliasdatabase" {
  name          = "alias/efsdatabase"
  target_key_id = aws_kms_key.efskeydatabase.key_id
}
# EFS - NFS fileshares
resource "aws_efs_file_system" "efschroot" {
  creation_token = "Conexus SFTP Data"
  encrypted      = true
  kms_key_id     = aws_kms_key.efskeychroot.arn
  tags = merge(var.tags, local.efstags, local.efschroottag)  
  lifecycle {
    prevent_destroy = false
  }
}
resource "aws_efs_file_system" "efsquarantine" {
  creation_token = "Conexus SFTP reject"
  encrypted      = true
  kms_key_id     = aws_kms_key.efskeychroot.arn
  tags = merge(var.tags, local.efstags, local.efsquarantinetag)
  lifecycle {
    prevent_destroy = false
  }
}
resource "aws_efs_file_system" "efsdatabase" {
  creation_token = "Conexus SFTP Database"
  encrypted      = true
  kms_key_id     = aws_kms_key.efskeydatabase.arn
  tags = merge(var.tags, local.efstags, local.efsdatabasetag)
  lifecycle {
    prevent_destroy = false
  }
}
resource "aws_efs_file_system" "efsattachments" {
  creation_token = "Conexus Order attachments"
  encrypted      = true
  kms_key_id     = aws_kms_key.efskeydatabase.arn
  tags = merge(var.tags, local.efstags, local.efsattachmentstag)
  lifecycle {
    prevent_destroy = false
  }
}
resource "aws_efs_file_system" "efsreports" {
  creation_token = "Conexus UI Reports"
  encrypted      = true
  kms_key_id     = aws_kms_key.efskeydatabase.arn  
  tags = merge(var.tags, local.efstags, local.efsreportstag)
  lifecycle {
    prevent_destroy = false
  }
}



# EFS targets are per az not per subnet; the svcsubnetids variable contains all the azs
resource "aws_efs_mount_target" "efstargetchroot" {
  for_each = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efschroot.id
  subnet_id       = "${each.value}"
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetquarantine" {
  for_each = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsquarantine.id
  subnet_id       = "${each.value}"
  security_groups = [aws_security_group.ingresssftpefs.id]
}

resource "aws_efs_mount_target" "efstargetdatabase" {
  for_each = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsdatabase.id
  subnet_id       = "${each.value}"
  security_groups = [aws_security_group.ingresssftpefs.id]
}

resource "aws_efs_mount_target" "efstargetattachments" {
  for_each = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsattachments.id
  subnet_id       = "${each.value}"
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetreports" {
  for_each = var.svcsubnetids
  file_system_id  = aws_efs_file_system.efsreports.id
  subnet_id       = "${each.value}"
  security_groups = [aws_security_group.ingresssftpefs.id]
}

output "efsdatabasemtid" {
  description = "Database EFS mount target ids in each zone "
  value = { for k, v in aws_efs_mount_target.efstargetdatabase : k => v.id }
}

output "efschrootmtid" {
  description = "Chroot Mount Target IDs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.id }
}

output "efsdnsnames" {
  description = "Chroot Mount Target DNS names"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.dns_name }
}

output "efstargetdnsnames" {
  description = "Chroot Mount Target names"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.mount_target_dns_name }
}
output "efsnetids" {
  description = "Chroot Mount Target network IDs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.network_interface_id }
}
output "efsazids" {
  description = "Chroot Mount Target AZs"
  value       = { for k, v in aws_efs_mount_target.efstargetchroot : k => v.availability_zone_id }
}




