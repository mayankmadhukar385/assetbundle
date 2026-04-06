# Add workspace-level baseline resources here later.
# Examples:
# - databricks_secret_scope
# - databricks_group
# - databricks_permissions
# - databricks_cluster_policy

resource "databricks_secret_scope" "shared" {
  name = var.secret_scope_name
}

resource "databricks_secret_acl" "engineers_manage_scope" {
  principal  = var.engineers_group_name
  scope      = databricks_secret_scope.shared.name
  permission = "MANAGE"
}

resource "databricks_secret_acl" "analysts_read_scope" {
  principal  = var.analysts_group_name
  scope      = databricks_secret_scope.shared.name
  permission = "READ"
}

resource "databricks_cluster_policy" "job_policy" {
  name = var.cluster_policy_name

  definition = jsonencode({
    "spark_version" = {
      "type"  = "fixed",
      "value" = "auto:latest-lts"
    },
    "node_type_id" = {
      "type"         = "unlimited",
      "defaultValue" = var.default_node_type_id
    },
    "num_workers" = {
      "type"         = "range",
      "minValue"     = var.min_workers
      "maxValue"     = var.max_workers
      "defaultValue" = var.default_workers
    },
    "autotermination_minutes" = {
      "type"   = "fixed",
      "value"  = var.autotermination_minutes
      "hidden" = true
    }
  })
}

resource "databricks_permissions" "cluster_policy_usage" {
  cluster_policy_id = databricks_cluster_policy.job_policy.id

  access_control {
    group_name       = var.engineers_group_name
    permission_level = "CAN_USE"
  }

  access_control {
    group_name       = var.analysts_group_name
    permission_level = "CAN_USE"
  }
}