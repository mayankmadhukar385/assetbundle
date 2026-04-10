# Investigation: Terraform & Databricks Asset Bundles in DevOps

**Purpose**: Independent technical investigation into how Terraform and Databricks Asset Bundles (DAB) function, where their responsibilities begin and end, how they interact in a CI/CD pipeline, and what the production-grade design should look like for the Boeing DataStage-to-Databricks migration.

**This is NOT a description of the POC.** This is a first-principles analysis.

---

## 1. What Problem Are We Solving?

We are migrating ~500 DataStage jobs to Databricks on AWS. That means we need to:

1. **Provision infrastructure** — AWS networking, S3 buckets, IAM roles, Databricks workspaces, Unity Catalog objects, cluster policies, secret scopes
2. **Deploy workloads** — notebooks, jobs, DLT pipelines, workflow orchestrations into Databricks
3. **Do both repeatedly and safely** across dev, stage, and prod environments

No single tool does both well. That's why we need two tools working together.

---

## 2. Terraform — The Infrastructure Layer

### 2.1 What Terraform Actually Is

Terraform is a **declarative infrastructure provisioning tool**. You describe the desired end state, and Terraform figures out what to create, update, or destroy to reach that state.

Key mental model:
```
You write: "I want an S3 bucket named X with versioning enabled"
Terraform: "That bucket doesn't exist yet → I'll create it"
Next run:  "That bucket already exists and matches → no changes"
Next run:  "You changed the name → I'll destroy the old one and create a new one"
```

This is fundamentally different from scripting. Terraform maintains a **state file** that tracks what it has created, so it knows the difference between "this needs to be created" and "this already exists."

### 2.2 What Terraform Should Own in This Project

| Resource | Why Terraform |
|----------|---------------|
| S3 buckets (Bronze/Silver/Gold per env) | Infrastructure that exists before any workload runs |
| IAM roles & policies | Security boundary — must be auditable and version-controlled |
| Databricks workspace configuration | Workspace-level settings that don't change per deployment |
| Unity Catalog — catalogs & schemas | Data governance layer — must exist before jobs reference them |
| Cluster policies | Guardrails on compute — set once, enforced always |
| Secret scopes & ACLs | Security primitives — not workload-specific |
| Service Principals | Identity layer for CI/CD authentication |
| VPC / networking (if customer-managed) | Network foundation |
| DynamoDB table for state locking | Terraform's own infrastructure |
| CloudWatch log groups & dashboards | Monitoring infrastructure |

### 2.3 What Terraform Should NOT Own

| Resource | Why NOT Terraform |
|----------|-------------------|
| Databricks jobs | These change frequently with code — they are workloads, not infra |
| Notebooks | Application code — belongs in version control and deployed via DAB |
| DLT pipelines | Workload definitions that reference application code |
| Workflow orchestrations | Business logic that evolves with the application |
| Job schedules & triggers | Operational config tied to workload lifecycle |
| Cluster instances (ephemeral) | Created and destroyed by jobs — not persistent infra |

**The line is clear**: if it exists before any job runs and changes rarely, it's Terraform. If it changes with every code push and is tied to application logic, it's DAB.

### 2.4 Terraform State — The Most Critical Piece

Terraform state is the source of truth for what infrastructure exists. If the state is lost or corrupted, Terraform loses track of everything it created.

**Remote backend design (required for any team > 1 person):**

```
S3 bucket:  s3://boeing-terraform-state-<account-id>/
Key path:   env/<environment>/terraform.tfstate
DynamoDB:   boeing-terraform-locks (for state locking)
Encryption: AES-256 (SSE-S3) or KMS
Versioning: Enabled (allows state rollback)
```

**Why this matters for CI/CD:**
- Two pipeline runs must never apply Terraform simultaneously → DynamoDB lock prevents this
- State must survive pipeline runner destruction → S3 remote backend
- State must be recoverable → S3 versioning
- State contains sensitive values → encryption is mandatory

### 2.5 Terraform Module Architecture

The POC uses a **separate folder per environment** pattern with shared modules. This is the right choice for this project. Here's why and how it should be structured:

```
terraform/
├── envs/
│   ├── dev/
│   │   ├── main.tf          ← calls modules with dev-specific values
│   │   ├── providers.tf     ← Databricks + AWS provider config
│   │   ├── backend.tf       ← remote state config (unique key per env)
│   │   ├── variables.tf     ← variable declarations
│   │   └── terraform.tfvars ← dev-specific values
│   ├── stg/
│   │   └── (same structure)
│   └── prod/
│       └── (same structure)
├── modules/
│   ├── unity_catalog_baseline/    ← catalogs, schemas
│   ├── workspace_baseline/        ← secret scopes, cluster policies, groups
│   ├── s3_data_lake/              ← bronze/silver/gold buckets + policies
│   ├── iam_roles/                 ← service principals, cross-account roles
│   └── monitoring/                ← CloudWatch dashboards, alarms, SNS
```

