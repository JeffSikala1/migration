#######################################
#              Required               #
#######################################

# Name tag for the EC2 instance
variable "name" {
  description = "Name tag for the instance"
  type        = string
}

# AMI ID for the EC2 instance
variable "ami" {
  description = "AMI ID for the EC2 instance"
  type        = string
}

# Subnet ID where the EC2 instance will be launched
variable "subnet_id" {
  description = "The subnet ID in which to launch the instance"
  type        = string
}

# List of security group IDs to assign to the instance
variable "vpc_security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

##########################################
#  Security Tools Registration Variables #
##########################################

# IAM role ARN for security tools (-r)
variable "sec_tools_iam_role_arn" {
  description = "IAM Role ARN for security tools"
  type        = string
}

# External ID (-x)
variable "external_id" {
  description = "External-id to assume the role"
  type        = string
}

# FISMA ID (-f)
variable "fisma_id" {
  description = "GSA FISMA ID of the system"
  type        = string
}

# Organization (-o)
variable "organization" {
  description = "GSA Organization of the system"
  type        = string
}

# Tenant Name (-t)
variable "tenant_name" {
  description = "GSA Tenant Name of the system"
  type        = string
}

# Environment (-e)
variable "environment" {
  description = "Environment of this EC2 instance (e.g., dev, prod)"
  type        = string
}

# Patch Group (-p)
variable "patch_group" {
  description = "GSA Patch Group - (Optional) - Defaults to #DONOTPATCH"
  type        = string
  default     = "#DONOTPATCH"  # Optional: default value can be set
}

#########################################
#  Security Requirement / Best Practice #
#########################################

# Enable detailed monitoring for the EC2 instance
variable "monitoring" {
  description = "Enable monitoring for the instance"
  type        = bool
  default     = true
}

# Whether to associate a public IP address with the instance
variable "associate_public_ip_address" {
  description = "Associate a public IP address with the instance"
  type        = bool
  default     = false
}

# Retrieve Windows password for the instance
variable "get_password_data" {
  description = "Retrieve Windows password for the instance"
  type        = bool
  default     = false
}

# Enable hibernation for the EC2 instance
variable "hibernation" {
  description = "Enable hibernation for the instance"
  type        = bool
  default     = false
}

# Disable API termination to prevent accidental termination
variable "disable_api_termination" {
  description = "If true, enables EC2 termination protection"
  type        = bool
  default     = false
}

# Disable API stop to prevent stopping the instance via API calls
variable "disable_api_stop" {
  description = "If true, prevents stopping the instance via API calls"
  type        = bool
  default     = false
}

# Whether to encrypt EBS block devices
variable "root_block_device" {
  description = "Configuration block for the root block device"
  type        = list(object({
    delete_on_termination = bool
    encrypted             = bool
    iops                  = number
    kms_key_id            = string
    volume_size           = number
    volume_type           = string
    throughput            = number
    tags                  = map(string)
  }))
  default = []
}

# Additional EBS block devices to attach to the instance
variable "ebs_block_device" {
  description = "Additional EBS block devices to attach to the instance"
  type        = list(object({
    delete_on_termination = bool
    device_name           = string
    encrypted             = bool
    iops                  = number
    kms_key_id            = string
    snapshot_id           = string
    volume_size           = number
    volume_type           = string
    throughput            = number
    tags                  = map(string)
  }))
  default = []
}

# Metadata service options to enforce best practices (IMDSv2)
variable "metadata_options" {
  description = "EC2 instance metadata options"
  type        = list(object({
    http_endpoint               = string
    http_tokens                 = string
    http_put_response_hop_limit = number
    instance_metadata_tags      = string
  }))
  default = []
}

# CPU options for the EC2 instance (core count and threads per core)
variable "cpu_options" {
  description = "CPU options for the instance"
  type        = object({
    core_count       = number
    threads_per_core = number
  })
  default = {
    core_count       = null  # Example default value
    threads_per_core = null  # Example default value
  }
}

#######################################
#          Consumer Optional          #
#######################################

# Instance type for the EC2 instance (e.g., t3.micro, t2.large)
variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.micro"
}

# SSH key pair name for SSH access to the instance
variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = ""
}

# Availability zone where the EC2 instance will be launched (Optional)
variable "availability_zone" {
  description = "The availability zone to launch the instance in"
  type        = string
  default     = null
}

# IAM instance profile to associate with the EC2 instance
variable "iam_instance_profile" {
  description = "IAM instance profile to associate with the instance"
  type        = string
  default     = ""
}

# Private IP address to associate with the instance
variable "private_ip" {
  description = "Private IP address to associate with the instance"
  type        = string
  default     = ""
}

