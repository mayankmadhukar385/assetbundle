# Terraform Multi-Environment Architecture Guide

> A comprehensive guide covering three approaches to managing Terraform infrastructure across multiple environments (dev, uat, prod).

---

## Table of Contents

1. [Approach 1 — Parameterized (Single Root Module)](#approach-1--parameterized-single-root-module)
2. [Approach 2 — Separate Folder (Per Environment)](#approach-2--separate-folder-per-environment)
3. [Approach 3 — Metadata-Driven Code Generation](#approach-3--metadata-driven-code-generation)
4. [Comparison Table](#comparison-table)
5. [Advantages & Disadvantages](#advantages--disadvantages)
6. [When to Use Which Approach](#when-to-use-which-approach)

---

## Approach 1 — Parameterized (Single Root Module)

### What Is It?

A **single set of Terraform configuration files** (one root module) is shared across all environments. Environment-specific values are supplied through separate `.tfvars` files (e.g. `dev.tfvars`, `uat.tfvars`, `prod.tfvars`).

The CI/CD pipeline selects the appropriate `.tfvars` file at runtime using the `-var-file` flag or Terraform workspaces.

### How It Works

```
Developer pushes code
        │
        ▼
GitHub Actions CI/CD
  (Lint → Validate → Plan → Deploy)
        │
        ├── dev.tfvars   (env="dev",  instance="t3.micro")
        ├── uat.tfvars   (env="uat",  instance="t3.medium")
        └── prod.tfvars  (env="prod", instance="t3.large")
                │
                ▼
     Terraform Root Module (main.tf)
     ├── variables.tf
     ├── outputs.tf
     ├── providers.tf
     └── backend.tf
                │
        ┌───────┼───────┐
        ▼       ▼       ▼
    VPC Module  EC2 Module  RDS Module
        │       │       │
        └───────┼───────┘
                ▼
           AWS Cloud
```

### Folder Structure

```
project-root/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── backend.tf
├── envs/
│   ├── dev.tfvars
│   ├── uat.tfvars
│   └── prod.tfvars
└── modules/
    ├── vpc/
    ├── ec2/
    └── rds/
```

### Flow Summary

1. Developer pushes code / triggers workflow
2. CI/CD pipeline selects environment (dev / uat / prod)
3. Corresponding `.tfvars` file is loaded via `-var-file`
4. Root module reads variables and calls child modules
5. VPC, EC2, RDS modules provision resources in AWS
6. State is stored in remote backend (S3 + DynamoDB)

### Key Characteristics

| Aspect | Detail |
|--------|--------|
| **Config Files** | One shared set of `.tf` files |
| **Env Switching** | `-var-file=dev.tfvars` or Terraform workspaces |
| **State Isolation** | Via workspaces or distinct S3 backend keys |
| **Code Duplication** | Minimal — only `.tfvars` differ per env |

---

## Approach 2 — Separate Folder (Per Environment)

### What Is It?

Each environment (dev, uat, prod) has its **own dedicated folder** containing a full set of Terraform files (`main.tf`, `variables.tf`, `backend.tf`, etc.). Each folder independently calls shared reusable modules from a common `modules/` directory.

Because every environment has its own `backend.tf`, state files are **naturally isolated** — eliminating the risk of one environment accidentally modifying another's resources.

### How It Works

```
Developer pushes code
        │
        ▼
GitHub Actions CI/CD
  (Lint → Validate → Plan → Deploy)
        │
        ├── environments/dev/    → terraform apply
        ├── environments/uat/    → terraform apply
        └── environments/prod/   → terraform apply
                │
                ▼
        modules/ (shared)
        ├── vpc/
        ├── ec2/
        └── rds/
                │
                ▼
           AWS Cloud
```

### Folder Structure

```
project-root/
├── environments/
│   ├── dev/
│   │   ├── main.tf              # calls ../../modules/*
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── backend.tf           # unique S3 key: dev/terraform.tfstate
│   │   └── terraform.tfvars     # env="dev", instance="t3.micro"
│   ├── uat/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   ├── backend.tf           # unique S3 key: uat/terraform.tfstate
│   │   └── terraform.tfvars     # env="uat", instance="t3.medium"
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── backend.tf           # unique S3 key: prod/terraform.tfstate
│       └── terraform.tfvars     # env="prod", instance="t3.large"
└── modules/
    ├── vpc/
    ├── ec2/
    └── rds/
```

### Flow Summary

1. Developer pushes code / triggers workflow
2. CI/CD pipeline selects environment folder (dev / uat / prod)
3. `terraform init` & `terraform apply` runs **inside** that folder
4. Each folder has its own `backend.tf` (isolated state per env)
5. Each folder calls shared modules from `../../modules/`
6. VPC, EC2, RDS modules provision resources in AWS

### Key Characteristics

| Aspect | Detail |
|--------|--------|
| **Config Files** | Full set of `.tf` files per environment |
| **Env Switching** | `cd environments/dev && terraform apply` |
| **State Isolation** | Fully isolated — each folder has its own backend |
| **Code Duplication** | High — `.tf` files repeated across env folders |

---

## Approach 3 — Metadata-Driven Code Generation

### What Is It?

Instead of writing Terraform `.tf` files by hand, you define your infrastructure in a **simple metadata file (YAML/JSON)**, and a **code generator** (Python + Jinja2, Go, Jsonnet, etc.) reads that metadata and **automatically generates** the Terraform `.tf` files.

Developers **only edit the metadata** — never the generated `.tf` files. Think of it as a **"template engine for infrastructure"**.

```
metadata (YAML)  ──▶  generator script  ──▶  Terraform .tf files
```

### How It Works

```
Developer edits metadata/infrastructure.yaml
        │
        ▼
Code Generator (Python + Jinja2)
  1. Reads metadata YAML
  2. Loops through environments & services
  3. Renders .tf files from Jinja2 templates
  4. Outputs generated/ folder
        │
        ▼
generated/
├── dev/
│   ├── main.tf           (auto-generated)
│   ├── user-api-ec2.tf   (auto-generated)
│   ├── user-api-rds.tf   (auto-generated)
│   ├── order-api-ec2.tf  (auto-generated)
│   └── backend.tf        (auto-generated)
└── prod/
    ├── main.tf           (auto-generated)
    ├── user-api-ec2.tf   (auto-generated)
    └── backend.tf        (auto-generated)
        │
        ▼
GitHub Actions CI/CD
  Step 1: python generate.py
  Step 2: cd generated/<env>
  Step 3: terraform init → plan → apply
        │
        ▼
   AWS Cloud
```

### Folder Structure

```
project-root/
├── metadata/
│   └── infrastructure.yaml         ← developers edit ONLY this
├── templates/
│   ├── main.tf.j2                  ← Jinja2 Terraform templates
│   ├── ec2.tf.j2
│   ├── rds.tf.j2
│   ├── sg.tf.j2
│   ├── backend.tf.j2
│   └── providers.tf.j2
├── generate.py                     ← Python script that generates TF
├── generated/                      ← auto-generated (git-ignored)
│   ├── dev/
│   ├── uat/
│   └── prod/
└── modules/                        ← shared reusable modules
    ├── vpc/
    ├── ec2/
    └── rds/
```

### Metadata Example

```yaml
# metadata/infrastructure.yaml

project: boeing-asset-platform

environments:
  - name: dev
    region: us-east-1
    vpc_cidr: "10.0.0.0/16"
    services:
      - name: user-api
        instance_type: t3.micro
        db_engine: postgres
        db_instance_class: db.t3.micro
      - name: order-api
        instance_type: t3.micro
        db_engine: mysql
        db_instance_class: db.t3.micro

  - name: prod
    region: us-east-1
    vpc_cidr: "10.1.0.0/16"
    services:
      - name: user-api
        instance_type: t3.large
        db_engine: postgres
        db_instance_class: db.r5.large
      - name: order-api
        instance_type: t3.large
        db_engine: mysql
        db_instance_class: db.r5.large
```

### Flow Summary

1. Developer edits `metadata/infrastructure.yaml`
2. CI/CD runs `python generate.py` to produce `.tf` files
3. Pipeline selects environment folder (`generated/dev`, etc.)
4. `terraform init` → `plan` → `apply` inside that folder
5. Generated `.tf` files call shared `modules/`
6. State stored in remote backend (S3 + DynamoDB)

### Key Characteristics

| Aspect | Detail |
|--------|--------|
| **Config Files** | Auto-generated from YAML metadata + Jinja2 templates |
| **Env Switching** | `cd generated/dev && terraform apply` |
| **State Isolation** | Fully isolated — each generated folder has its own backend |
| **Code Duplication** | None — everything generated from single YAML |

### Tools That Use This Approach

| Tool | Description |
|------|-------------|
| **Terragrunt** | Wrapper that generates TF from config |
| **CDK for Terraform** | Write in Python/TypeScript → generates TF JSON |
| **Jsonnet** | Data templating language → generates JSON |
| **Pulumi** | General-purpose languages → generates IaC |
| **Custom (Jinja2)** | Python + Jinja2 (shown in this guide) |

---

## Comparison Table

| Criteria | Approach 1 — Parameterized | Approach 2 — Separate Folder | Approach 3 — Metadata Codegen |
|----------|---------------------------|------------------------------|-------------------------------|
| **Best For** | Small teams, simple infra | Strict env isolation needs | Large scale, many services |
| **Code Duplication** | ✅ Minimal | ❌ High | ✅ None |
| **Scalability** | Medium | Medium | Very High |
| **Complexity** | Low | Medium | High |
| **Env Isolation** | ❌ Workspace / backend keys | ✅ Full (own state per folder) | ✅ Full (own state per folder) |
| **Flexibility** | ❌ Limited | ✅ High | ✅ Very High |
| **Tooling Needed** | ✅ Terraform only | ✅ Terraform only | ❌ Terraform + Python/Jinja2 |
| **Learning Curve** | ✅ Low | ✅ Low | ❌ Medium-High |
| **Production Safety** | ❌ Risk if misconfigured | ✅ Safer (blast-radius control) | ✅ Safer (isolated folders) |
| **CI/CD Complexity** | ✅ Simple (one workflow) | ❌ More complex (per-folder) | ❌ Most complex (generate + apply) |
| **Rollback** | ❌ Affects all envs | ✅ Per-env rollback | ✅ Per-env rollback |
| **Team Scalability** | ❌ Merge conflicts likely | ✅ Parallel work per env | ✅ Parallel work per env |
| **Onboarding Speed** | ✅ Fast | ❌ Slower | ❌ Slowest |
| **Consistency** | ✅ Guaranteed (same code) | ❌ Manual effort needed | ✅ Enforced via templates |
| **Customization** | ❌ Needs conditionals | ✅ Easy per-env overrides | ✅ Template-level control |
| **Add New Service** | Edit `.tfvars` | Edit each env folder | Add YAML entry |
| **Add New Env** | New `.tfvars` file | Copy entire folder | Add YAML block |
| **State Management** | Workspaces or backend keys | Separate backend per folder | Separate backend per generated folder |

---

## Advantages & Disadvantages

### Approach 1 — Parameterized (Single Root Module)

#### ✅ Advantages

| # | Advantage | Details |
|---|-----------|--------|
| 1 | **Minimal Code Duplication** | Single set of `.tf` files shared across all environments. Only `.tfvars` files differ per environment. Bug fixes and updates apply to all environments at once. |
| 2 | **Easier Maintenance** | One place to update resource definitions. Reduces risk of configuration drift between environments. Smaller codebase to review and manage. |
| 3 | **Consistency Across Environments** | All environments use the exact same Terraform logic. Guarantees dev, uat, and prod are structurally identical. Easier to enforce standards and compliance. |
| 4 | **Faster Onboarding** | New team members learn one structure. Adding a new environment = just adding a new `.tfvars` file. Less cognitive overhead. |
| 5 | **Simpler CI/CD Pipeline** | One workflow with an environment input parameter. Pipeline logic is straightforward: `terraform plan -var-file=envs/<env>.tfvars` |
| 6 | **DRY Principle** | Follows software engineering best practices (Don't Repeat Yourself). Less code = fewer places for bugs to hide. |

#### ❌ Disadvantages

| # | Disadvantage | Details |
|---|-------------|--------|
| 1 | **Shared State Risk** | If workspace or `-var-file` is misconfigured, you could accidentally apply dev changes to prod. Requires strict CI/CD guardrails to prevent cross-env errors. |
| 2 | **Limited Environment Divergence** | Hard to have environment-specific resources (e.g., extra monitoring only in prod). Conditional logic (`count`, `for_each`) can make code complex. |
| 3 | **Blast Radius** | A bad change to `main.tf` affects ALL environments. No way to test a structural change in dev without it being available in prod code path. |
| 4 | **Complex Variable Management** | As environments grow, `.tfvars` files can become large. Difficult to manage environment-specific overrides cleanly. |
| 5 | **State File Management** | Requires Terraform workspaces or dynamic backend config to isolate state per environment. Workspace misuse can lead to state corruption. |
| 6 | **Harder Rollback** | Rolling back one environment means rolling back the shared code, which may affect other environments. |

---

### Approach 2 — Separate Folder (Per Environment)

#### ✅ Advantages

| # | Advantage | Details |
|---|-----------|--------|
| 1 | **Full Environment Isolation** | Each environment has its own directory and state file. Zero risk of accidentally applying to the wrong environment. Complete separation of concerns. |
| 2 | **Independent Deployments** | Can deploy dev without touching uat or prod. Each environment can be at a different version. Supports progressive rollout strategies. |
| 3 | **Environment-Specific Customization** | Easy to add resources only in certain environments (e.g., extra logging in prod, reduced infra in dev). No need for conditional logic or count hacks. |
| 4 | **Safer for Production** | Prod folder can have stricter review and approval gates. Changes can be tested in dev/uat folders first, then manually promoted to prod. Reduces accidental production impact. |
| 5 | **Independent State Management** | Each folder has its own `backend.tf`. No workspace confusion. State files are naturally isolated. |
| 6 | **Easier Rollback** | Can roll back one environment independently. Git history per folder makes it clear what changed where. |
| 7 | **Team Scalability** | Different teams can own different environment folders. Parallel development without merge conflicts. |

#### ❌ Disadvantages

| # | Disadvantage | Details |
|---|-------------|--------|
| 1 | **Code Duplication** | `main.tf`, `variables.tf`, `providers.tf` are repeated per env. Changes must be manually copied across all folders. Higher risk of environments drifting apart over time. |
| 2 | **Harder to Keep Environments in Sync** | A fix in `dev/` must be manually replicated to `uat/` and `prod/`. Easy to forget updating one environment. Requires discipline or automation to stay consistent. |
| 3 | **Larger Codebase** | More files to manage, review, and maintain. PR reviews become longer. Increased repository size. |
| 4 | **More Complex CI/CD** | Pipeline must know which folder to target. May need separate workflows or matrix strategies. More pipeline configuration to maintain. |
| 5 | **Slower Onboarding** | New developers must understand the folder convention. More files to navigate. Can be confusing if folders have diverged. |
| 6 | **Module Version Drift** | Different env folders might reference different module versions if not carefully managed. Can lead to inconsistent infrastructure. |

---

### Approach 3 — Metadata-Driven Code Generation

#### ✅ Advantages

| # | Advantage | Details |
|---|-----------|--------|
| 1 | **Massive Scale** | Manage hundreds of resources from a single YAML file. Adding 50 microservices = 50 entries in YAML, not 50 manual module blocks. |
| 2 | **Single Source of Truth** | The metadata file is the only input developers edit. Everything else is auto-generated. Easy to audit what's deployed. |
| 3 | **Consistency via Templates** | Jinja2 templates enforce standards across all resources. Changing a tag convention = update one template, regenerate all. |
| 4 | **Speed of Change** | Adding a new service = 5 lines of YAML. Adding a new environment = one YAML block. Run `python generate.py` and done. |
| 5 | **Reduced Human Error** | No manual `.tf` file editing. Generated code is deterministic and repeatable. Eliminates copy-paste mistakes. |
| 6 | **Great Auditability** | Easy to see what's deployed by reading the YAML. Metadata file serves as living documentation. |
| 7 | **Full Environment Isolation** | Each generated folder has its own `backend.tf`. State files are naturally isolated per environment. |

#### ❌ Disadvantages

| # | Disadvantage | Details |
|---|-------------|--------|
| 1 | **Extra Tooling Required** | Need Python, Jinja2 (or similar) installed in CI/CD pipeline. Additional dependencies to manage and maintain. |
| 2 | **Higher Learning Curve** | Team must understand both Terraform AND the template/generator system. Debugging requires knowledge of Jinja2 syntax + Terraform HCL. |
| 3 | **Debugging Complexity** | Errors may be in the template, not in the generated Terraform code. Stack traces can be harder to trace back to the root cause. |
| 4 | **Generated Code Review** | Auto-generated PRs are harder to review meaningfully. Reviewers must trust the templates rather than reading every generated line. |
| 5 | **Template Maintenance** | Templates become complex over time as requirements grow. Edge cases and conditionals accumulate in Jinja2 logic. |
| 6 | **Overkill for Small Projects** | Not worth the setup overhead for projects with fewer than 5 services. Adds unnecessary complexity for simple infrastructure. |
| 7 | **Harder Rollback** | Must regenerate from a previous YAML version. Rolling back means re-running the generator, not just reverting `.tf` files. |

---

## When to Use Which Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small project, 1–3 environments, few resources, small team | **Approach 1** — Parameterized |
| Rapid prototyping or POC with minimal setup | **Approach 1** — Parameterized |
| Strict compliance / audit needs, envs must be fully isolated | **Approach 2** — Separate Folder |
| Prod needs different config/resources than dev | **Approach 2** — Separate Folder |
| Regulated industry (finance, healthcare) with change control per env | **Approach 2** — Separate Folder |
| Many microservices (10+), multiple envs, need to scale fast | **Approach 3** — Metadata Codegen |
| Platform engineering team managing standardized patterns | **Approach 3** — Metadata Codegen |
| **Hybrid** — want isolation + less duplication | **Approach 2 + 3** — Separate folders generated from templates |

---

## Recommendation Summary

| Team / Project Size | Recommended |
|---------------------|-------------|
| **Small teams / simple infra** | Approach 1 — Parameterized |
| **Large teams / strict compliance** | Approach 2 — Separate Folder |
| **Platform teams / massive scale** | Approach 3 — Metadata Codegen |
| **Best of both worlds** | Hybrid — Separate folders that call shared modules, optionally generated from templates |

---

> **Tip:** You can combine approaches — for example, use **Approach 2** for folder isolation but add a lightweight **code generator** (Approach 3) to reduce duplication across env folders. This gives you the safety of isolation with the efficiency of automation.
