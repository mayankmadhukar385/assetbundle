variable "environment" {
  description = "Environment name"
  type        = string
}

variable "secret_scope_name" {
  description = "Name of the Databricks secret scope"
  type        = string
}

variable "engineers_group_name" {
  description = "Existing Databricks/IdP-synced group for engineers"
  type        = string
}

variable "analysts_group_name" {
  description = "Existing Databricks/IdP-synced group for analysts"
  type        = string
}

variable "cluster_policy_name" {
  description = "Name of the Databricks cluster policy"
  type        = string
}

variable "default_node_type_id" {
  description = "Default node type for clusters"
  type        = string
  default     = "i3.xlarge"
}

variable "min_workers" {
  description = "Minimum allowed workers"
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum allowed workers"
  type        = number
  default     = 4
}

variable "default_workers" {
  description = "Default number of workers"
  type        = number
  default     = 2
}

variable "autotermination_minutes" {
  description = "Auto termination in minutes"
  type        = number
  default     = 20
}