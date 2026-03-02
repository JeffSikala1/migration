# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "s-62d1150f116d4688b"


resource "aws_transfer_server" "conexussftp" {
  certificate                      = null
  directory_id                     = null
  domain                           = "EFS"
  endpoint_type                    = "PUBLIC"
  force_destroy                    = null
  function                         = null
  host_key                         = null # sensitive
  identity_provider_type           = "SERVICE_MANAGED"
  invocation_role                  = null
  logging_role                     = aws_iam_role.transferfamilyrole.arn
  post_authentication_login_banner = null # sensitive
  pre_authentication_login_banner  = null # sensitive
  protocols                        = ["SFTP"]
  security_policy_name             = "TransferSecurityPolicy-FIPS-2024-01"
  sftp_authentication_methods      = null
  structured_log_destinations      = []
  tags = {
    Name = "sftp.${var.dnsdomain}"
  }

  #url = ""
  protocol_details {
    as2_transports              = []
    passive_ip                  = "AUTO"
    set_stat_option             = "DEFAULT"
    tls_session_resumption_mode = "ENFORCED"
  }
}


#SFTP user configuration
resource "aws_transfer_user" "sftp_users" {
  for_each  = toset(var.sftpusers)
  user_name = each.value
  server_id = aws_transfer_server.conexussftp.id
  role      = aws_iam_role.transferfamilyrole.arn

  home_directory_type = "LOGICAL"
  //home_directory = "/${each.value}"  
  home_directory_mappings {
    entry  = "/"
    target = "/${aws_efs_file_system.efschroot.id}/${each.value}" # point each user to their EFS home directory
  }

  posix_profile {
    uid = index(var.sftpusers, each.value) + 1100
    gid = index(var.sftpusers, each.value) + 1100
  }

  tags = {
    Name = "${each.value}"
  }
}

#Create a EFS access point for each sftp user
resource "aws_efs_access_point" "sftpuser_access_points" {
  for_each       = toset(var.sftpusers)
  file_system_id = aws_efs_file_system.efschroot.id

  posix_user {
    uid = 1100 + index(var.sftpusers, each.value)
    gid = 1100 + index(var.sftpusers, each.value)
  }

  root_directory {
    path = "/${each.value}"
    creation_info {
      owner_uid   = 1100 + index(var.sftpusers, each.value)
      owner_gid   = 1100 + index(var.sftpusers, each.value)
      permissions = 750
    }
  }

  tags = {
    Name = "${each.value}"
  }
}

resource "aws_iam_role" "transferfamilyrole" {
  name               = "cnxs-transferfamily-sftp-role"
  description        = "The role for the Conexus Transfer family SFTP Users"
  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": {
"Effect": "Allow",
"Principal": {"Service": "transfer.amazonaws.com"},
"Action": "sts:AssumeRole"
}
}
EOF

  tags = {
    stack = "${var.dnsdomain}"
  }

}
