output "catalog_name" {
  value = module.unity_catalog_baseline.catalog_name
}

output "schema_name" {
  value = module.unity_catalog_baseline.schema_name
}

output "secret_scope_name" {
  value = module.workspace_baseline.secret_scope_name
}

output "cluster_policy_id" {
  value = module.workspace_baseline.cluster_policy_id
}

output "cluster_policy_name" {
  value = module.workspace_baseline.cluster_policy_name
}