**Why separate folders instead of workspaces or tfvars-only:**
- Each environment gets its own state file naturally — no workspace confusion
- Prod can have stricter approval gates in CI/CD without affecting dev
- Environments can temporarily diverge during testing without risk
- A bad Terraform change in dev cannot accidentally destroy prod

**Why shared modules:**
- Modules enforce consistency — dev and prod use the same resource definitions
- Bug fixes in a module propagate to all environments on next apply
- Module versioning (via Git tags) allows controlled promotion

### 2.6 Terraform Provider Authentication — The Enterprise Way

The POC uses `host` + `token` (PAT). This works for development but is not production-grade.

**Production authentication model:**

| Environment | Auth Method | Why |
|-------------|-------------|-----|
| Dev (local) | PAT or OAuth (developer's identity) | Convenience for iteration |
| CI pipeline | OIDC federation (GitHub → AWS → Databricks) | No stored secrets, short-lived tokens |
| CD pipeline | Service Principal + OAuth M2M | Machine identity, auditable, rotatable |

**OIDC flow for GitHub Actions → Databricks:**
```
GitHub Actions runner
  → assumes AWS IAM role via OIDC (no AWS keys stored)
  → IAM role has permissions to access Databricks
  → Databricks Service Principal authenticates via OAuth client credentials
  → Terraform uses Service Principal token
```

This eliminates long-lived PATs from GitHub Secrets entirely.

---

## 3. Databricks Asset Bundles (DAB) — The Workload Layer

### 3.1 What DAB Actually Is

DAB is a **deployment packaging and lifecycle tool** for Databricks workloads. Think of it as "Terraform for Databricks jobs and notebooks" — but purpose-built for the Databricks developer experience.

Key mental model:
```
You write: "I have a job called ingest_job that runs notebook X on schedule Y"
DAB:       "I'll create that job in the target workspace with the right config"
Next run:  "The notebook changed → I'll update the deployed copy"
Next run:  "You added a new task → I'll update the job definition"
```

DAB manages the **full lifecycle**: create, update, destroy — similar to Terraform but scoped to Databricks workloads.

### 3.2 What DAB Deploys

| Resource Type | Example |
|---------------|---------|
| Jobs (workflows) | Multi-task jobs with notebook/Python/JAR tasks |
| Notebooks | .ipynb or .py files synced to workspace |
| DLT Pipelines | Delta Live Tables pipeline definitions |
| Python wheel packages | Libraries built from src/ |
| ML models & experiments | MLflow model deployments |
| Schemas (via bundle resources) | DAB can also create schemas, but we delegate this to Terraform |

### 3.3 The databricks.yml Anatomy

```yaml
bundle:
  name: boeing-datastage-migration    # unique identifier

include:
  - resources/*.yml                   # job/pipeline definitions
  - resources/*/*.yml                 # nested resource definitions

variables:
  catalog:
    description: Target catalog name
  schema:
    description: Target schema name

targets:
  dev:
    mode: development                 # prefixes resources, pauses schedules
    default: true
    workspace:
      host: https://<dev-workspace>.cloud.databricks.com/
    variables:
      catalog: boeing_dev
      schema: bronze

  stg:
    mode: production
    workspace:
      host: https://<stg-workspace>.cloud.databricks.com/
      root_path: /Workspace/Shared/.bundle/${bundle.name}/${bundle.target}
    run_as:
      service_principal_name: sp-boeing-stg
    variables:
      catalog: boeing_stg
      schema: bronze

  prod:
    mode: production
    workspace:
      host: https://<prod-workspace>.cloud.databricks.com/
      root_path: /Workspace/Shared/.bundle/${bundle.name}/${bundle.target}
    run_as:
      service_principal_name: sp-boeing-prod
    variables:
      catalog: boeing_prod
      schema: bronze
```

### 3.4 Key DAB Concepts for Enterprise Use

**development vs production mode:**
- `development` → prefixes resource names with `[dev username]`, pauses all schedules, allows iterative deployment
- `production` → deploys resources as-is, schedules are active, requires `run_as` to be set (no human identity)

**run_as:**
- In production mode, DAB requires a `run_as` identity — this must be a Service Principal
- This means jobs run as a machine identity, not a human — critical for audit and security
- The Service Principal must be created by Terraform first

**root_path:**
- Controls where bundle artifacts are stored in the workspace filesystem
- Use `/Workspace/Shared/.bundle/...` for production — not under a user's personal folder
- The POC uses `/Workspace/Users/mayank.madhukar@pwc.com/...` — this must change for production

**Permissions:**
- DAB can set permissions on deployed resources (jobs, pipelines)
- Use AD groups, not individual users: `group_name: boeing-data-engineers` instead of `user_name: someone@pwc.com`

### 3.5 DAB Commands in CI/CD Context

| Command | When to Use | What It Does |
|---------|-------------|--------------|
| `databricks bundle validate --target <env>` | CI (on every PR) | Checks YAML syntax, variable resolution, resource references — no deployment |
| `databricks bundle deploy --target <env>` | CD (on release) | Creates/updates all resources in the target workspace |
| `databricks bundle run --target <env> <job_name>` | CD (optional) | Triggers a specific job after deployment — useful for smoke tests |
| `databricks bundle destroy --target <env>` | Manual/cleanup | Removes all resources deployed by the bundle — use with caution |

### 3.6 What DAB Does NOT Do

- Does not create Databricks workspaces
- Does not manage Unity Catalog metastore bindings
- Does not create IAM roles or S3 buckets
- Does not manage networking or VPC configuration
- Does not handle Terraform state or infrastructure drift detection

This is exactly why Terraform and DAB are complementary, not competing.

---

## 4. The Boundary — Where Terraform Ends and DAB Begins

This is the most important architectural decision in the entire DevOps design.

```
┌─────────────────────────────────────────────────────────────────┐
│                     TERRAFORM DOMAIN                             │
│                                                                  │
│  AWS Account Setup                                               │
│  ├── VPC, Subnets, Security Groups                              │
│  ├── S3 Buckets (bronze/silver/gold per env)                    │
│  ├── IAM Roles (cross-account, instance profiles)               │
│  ├── KMS Keys for encryption                                    │
│  └── DynamoDB (Terraform state lock)                            │
│                                                                  │
│  Databricks Account Setup                                        │
│  ├── Workspace creation (via account-level API)                 │
│  ├── Unity Catalog metastore + bindings                         │
│  ├── Catalogs and Schemas                                       │
│  ├── Service Principals + group memberships                     │
│  ├── Cluster Policies                                           │
│  ├── Secret Scopes + ACLs                                       │
│  ├── SQL Warehouses (if needed)                                 │
│  └── IP Access Lists / Private Link config                      │
│                                                                  │
├──────────────────── HANDOFF POINT ──────────────────────────────┤
│                                                                  │
│  Terraform outputs:                                              │
│  → workspace_url (per env)                                      │
│  → service_principal_client_id (per env)                        │
│  → catalog_name (per env)                                       │
│  → schema_names (per env)                                       │
│  → s3_bucket_arns (per env)                                     │
│                                                                  │
│  These values feed into DAB variables or CI/CD secrets          │
│                                                                  │
├──────────────────── HANDOFF POINT ──────────────────────────────┤
│                                                                  │
│                       DAB DOMAIN                                 │
│                                                                  │
│  Databricks Workload Deployment                                  │
│  ├── Jobs (multi-task workflows)                                │
│  ├── Notebooks (synced from Git)                                │
│  ├── DLT Pipelines                                              │
│  ├── Python wheel libraries                                     │
│  ├── Job schedules and triggers                                 │
│  ├── Job-level permissions                                      │
│  └── ML model serving endpoints (if applicable)                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**The handoff is one-directional**: Terraform creates the environment → DAB deploys into it. DAB never creates infrastructure. Terraform never deploys notebooks.

---

## 5. How They Work Together in CI/CD

### 5.1 The Execution Order

```
CI (on Pull Request):
  1. Lint Python code (pylint, ruff)
  2. Run unit tests (pytest)
  3. terraform fmt -check -recursive
  4. terraform validate (dev)
  5. terraform plan (dev) — show what WOULD change, don't apply
  6. databricks bundle validate --target dev
  7. ✅ All green → PR is mergeable

CD (on Release tag):
  For each environment (dev → stg → prod):
    1. terraform init
    2. terraform plan
    3. terraform apply    ← infrastructure is ready
    4. databricks bundle validate --target <env>
    5. databricks bundle deploy --target <env>  ← workloads deployed
    6. (optional) databricks bundle run --target <env> smoke_test_job
```

**Why this order matters:**
- Terraform must run first because DAB references catalogs, schemas, and workspace URLs that Terraform creates
- If Terraform fails, DAB should not run — the environment is not ready
- If DAB fails, Terraform changes are already applied — this is fine because infra is independent of workloads

### 5.2 Failure Scenarios and Recovery

| Failure Point | Impact | Recovery |
|---------------|--------|----------|
| Terraform plan fails | No changes made | Fix the Terraform code, re-run CI |
| Terraform apply fails mid-way | Partial infra created | Re-run apply — Terraform is idempotent, it will complete |
| Terraform apply succeeds, DAB validate fails | Infra is fine, workload config is broken | Fix bundle YAML, re-run CD |
| Terraform apply succeeds, DAB deploy fails | Infra is fine, old workload version still running | Fix and re-deploy, or re-tag previous release |
| DAB deploy succeeds but job fails at runtime | Everything deployed correctly, business logic error | Fix code, new release, redeploy |

### 5.3 The Idempotency Guarantee

Both tools are idempotent:
- Running `terraform apply` twice with the same config → no changes on second run
- Running `databricks bundle deploy` twice with the same code → no changes on second run

This means **re-running a failed pipeline is always safe**. You never need to manually clean up before retrying.

---

## 6. Enterprise Patterns — Beyond the POC

### 6.1 Separate Workspaces Per Environment (Critical)

The POC uses one workspace for all three targets. This is a **non-starter for production**.

**Why separate workspaces:**
- Blast radius isolation — a misconfigured dev job cannot access prod data
- Network isolation — prod workspace can be in a private subnet with no public access
- Compliance — auditors expect environment separation at the workspace level
- Cost attribution — per-workspace billing makes cost tracking straightforward
- Access control — dev workspace allows broad access; prod is locked to Service Principals

**Target architecture:**
```
Databricks Account
├── Workspace: boeing-dev    (https://boeing-dev.cloud.databricks.com)
├── Workspace: boeing-stg    (https://boeing-stg.cloud.databricks.com)
└── Workspace: boeing-prod   (https://boeing-prod.cloud.databricks.com)

Unity Catalog Metastore (shared across workspaces)
├── Catalog: boeing_dev    → bound to boeing-dev workspace
├── Catalog: boeing_stg    → bound to boeing-stg workspace
└── Catalog: boeing_prod   → bound to boeing-prod workspace
```

### 6.2 Service Principal Per Environment

Each environment should have its own Service Principal:

| SP Name | Used By | Permissions |
|---------|---------|-------------|
| sp-boeing-dev | CD pipeline (dev job) | Full access to dev workspace + dev catalog |
| sp-boeing-stg | CD pipeline (stg job) | Full access to stg workspace + stg catalog |
| sp-boeing-prod | CD pipeline (prod job) | Full access to prod workspace + prod catalog |

**Why per-environment SPs:**
- If the dev SP is compromised, prod is unaffected
- Audit logs clearly show which environment was accessed
- Permissions can be scoped precisely per environment

### 6.3 Terraform Output → DAB Input Bridge

Terraform creates resources. DAB needs to know about them. The bridge:

**Option A: CI/CD secrets (simple, recommended to start)**
```
Terraform outputs → stored as GitHub Environment Secrets → DAB reads via env vars
```

**Option B: Terraform output file (automated)**
```yaml
# In CD pipeline after terraform apply:
- name: Export Terraform outputs
  working-directory: terraform/envs/${{ env.TARGET }}
  run: |
    echo "WORKSPACE_HOST=$(terraform output -raw workspace_url)" >> $GITHUB_ENV
    echo "CATALOG_NAME=$(terraform output -raw catalog_name)" >> $GITHUB_ENV
```

**Option C: Shared parameter store (enterprise)**
```
Terraform writes outputs → AWS SSM Parameter Store
DAB pipeline reads from SSM before deploy
```

### 6.4 Drift Detection

**Terraform drift**: Run `terraform plan` on a schedule (e.g., nightly cron in GitHub Actions). If the plan shows changes, someone modified infrastructure outside Terraform → alert the team.

**DAB drift**: Harder to detect. If someone modifies a job in the Databricks UI, the next `bundle deploy` will overwrite it. Mitigation: restrict UI edit permissions in stg/prod to read-only for humans.

### 6.5 Handling the 500-Job Scale

With ~500 DataStage jobs to migrate, the bundle structure matters:

**Option A: Single monorepo bundle (simpler, start here)**
```yaml
# databricks.yml
include:
  - resources/jobs/**/*.yml
  - resources/pipelines/**/*.yml
```
All 500 jobs in one bundle. Deploy is all-or-nothing per environment.

**Option B: Multiple bundles by domain (scale later if needed)**
```
repo/
├── bundles/
│   ├── ingestion/
│   │   ├── databricks.yml
│   │   └── resources/
│   ├── transformation/
│   │   ├── databricks.yml
│   │   └── resources/
│   └── reporting/
│       ├── databricks.yml
│       └── resources/
```
Each domain deploys independently. More complex CI/CD but better isolation.

**Recommendation**: Start with Option A. Split into multiple bundles only if deploy times become unacceptable or teams need independent release cycles.

---

## 7. What the POC Got Right and What Needs to Change

### ✅ Good Decisions in the POC

| Decision | Why It's Good |
|----------|---------------|
| Separate Terraform folders per env | Proper isolation, independent state |
| Shared Terraform modules | DRY, consistent across environments |
| CI validates Terraform + DAB without applying | Correct separation of CI vs CD |
| Release-triggered CD | Controlled promotion, auditable |
| Concurrency controls on pipelines | Prevents parallel deploys |
| Tag verification (release from main only) | Prevents deploying unreviewed code |

### ❌ What Must Change for Production

| Current State | Production Requirement | Priority |
|---------------|----------------------|----------|
| Single workspace for all targets | Separate workspace per environment | **P0** |
| PAT-based authentication | Service Principal + OAuth / OIDC | **P0** |
| root_path under personal user folder | `/Workspace/Shared/.bundle/...` | **P0** |
| Permissions granted to individual email | Use AD groups / Service Principals | **P0** |
| No Terraform remote backend | S3 + DynamoDB remote state | **P0** |
| Stage job skips Terraform | All environments must run Terraform | **P1** |
| No smoke test after deploy | Add post-deploy validation job | **P1** |
| No drift detection | Scheduled Terraform plan + alerting | **P2** |
| No Terraform plan output in PR comments | Add plan output as PR comment for review | **P2** |
| No bundle deploy dry-run in PRs | Consider `bundle validate` output in PR | **P2** |

---

## 8. Security Considerations

### 8.1 Secrets Management

| Secret | Where to Store | How to Rotate |
|--------|---------------|---------------|
| Databricks SP client secret | GitHub Environment Secrets + AWS Secrets Manager | Rotate every 90 days via Terraform |
| AWS access keys | **Do not use** — use OIDC federation instead | N/A |
| Terraform state encryption key | AWS KMS (managed key) | Auto-rotated by KMS |
| Database connection strings | Databricks Secret Scope (created by Terraform) | Rotate via Terraform + secret scope update |

### 8.2 Least Privilege

- CI pipeline: read-only access (validate, plan — never apply)
- CD pipeline per env: write access only to that environment's workspace and state
- Developers: full access to dev, read-only to stg, no access to prod
- Service Principals: scoped to their environment's catalog and workspace

### 8.3 Audit Trail

Every deployment should be traceable:
```
Git commit SHA → Release tag → CD pipeline run → Terraform apply log → DAB deploy log
```
All of these are captured automatically by GitHub Actions + Terraform state + Databricks audit logs.

---

## 9. Decision Matrix — When to Use What

| Question | Answer |
|----------|--------|
| "I need to create an S3 bucket" | Terraform |
| "I need to create a Databricks catalog" | Terraform |
| "I need to deploy a notebook" | DAB |
| "I need to create a job that runs a notebook" | DAB |
| "I need to set a cluster policy" | Terraform |
| "I need to set job-level permissions" | DAB |
| "I need to create a secret scope" | Terraform |
| "I need to write a secret value" | Terraform (or CI/CD script) |
| "I need to create a Service Principal" | Terraform |
| "I need to set run_as on a job" | DAB |
| "I need to create a DLT pipeline" | DAB |
| "I need to create a SQL warehouse" | Terraform |
| "I need to schedule a job" | DAB |
| "I need to set up workspace IP access lists" | Terraform |

---

## 10. Summary

| Aspect | Terraform | DAB |
|--------|-----------|-----|
| **What** | Infrastructure provisioning | Workload deployment |
| **Scope** | AWS + Databricks platform resources | Databricks jobs, notebooks, pipelines |
| **State** | Remote state in S3 | Managed internally by Databricks |
| **Idempotent** | Yes | Yes |
| **Change frequency** | Rarely (infra changes are infrequent) | Often (every code release) |
| **Who triggers** | DevOps / Platform team | Development team (via release) |
| **Rollback** | Re-apply previous state or fix forward | Re-deploy previous release tag |
| **Auth model** | Provider config (SP, OIDC) | CLI config (SP, OAuth, PAT) |

**The bottom line**: Terraform builds the house. DAB moves the furniture in. You need both, in that order, every time.
