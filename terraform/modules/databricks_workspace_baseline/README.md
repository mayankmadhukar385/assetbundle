# databricks_workspace_baseline

This module creates shared Databricks workspace controls for an environment:

- secret scope
- secret ACLs
- cluster policy
- permissions on the cluster policy

## Important
This module assumes group names already exist in Databricks or are synced from your enterprise identity provider.

## Inputs
- environment
- secret_scope_name
- engineers_group_name
- analysts_group_name
- cluster_policy_name
- default_node_type_id
- min_workers
- max_workers
- default_workers
- autotermination_minutes

## Outputs
- secret_scope_name
- cluster_policy_id
- cluster_policy_name