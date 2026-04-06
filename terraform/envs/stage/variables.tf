variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
}

variable "databricks_token" {
  description = "Databricks token"
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

variable "force_destroy_catalog" {
  description = "Whether catalog can be force destroyed"
  type        = bool
  default     = false
}

variable "secret_scope_name" {
  description = "Databricks secret scope name"
  type        = string
}

variable "engineers_group_name" {
  description = "Existing engineers group name"
  type        = string
}

variable "analysts_group_name" {
  description = "Existing analysts group name"
  type        = string
}

variable "cluster_policy_name" {
  description = "Cluster policy name"
  type        = string
}

variable "default_node_type_id" {
  description = "Default node type"
  type        = string
  default     = "i3.xlarge"
}

variable "min_workers" {
  description = "Minimum workers"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum workers"
  type        = number
  default     = 4
}

variable "default_workers" {
  description = "Default workers"
  type        = number
  default     = 2
}

variable "autotermination_minutes" {
  description = "Autotermination minutes"
  type        = number
  default     = 20
}