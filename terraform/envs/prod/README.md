# prod Terraform root

This Terraform root provisions the Databricks baseline for prod.

## Commands
terraform init
terraform validate
terraform plan
terraform apply

## Required auth
Set:
- TF_VAR_databricks_host
- TF_VAR_databricks_token