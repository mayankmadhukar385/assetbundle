resource "databricks_catalog" "catalog" {
  name          = var.catalog_name
  comment       = "Managed by Terraform for ${var.environment}"
  force_destroy = false
}

resource "databricks_schema" "schema" {
  catalog_name = databricks_catalog.catalog.name
  name         = var.schema_name
  comment      = "Managed by Terraform for ${var.environment}"
}