# List of secondary private IP addresses to assign to the instance (optional)
variable "secondary_private_ips" {
  description = "List of secondary private IP addresses to assign to the instance"
  type        = list(string)
  default     = []
}

# Number of IPv6 addresses to associate with the instance
variable "ipv6_address_count" {
  description = "Number of IPv6 addresses to associate"
  type        = number
  default     = 0
}

# List of IPv6 addresses to associate with the instance
variable "ipv6_addresses" {
  description = "List of IPv6 addresses to associate"
  type        = list(string)
  default     = []
}

# Enable EBS optimization for the instance
variable "ebs_optimized" {
  description = "Whether the instance is EBS-optimized"
  type        = bool
  default     = false
}

# User data to configure the instance
variable "user_data" {
  description = "User data to configure the instance"
  type        = string
  default     = ""
}

# Whether to create a spot instance instead of an on-demand instance
variable "create_spot_instance" {
  description = "Whether to create a spot instance instead of an on-demand instance"
  type        = bool
  default     = false
}

# Capacity reservation specification for the instance
variable "capacity_reservation_specification" {
  description = "Describes an instance's Capacity Reservation targeting option"
  type        = any
  default     = {}
}

# Ephemeral (instance store) volumes for the EC2 instance
variable "ephemeral_block_device" {
  description = "Configuration block for ephemeral (instance store) volumes"
  type        = list(object({
    device_name  = string
    no_device    = bool
    virtual_name = string
  }))
  default = []
}

# Source/Destination check to control if traffic is routed to/from the instance
variable "source_dest_check" {
  description = "Controls if traffic is routed to/from the instance (used in NAT instances)"
  type        = bool
  default     = true
}

# Placement group for the EC2 instance
variable "placement_group" {
  description = "The placement group the instance belongs to"
  type        = string
  default     = ""
}

# Tenancy of the instance (default, dedicated, host)
variable "tenancy" {
  description = "The tenancy of the instance (default, dedicated, host)"
  type        = string
  default     = "default"
}

# Host ID for dedicated tenancy
variable "host_id" {
  description = "The host ID for the instance (used for dedicated tenancy)"
  type        = string
  default     = ""
}

# Enclave options for Nitro Enclaves
variable "enclave_options_enabled" {
  description = "Whether Nitro Enclaves are enabled"
  type        = bool
  default     = false
}

# CPU credits for burstable instances (e.g., T3 instances)
variable "cpu_credits" {
  description = "The credit option for CPU usage (standard or unlimited)"
  type        = string
  default     = "standard"  # Default to "standard", can be "unlimited"
}

# Enable volume tagging for the instance
variable "enable_volume_tags" {
  description = "Whether to enable volume tagging"
  type        = bool
  default     = false
}

# Tags to apply to EBS volumes
variable "volume_tags" {
  description = "Tags to apply to EBS volumes"
  type        = map(string)
  default     = {}
}

# Tags for the instance
variable "tags" {
  description = "Additional tags for the instance"
  type        = map(string)
  default     = {}
}

# Optional: Network Interface Configuration
variable "network_interface" {
  description = "Configuration for network interfaces"
  type        = list(object({
    device_index          = number
    network_interface_id  = string
    delete_on_termination = bool
  }))
  default = []
}

# Optional: Private DNS Name Options
variable "private_dns_name_options" {
  description = "Private DNS name options for the instance"
  type        = list(object({
    hostname_type                        = string
    enable_resource_name_dns_a_record    = bool
    enable_resource_name_dns_aaaa_record = bool
  }))
  default = []
}

# Optional: Launch Template Configuration
variable "launch_template" {
  description = "Configuration block for EC2 instance launch template"
  type        = list(object({
    id      = string
    name    = string
    version = string
  }))
  default = []
}

# Optional: Maintenance Options Configuration
variable "maintenance_options" {
  description = "Configuration block for maintenance options"
  type        = list(object({
    auto_recovery = string
  }))
  default = []
}

# Optional: Instance Initiated Shutdown Behavior
variable "instance_initiated_shutdown_behavior" {
  description = "Shutdown behavior for the instance (stop or terminate)"
  type        = string
  default     = "stop"
}

# Optional: Timeouts for creating, updating, and deleting the instance
variable "timeouts" {
  description = "Timeout settings for create, update, and delete actions"
  type = object({
    create = string
    update = string
    delete = string
  })
  default = {
    create = "10m"  # Wait up to 10 minutes for creation
    update = "10m"  # Wait up to 10 minutes for updates
    delete = "10m"  # Wait up to 10 minutes for deletion
  }
}
