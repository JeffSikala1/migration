variable "secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
}

variable "username" {
  description = "The database username to store in the secret"
  type        = string
}

variable "password" {
  description = "The database password to store in the secret"
  type        = string
  sensitive   = true
}

variable "description" {
  description = "The description of the secret"
  type        = string
  default     = "Database credentials"
}

variable "tags" {
  description = "A map of tags to add to the secret"
  type        = map(string)
  default     = {}
}

variable "master_username" {
  description = "Username of the DB super user"
  type = string
  default = "postgres"
}
