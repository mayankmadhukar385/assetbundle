output "secret_scope_name" {
  description = "Created secret scope name"
  value       = databricks_secret_scope.shared.name
}

output "cluster_policy_id" {
  description = "Created cluster policy ID"
  value       = databricks_cluster_policy.job_policy.id
}

output "cluster_policy_name" {
  description = "Created cluster policy name"
  value       = databricks_cluster_policy.job_policy.name
}