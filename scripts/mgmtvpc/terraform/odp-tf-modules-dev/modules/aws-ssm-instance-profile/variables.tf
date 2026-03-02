variable "role_name" {
  description = "The name of the IAM Role for SSM"
  type        = string
  default     = "GSA_ISE_SSM_Instance_Profile_Role"
}

variable "instance_profile_name" {
  description = "The name of the IAM Instance Profile for SSM"
  type        = string
  default     = "GSA_ISE_SSM_Instance_Profile"
}

variable "assume_role_arn" {
  description = "The ARN of the role that the EC2 instance should assume"
  type        = string
}

variable "external_id" {
  description = "The External ID to use when assuming the role"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "secrets_account_id" {
  description = "The AWS Account ID of the Secrets Account"
  type        = string
}
