module "workspace_baseline" {
  count = (
    var.secret_scope_name != null &&
    var.engineers_group_name != null &&
    var.analysts_group_name != null &&
    var.cluster_policy_name != null
  ) ? 1 : 0

  source = "../../modules/databricks_workspace_baseline"

  providers = {
    databricks = databricks
  }

  environment             = var.environment
  secret_scope_name       = var.secret_scope_name
  engineers_group_name    = var.engineers_group_name
  analysts_group_name     = var.analysts_group_name
  cluster_policy_name     = var.cluster_policy_name
  default_node_type_id    = var.default_node_type_id
  min_workers             = var.min_workers
  max_workers             = var.max_workers
  default_workers         = var.default_workers
  autotermination_minutes = var.autotermination_minutes
}