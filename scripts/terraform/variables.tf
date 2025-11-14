variable "region" {
  type = string
  description = "AWS region"
  default = ""
}

variable "sandbox_bastion_s3" {
  description = "S3 sandbox bastion"
  type = string
  default = "sandbox-bastion-data"
}

variable "sandbox_bastion_s3_key_alias" {
  description = "KMS Key Alias for sandbox bastion S3 bucket"
  type = string
  default = "sandbox-bastion-data"
}

variable "iam_instance_profile" {
  description = "IAM instance profile to attach to the bastion host"
  type = string
  default = "null"
}