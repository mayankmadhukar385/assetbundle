module "unity_catalog_baseline" {
  source = "../../modules/unity_catalog_baseline"

  catalog_name          = var.catalog_name
  schema_name           = var.schema_name
  environment           = var.environment
  force_destroy_catalog = var.force_destroy_catalog
}

module "workspace_baseline" {
  source = "../../modules/databricks_workspace_baseline"

  environment         = var.environment
  secret_scope_name   = var.secret_scope_name
  engineers_group_name = var.engineers_group_name
  analysts_group_name  = var.analysts_group_name
  cluster_policy_name = var.cluster_policy_name

  default_node_type_id    = var.default_node_type_id
  min_workers             = var.min_workers
  max_workers             = var.max_workers
  default_workers         = var.default_workers
  autotermination_minutes = var.autotermination_minutes
}