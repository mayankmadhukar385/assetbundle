variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
}

variable "databricks_token" {
  description = "Databricks PAT"
  type        = string
  sensitive   = true
}

variable "catalog_name" {
  description = "Unity Catalog catalog name"
  type        = string
}

variable "schema_name" {
  description = "Unity Catalog schema name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}