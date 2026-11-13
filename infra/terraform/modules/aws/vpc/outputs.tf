output "vpc_id" { value = module.vpc.vpc_id }
output "app_subnet_ids" { value = module.vpc.private_subnets }
output "data_subnet_ids" { value = module.vpc.database_subnets }
output "database_subnet_group" { value = module.vpc.database_subnet_group_name }
output "private_route_table_ids" { value = module.vpc.private_route_table_ids }
