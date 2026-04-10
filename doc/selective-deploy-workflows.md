# Selective Deploy Workflows — Documentation

---

## 1. Background — The Problem

In a typical Databricks Asset Bundle project, multiple PRs get merged to `main` throughout the week. When it's time to deploy to staging or production, the team faces real-world challenges that standard CD workflows cannot handle:

**Problem 1 — All-or-Nothing PR Deployment**

Standard CD workflows deploy an entire PR or an entire release. There is no way to:
- Deploy only 3 out of 5 merged PRs (skipping the ones that aren't ready)
- Deploy a hotfix PR without dragging in other unrelated merged changes

*Example:* Five PRs merged this week — PR #40 (data ingestion), PR #41 (job config), PR #42 (experimental — not ready), PR #43 (bug fix), PR #44 (WIP — not ready). The team needs to deploy only #40, #41, and #43 to production. No existing workflow can do this.

**Problem 2 — No File-Level Control Within a PR**

A single PR can touch files across notebooks, jobs, shared libraries, and tests. Standard workflows deploy all changed files together. There is no way to:
- Deploy only the notebook changes now and hold back the job config changes
- Roll out changes in phases (critical paths first, remaining later)

*Example:* PR #50 changed 7 files across `src/notebook/`, `resources/jobs/`, `src/shared/`, and `tests/`. Only the notebook and one job file are ready. The rest need more testing.

**Problem 3 — No Deployment Baseline Tracking**

After a deployment, there is no record of what was last deployed. This makes it impossible to:
- Know the exact diff between what's live and what's on `main`
- Deploy a targeted hotfix without including everything else

**Problem 4 — No Dry-Run / Preview Capability**

There is no way to validate a deployment without actually deploying. Teams cannot:
- See which files will be affected before committing to a deploy
- Run a validation-only pass to catch issues early

---

## 2. Solution — Two New Workflows

Two new workflows were created to solve all four problems:

| Workflow | File | Purpose |
|----------|------|---------|
| CD Selective Deploy (By PR) | `cd-selective-deploy.yml` | Cherry-pick and deploy only specific merged PRs |
| CD Path-Selective Deploy | `cd-folder-selective-deploy.yml` | Deploy only specific file paths from a PR, with optional phased rollout |

Both workflows also introduce:
- **Baseline tracking** via `last-deployed-<env>` git tags
- **Dry-run mode** to validate without deploying
- **Deployment summaries** in GitHub Actions
- **Concurrency control** to prevent parallel deploys to the same environment

---

## 3. Workflow 1 — CD Selective Deploy (By PR)

**File:** `.github/workflows/cd-selective-deploy.yml`

### 3.1 What It Does

Takes a list of merged PR numbers, cherry-picks only those PRs onto the last-deployed baseline, and deploys the result. All other merged PRs on `main` are skipped.

### 3.2 Inputs

| Input | Required | Type | Description |
|-------|----------|------|-------------|
| `pr_numbers` | Yes | String | Comma-separated PR numbers to deploy (e.g. `40,41,43`) |
| `target_env` | Yes | Choice | Target environment — `stage` or `prod` |
| `base_ref` | No | String | Custom baseline SHA/tag/branch. Leave empty to auto-detect from `last-deployed-<env>` tag |
| `dry_run` | No | Boolean | If `true`, validates only — no actual deployment. Default: `false` |

### 3.3 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    RESOLVE BASELINE                          │
│                                                             │
│  Priority:                                                  │
│    1. User-provided base_ref (if given)                     │
│    2. last-deployed-<env> git tag (if exists)               │
│    3. Initial commit of the repo (first-ever deploy)        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              CREATE TEMP BRANCH FROM BASELINE                │
│                                                             │
│  git checkout -b temp-selective-deploy <baseline_sha>        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│            CHERRY-PICK EACH PR (in order)                    │
│                                                             │
│  For each PR number:                                        │
│    1. Validate PR is merged to main (abort if not)          │
│    2. Fetch all commits from that PR via GitHub API         │
│    3. Cherry-pick each commit onto the temp branch          │
│    4. Auto-resolve conflicts using "theirs" strategy        │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  SHOW CHANGES                                │
│                                                             │
│  git diff --name-only <baseline> HEAD                       │
│  git diff --stat <baseline> HEAD                            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    DEPLOY                                     │
│                                                             │
│  If target_env == prod:                                     │
│    → terraform init → plan → apply                          │
│                                                             │
│  Then:                                                      │
│    → databricks bundle validate --target <env>              │
│    → databricks bundle deploy --target <env>                │
│                                                             │
│  (Skipped if dry_run == true)                               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                TAG DEPLOYED STATE                             │
│                                                             │
│  git tag -f "last-deployed-<env>" HEAD                      │
│  git push origin "last-deployed-<env>" --force              │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 Example

**Scenario:** 5 PRs merged to main. Only #40, #41, #43 are ready for prod.

**Inputs:**
```
pr_numbers:  40,41,43
target_env:  prod
base_ref:    (empty — auto-detect)
dry_run:     false
```

**What happens:**
```
Baseline resolved: last-deployed-prod → commit abc1234

Cherry-picking:
  ✅ PR #40 — 2 commits applied
  ✅ PR #41 — 1 commit applied
  ✅ PR #43 — 3 commits applied

Skipped (not in list):
  ❌ PR #42
  ❌ PR #44

Files changed from baseline:
  src/notebook/ingestion.py
  resources/jobs/daily_job.yml
  src/shared/utils.py

Terraform: init → plan → apply ✅
Bundle: validate → deploy ✅

Tagged: last-deployed-prod → new HEAD
```

### 3.5 Validations & Safety

- Aborts if any specified PR is **not merged**
- Aborts if any PR targets a branch **other than main**
- Concurrency group prevents parallel deploys to the same environment
- Dry-run mode skips terraform apply and bundle deploy

---

## 4. Workflow 2 — CD Path-Selective Deploy

**File:** `.github/workflows/cd-folder-selective-deploy.yml`

### 4.1 What It Does

Takes a PR number and optional file/folder paths. Detects all changed files in that PR, deploys only the files matching the specified paths, and optionally deploys the remaining files in a second phase with a separate approval gate.

### 4.2 Inputs

| Input | Required | Type | Description |
|-------|----------|------|-------------|
| `pr_number` | Yes | String | PR number to analyze |
| `deploy_paths` | No | String | Comma-separated paths to deploy (e.g. `src/notebook,resources/jobs/daily_job.yml`). Leave empty to preview all changed files without deploying. |
| `target_env` | Yes | Choice | Target environment — `stage` or `prod` |
| `deploy_remaining` | No | Boolean | If `true`, deploys remaining files in Phase 2 (requires approval). Default: `false` |
| `dry_run` | No | Boolean | If `true`, validates only — no actual deployment. Default: `false` |

### 4.3 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│           PHASE 1 — ANALYZE & DEPLOY SELECTED PATHS          │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              DETECT ALL CHANGED FILES IN PR                   │
│                                                             │
│  Uses GitHub API: repos/<repo>/pulls/<pr>/files              │
│  Lists every file added, modified, or deleted in the PR     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │             │
            deploy_paths      deploy_paths
             is EMPTY          is PROVIDED
                    │             │
                    ▼             ▼
┌──────────────────────┐  ┌──────────────────────────────────┐
│  DISCOVERY MODE      │  │  FILTER FILES                     │
│                      │  │                                    │
│  Show all changed    │  │  For each changed file:            │
│  files and exit.     │  │    Does it match any deploy_path?  │
│                      │  │      YES → add to "deploy now"     │
│  User re-runs with   │  │      NO  → add to "remaining"      │
│  specific paths.     │  │                                    │
└──────────────────────┘  └──────────────┬─────────────────────┘
                                         │
                                         ▼
                          ┌──────────────────────────────────┐
                          │  DEPLOY MATCHED FILES             │
                          │                                    │
                          │  If target_env == prod:            │
                          │    → terraform init → plan → apply │
                          │                                    │
                          │  Then:                             │
                          │    → bundle validate → deploy      │
                          │                                    │
                          │  (Skipped if dry_run == true)      │
                          └──────────────┬─────────────────────┘
                                         │
                                         ▼
                          ┌──────────────────────────────────┐
                          │  TAG + SUMMARY                    │
                          │                                    │
                          │  Tag: last-deployed-<env>          │
                          │  Summary: deployed vs remaining    │
                          └──────────────┬─────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│     PHASE 2 — DEPLOY REMAINING (Optional, with approval)     │
│                                                             │
│  Only runs if:                                              │
│    • There ARE remaining files                              │
│    • deploy_remaining == true                               │
│    • Separate environment approval is granted               │
│                                                             │
│  Deploys all files NOT deployed in Phase 1                  │
│  Uses same terraform + bundle deploy steps                  │
└─────────────────────────────────────────────────────────────┘
```

### 4.4 Path Matching Logic

The `deploy_paths` input supports both exact file paths and folder prefixes:

| deploy_paths value | Matches |
|-------------------|---------|
| `src/notebook` | All files under `src/notebook/` (prefix match) |
| `src/notebook/ingestion.py` | Only that exact file |
| `src/notebook,resources/jobs` | All files under both folders |
| `resources/jobs/daily_job.yml` | Only that exact file |

### 4.5 Example — Two-Run Workflow

**Run 1 — Discovery Mode (preview changed files):**

```
Inputs:
  pr_number:    50
  deploy_paths: ""        ← empty
  target_env:   prod

Output:
  PR #50 — all changed files:
    src/notebook/ingestion.py
    src/notebook/transform.py
    resources/jobs/daily_job.yml
    resources/jobs/weekly_job.yml
    src/shared/utils.py
    tests/test_ingestion.py
    tests/test_transform.py

  → No deployment. Re-run with deploy_paths to deploy specific paths.
```

**Run 2 — Selective Deploy:**

```
Inputs:
  pr_number:        50
  deploy_paths:     "src/notebook,resources/jobs/daily_job.yml"
  target_env:       prod
  deploy_remaining: false
  dry_run:          false

Result:
  Deploying now:
    ✅ src/notebook/ingestion.py
    ✅ src/notebook/transform.py
    ✅ resources/jobs/daily_job.yml

  Remaining (not deployed):
    ⏸️ resources/jobs/weekly_job.yml
    ⏸️ src/shared/utils.py
    ⏸️ tests/test_ingestion.py
    ⏸️ tests/test_transform.py

  Terraform: init → plan → apply ✅
  Bundle: validate → deploy ✅
  Tagged: last-deployed-prod → HEAD
```

**Run 3 (optional) — Deploy Remaining with Approval:**

```
Inputs:
  pr_number:        50
  deploy_paths:     "src/notebook,resources/jobs/daily_job.yml"
  target_env:       prod
  deploy_remaining: true       ← triggers Phase 2
  dry_run:          false

Phase 1: deploys src/notebook + daily_job.yml (same as Run 2)
Phase 2: waits for approval → deploys remaining 4 files
```

### 4.6 Validations & Safety

- Aborts if PR has no changed files
- Discovery mode (empty `deploy_paths`) never deploys — safe to run anytime
- Phase 2 requires a **separate environment approval** (`<env>-remaining-approval`)
- Concurrency group prevents parallel deploys to the same environment
- Dry-run mode skips terraform apply and bundle deploy
- GitHub Step Summary shows exactly what was deployed and what remains

---

## 5. Key Features Introduced

| Feature | cd-selective-deploy | cd-folder-selective-deploy |
|---------|:-------------------:|:--------------------------:|
| Cherry-pick specific PRs | ✅ | — |
| Deploy specific file paths | — | ✅ |
| Discovery / preview mode | ✅ (shows diff) | ✅ (shows changed files) |
| Dry-run (validate only) | ✅ | ✅ |
| Baseline tracking (`last-deployed-<env>` tag) | ✅ | ✅ |
| Phased rollout (now + later) | — | ✅ |
| Approval gate for remaining files | — | ✅ |
| Terraform integration (prod) | ✅ | ✅ |
| Concurrency control | ✅ | ✅ |
| GitHub deploy summary | ✅ | ✅ |
| Custom base ref | ✅ | — |
| Conflict auto-resolution | ✅ | — |

---

## 6. When to Use Which

| I want to... | Use this workflow |
|-------------|-------------------|
| Deploy only certain merged PRs, skip the rest | `cd-selective-deploy.yml` |
| Deploy a hotfix PR without including other changes | `cd-selective-deploy.yml` |
| Deploy only specific files/folders from a PR | `cd-folder-selective-deploy.yml` |
| Preview what files a PR changed before deploying | `cd-folder-selective-deploy.yml` (empty deploy_paths) |
| Roll out changes in phases (critical first, rest later) | `cd-folder-selective-deploy.yml` (deploy_remaining: true) |
| Validate a deployment without actually deploying | Either workflow (dry_run: true) |
| Know what was last deployed to an environment | Either workflow (check `last-deployed-<env>` tag) |
