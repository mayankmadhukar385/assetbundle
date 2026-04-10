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
| **Code Duplication** | Minimal | High | None |
| **Scalability** | Medium | Medium | Very High |
| **Complexity** | Low | Medium | High |
| **Env Isolation** | Workspace / backend keys | Full (own state per folder) | Full (own state per folder) |
| **Flexibility** | Limited | High | Very High |
| **Tooling Needed** | Terraform only | Terraform only | Terraform + Python/Jinja2 |
| **Learning Curve** | Low | Low | Medium-High |
| **Add New Service** | Edit `.tfvars` | Edit each env folder | Add YAML entry |
| **Add New Env** | New `.tfvars` file | Copy entire folder | Add YAML block |
| **State Management** | Workspaces or backend keys | Separate backend per folder | Separate backend per generated folder |

---

## Advantages & Disadvantages

### Approach 1 — Parameterized (Single Root Module)

| ✅ Advantages | ❌ Disadvantages |
|---------------|-----------------|
| One set of `.tf` files — DRY codebase | Shared state risk if misconfigured |
| Minimal code duplication | Needs workspace or `-var-file` to switch envs |
| Easy to maintain & update | All envs share same TF code — can't diverge per env |
| Quick to set up | Accidental apply to wrong env if workspace not set correctly |
| Low learning curve | Limited flexibility for env-specific overrides |

### Approach 2 — Separate Folder (Per Environment)

| ✅ Advantages | ❌ Disadvantages |
|---------------|-----------------|
| Full isolation per environment | Code duplication across env folders |
| Independent state per folder | Harder to keep envs in sync when modules change |
| Can diverge configs per environment | More files to manage overall |
| Safer for production workflows (blast-radius control) | Adding a new resource means updating every env folder |
| Easy to understand structure | Drift between envs if not carefully managed |

### Approach 3 — Metadata-Driven Code Generation

| ✅ Advantages | ❌ Disadvantages |
|---------------|-----------------|
| Massive scale — manage 100s of resources from one YAML | Extra tooling needed (Python, Jinja2) in CI/CD pipeline |
| Single source of truth (metadata file) | Higher learning curve — team must understand templates |
| Templates enforce consistency across all resources | Debugging harder — errors may be in template, not in TF |
| Adding a new service = a few lines of YAML | Generated code harder to review in PRs |
| Reduced human error — no manual `.tf` file editing | Templates become complex over time as requirements grow |
| Great auditability — easy to see what's deployed from YAML | Overkill for small projects with fewer than 5 services |

---

## When to Use Which Approach

| Scenario | Recommended Approach |
|----------|---------------------|
| Small project, 1–3 environments, few resources, small team | **Approach 1** — Parameterized |
| Strict compliance / audit needs, envs must be fully isolated, prod needs different config than dev | **Approach 2** — Separate Folder |
| Many microservices (10+), multiple envs, need to scale fast, platform engineering team | **Approach 3** — Metadata Codegen |
| Rapid prototyping or POC with minimal setup | **Approach 1** — Parameterized |
| Regulated industry (finance, healthcare) with change control per env | **Approach 2** — Separate Folder |
| Standardized platform with repeatable patterns across teams | **Approach 3** — Metadata Codegen |

---

> **Tip:** You can also combine approaches — for example, use **Approach 2** for folder isolation but add a lightweight **code generator** to reduce duplication across env folders.
