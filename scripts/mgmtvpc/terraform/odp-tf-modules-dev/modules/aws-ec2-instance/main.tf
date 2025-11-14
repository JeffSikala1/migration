# Main EC2 Instance Configuration

resource "aws_instance" "this" {
  ami                         = var.ami
  instance_type               = var.instance_type
  hibernation                 = var.hibernation
  availability_zone           = var.availability_zone
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.vpc_security_group_ids
  key_name                    = var.key_name
  monitoring                  = var.monitoring  # Configurable monitoring
  get_password_data           = var.get_password_data
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = var.associate_public_ip_address

  # Resolve private_ip optional setting
  private_ip                  = var.private_ip != "" ? var.private_ip : null
  secondary_private_ips       = var.secondary_private_ips

  # Resolve ipv6_address_count vs ipv6_addresses conflict
  ipv6_address_count          = var.ipv6_addresses != [] ? null : var.ipv6_address_count
  ipv6_addresses              = var.ipv6_address_count > 0 ? [] : var.ipv6_addresses

  ebs_optimized               = var.ebs_optimized

  # Standard Tags
  tags = merge(var.tags, { 
    "FISMA_ID"        = var.fisma_id,
    "Organization"    = var.organization,
    "Tenant"          = var.tenant_name,
    "Environment"     = var.environment,
    "Patch_Group"     = var.patch_group,
    "module"          = "https://github.com/GSA/odp-tf-module-aws-ec2-instance"
  })

  # User data script to run the sectools registration script on instance startup
  user_data = <<-EOF
    #!/bin/bash
    sudo /build-artifacts/sectools-registration.sh \
      -r ${var.sec_tools_iam_role_arn} \
      -x ${var.external_id} \
      -f ${var.fisma_id} \
      -o ${var.organization} \
      -t ${var.tenant_name} \
      -e ${var.environment} \
      -p ${var.patch_group}
  EOF

  dynamic "cpu_options" {
    for_each = length(var.cpu_options) > 0 ? [var.cpu_options] : []

    content {
      core_count       = try(cpu_options.value.core_count, null)
      threads_per_core = try(cpu_options.value.threads_per_core, null)
    }
  }
  
  dynamic "capacity_reservation_specification" {
    for_each = length(var.capacity_reservation_specification) > 0 ? [var.capacity_reservation_specification] : []

    content {
      capacity_reservation_preference = try(capacity_reservation_specification.value.capacity_reservation_preference, null)

      dynamic "capacity_reservation_target" {
        for_each = try([capacity_reservation_specification.value.capacity_reservation_target], [])

        content {
          capacity_reservation_id                 = try(capacity_reservation_target.value.capacity_reservation_id, null)
          capacity_reservation_resource_group_arn = try(capacity_reservation_target.value.capacity_reservation_resource_group_arn, null)
        }
      }
    }
  }

  # Enforce encryption at rest for root block device (CIS, NIST best practices)
  dynamic "root_block_device" {
    for_each = var.root_block_device

    content {
      delete_on_termination = try(root_block_device.value.delete_on_termination, null)
      encrypted             = true # Ensure encryption at rest is enabled
      iops                  = try(root_block_device.value.iops, null)
      kms_key_id            = lookup(root_block_device.value, "kms_key_id", null)
      volume_size           = try(root_block_device.value.volume_size, null)
      volume_type           = try(root_block_device.value.volume_type, null)
      throughput            = try(root_block_device.value.throughput, null)
      tags                  = try(root_block_device.value.tags, null)
    }
  }

  # Ensure encryption for additional EBS volumes (best practice)
  dynamic "ebs_block_device" {
    for_each = var.ebs_block_device

    content {
      delete_on_termination = try(ebs_block_device.value.delete_on_termination, null)
      device_name           = ebs_block_device.value.device_name
      encrypted             = true # Ensure encryption at rest is enabled
      iops                  = try(ebs_block_device.value.iops, null)
      kms_key_id            = lookup(ebs_block_device.value, "kms_key_id", null)
      snapshot_id           = lookup(ebs_block_device.value, "snapshot_id", null)
      volume_size           = try(ebs_block_device.value.volume_size, null)
      volume_type           = try(ebs_block_device.value.volume_type, null)
      throughput            = try(ebs_block_device.value.throughput, null)
      tags                  = try(ebs_block_device.value.tags, null)
    }
  }

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device

    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = try(ephemeral_block_device.value.no_device, null)
      virtual_name = try(ephemeral_block_device.value.virtual_name, null)
    }
  }

  # Enable IMDSv2 for enhanced security (AWS Well-Architected Framework)
  dynamic "metadata_options" {
    for_each = length(var.metadata_options) > 0 ? [var.metadata_options] : []

    content {
      http_endpoint               = try(metadata_options.value.http_endpoint, "enabled")
      http_tokens                 = "required" # Enforce IMDSv2
      http_put_response_hop_limit = try(metadata_options.value.http_put_response_hop_limit, 1)
      instance_metadata_tags      = try(metadata_options.value.instance_metadata_tags, null)
    }
  }

  dynamic "network_interface" {
    for_each = var.network_interface

    content {
      device_index          = network_interface.value.device_index
      network_interface_id  = lookup(network_interface.value, "network_interface_id", null)
      delete_on_termination = try(network_interface.value.delete_on_termination, false)
    }
  }

  dynamic "private_dns_name_options" {
    for_each = length(var.private_dns_name_options) > 0 ? [var.private_dns_name_options] : []

    content {
      hostname_type                        = try(private_dns_name_options.value.hostname_type, null)
      enable_resource_name_dns_a_record    = try(private_dns_name_options.value.enable_resource_name_dns_a_record, null)
      enable_resource_name_dns_aaaa_record = try(private_dns_name_options.value.enable_resource_name_dns_aaaa_record, null)
    }
  }

  dynamic "launch_template" {
    for_each = length(var.launch_template) > 0 ? [var.launch_template] : []

    content {
      id      = lookup(var.launch_template, "id", null)
      name    = lookup(var.launch_template, "name", null)
      version = lookup(var.launch_template, "version", null)
    }
  }

  dynamic "maintenance_options" {
    for_each = length(var.maintenance_options) > 0 ? [var.maintenance_options] : []

    content {
      auto_recovery = try(maintenance_options.value.auto_recovery, null)
    }
  }

  # Enable Enclave Options for Nitro instances
  enclave_options {
    enabled = var.enclave_options_enabled
  }

  # Source Destination Check Disabled for NAT instances
  source_dest_check                    = length(var.network_interface) > 0 ? null : var.source_dest_check

  # Disable API Termination (prevents accidental deletion)
  disable_api_termination              = var.disable_api_termination

  # Disable API Stop (prevents stopping the instance via API)
  disable_api_stop                     = var.disable_api_stop

  # Instance shutdown behavior
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
  placement_group                      = var.placement_group
  tenancy                              = var.tenancy
  host_id                              = var.host_id

  credit_specification {
    cpu_credits = var.cpu_credits
  }

  # Timeout settings without `try()`
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  # Enable volume tags if necessary
  volume_tags = var.enable_volume_tags ? merge({ "Name" = var.name }, var.volume_tags) : null
}
