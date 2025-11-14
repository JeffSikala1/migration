/*

module "secrets_manager" {
  source       = "./secrets-manager-module"
  secret_name  = var.secret_name
  username     = var.master_username
  password     = var.master_password
  description  = "Aurora database credentials"
  tags         = var.tags
}

module "aurora_postgres" {
  source                  = "./aurora-postgres-module"
  vpc_id                  = data.aws_vpc.vpc.id 
  db_subnet_ids           = [for k,v in var.dbsubnetids: "${v}"]
  allowed_cidr_blocks     = ["0.0.0.0/0"] 
  db_cluster_name         = var.db_cluster_name
  secret_arn              = module.secrets_manager.secret_arn
  tags                    = var.tags
}

*/
