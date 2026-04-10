output "catalog_name" {
  description = "Created catalog name"
  value       = databricks_catalog.catalog.name
}

output "schema_name" {
  description = "Created schema name"
  value       = databricks_schema.schema.name
}