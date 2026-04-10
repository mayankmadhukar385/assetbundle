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

variable "force_destroy_catalog" {
  description = "Whether to force destroy catalog on delete"
  type        = bool
  default     = false
}