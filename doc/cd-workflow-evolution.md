# CD Workflow Evolution — Why We Needed Selective Deploy

> This document explains the limitations of the existing CD workflows, the real-world use cases where they fail, and how the two new selective deploy workflows solve those problems.

---

## Table of Contents

1. [Existing CD Workflows — Overview](#existing-cd-workflows--overview)
2. [The Problem — Use Cases Where They Fail](#the-problem--use-cases-where-they-fail)
3. [Solution — Two New Selective Deploy Workflows](#solution--two-new-selective-deploy-workflows)
4. [How Each New Workflow Works](#how-each-new-workflow-works)
5. [Before vs After — Side-by-Side](#before-vs-after--side-by-side)
6. [Feature Comparison Matrix](#feature-comparison-matrix)
7. [When to Use Which Workflow](#when-to-use-which-workflow)

---

## Existing CD Workflows — Overview

We have four CD workflows, each designed for a different trigger and scope:

| # | Workflow File | Trigger | What It Deploys | Flow |
|---|--------------|---------|-----------------|------|
| 1 | `CD-Workflow.yml` | Manual (PR number) | **Entire PR** — all files changed in that PR | stage → prod |
| 2 | `cd workflow release.yml` | Release published | **Entire release tag** — full codebase at that tag | stage → prod |
| 3 | `cd-workflow-param.yml` | Manual (folder names) | **Entire bundle folders** — e.g. `src_bundle,test_bundle` | stage → prod |
| 4 | `cd_workdlow_param2test.yml` | Manual (folder names) | Same as #3 but deploys each folder in an **isolated temp directory** | stage → prod |

### What They All Have in Common

- They deploy **everything** in the given scope — full PR, full release, or full folder
- They follow a fixed **stage → prod** pipeline
- They are **all-or-nothing** — no way to partially deploy

---

## The Problem — Use Cases Where They Fail

### Use Case 1: "I only want to deploy 2 out of 5 merged PRs"

**Scenario:**
Your team merged 5 PRs to `main` this week:
- PR #40 — New notebook for data ingestion ✅ (ready for prod)
- PR #41 — Updated job config ✅ (ready for prod)
- PR #42 — Experimental feature ❌ (NOT ready for prod)
- PR #43 — Bug fix in shared library ✅ (ready for prod)
- PR #44 — WIP pipeline changes ❌ (NOT ready for prod)

You want to deploy only PR #40, #41, and #43 to production, skipping #42 and #44.

**What happens with existing workflows:**

| Workflow | Can it solve this? | Why not? |
|----------|--------------------|----------|
| `CD-Workflow.yml` | ❌ No | Takes a single PR number — deploys that entire PR. You'd have to run it 3 times, and it still deploys from the PR's HEAD SHA which includes all prior merges to main. |
| `cd workflow release.yml` | ❌ No | Deploys the entire release tag — all 5 PRs would be included. |
| `cd-workflow-param.yml` | ❌ No | Deploys by folder name, not by PR. No concept of which PR changed what. |
| `cd_workdlow_param2test.yml` | ❌ No | Same limitation — folder-based, not PR-aware. |

**The core problem:** None of the existing workflows can **cherry-pick specific PRs** while skipping others. They all assume "deploy everything that's on main" or "deploy everything in this PR."

---

### Use Case 2: "A PR changed 10 files, but I only want to deploy 3 of them right now"

**Scenario:**
PR #50 was a large PR that changed files across multiple areas:
```
src/notebook/ingestion.py          ← ready to deploy
src/notebook/transform.py          ← ready to deploy
resources/jobs/daily_job.yml       ← ready to deploy
resources/jobs/weekly_job.yml      ← NOT ready (still testing)
src/shared/utils.py                ← NOT ready (dependency issue)
tests/test_ingestion.py            ← not needed in deploy
tests/test_transform.py            ← not needed in deploy
```

You want to deploy only the `src/notebook/` and `resources/jobs/daily_job.yml` changes now, and hold back the rest until next week.

**What happens with existing workflows:**

| Workflow | Can it solve this? | Why not? |
|----------|--------------------|----------|
| `CD-Workflow.yml` | ❌ No | Deploys the entire PR — all 10 files. No way to select specific paths. |
| `cd workflow release.yml` | ❌ No | Deploys the full release — even more files included. |
| `cd-workflow-param.yml` | ❌ No | Deploys entire folders like `src_bundle` — can't pick individual files or sub-paths within a PR. |
| `cd_workdlow_param2test.yml` | ❌ No | Same folder-level granularity. |

**The core problem:** None of the existing workflows support **file-level or path-level selective deployment** within a PR.

---

### Use Case 3: "We deployed to prod and something broke — what exactly was deployed?"

**Scenario:**
After a production deployment, a job starts failing. The team needs to know:
- What was the last known good state?
- What exactly changed since the last deploy?
- Can we deploy just a hotfix PR without including other unrelated changes?

**What happens with existing workflows:**

| Workflow | Can it solve this? | Why not? |
|----------|--------------------|----------|
| `CD-Workflow.yml` | ❌ No | No tracking of what was last deployed. No baseline concept. |
| `cd workflow release.yml` | ⚠️ Partial | Release tags give some traceability, but you can't selectively deploy a hotfix without creating a new release that includes everything. |
| `cd-workflow-param.yml` | ❌ No | No deployment tracking at all. |
| `cd_workdlow_param2test.yml` | ❌ No | No deployment tracking at all. |

**The core problem:** No workflow tracks a **"last deployed" baseline**, making it impossible to know the exact diff between what's deployed and what's on main.

---

### Use Case 4: "I want to preview what will be deployed before actually deploying"

**Scenario:**
Before deploying to production, you want to:
- See exactly which files will be affected
- Validate the bundle without actually deploying
- Get approval before proceeding

**What happens with existing workflows:**

| Workflow | Can it solve this? | Why not? |
|----------|--------------------|----------|
| `CD-Workflow.yml` | ❌ No | No dry-run option. Deploys immediately after validation. |
| `cd workflow release.yml` | ❌ No | Triggered automatically on release publish. No dry-run. |
| `cd-workflow-param.yml` | ❌ No | No dry-run option. |
| `cd_workdlow_param2test.yml` | ❌ No | No dry-run option. |

**The core problem:** None of the existing workflows have a **dry-run mode** to validate without deploying.

---

## Solution — Two New Selective Deploy Workflows

### Overview

| New Workflow | File | Solves |
|-------------|------|--------|
| **CD Selective Deploy (By PR)** | `cd-selective-deploy.yml` | Use Cases 1, 3, 4 — Cherry-pick specific PRs, baseline tracking, dry-run |
| **CD Path-Selective Deploy** | `cd-folder-selective-deploy.yml` | Use Cases 2, 3, 4 — Deploy specific file paths within a PR, phased rollout with approval, dry-run |

---

## How Each New Workflow Works

### Workflow 1: `cd-selective-deploy.yml` — Cherry-Pick PRs

**Purpose:** Deploy only specific merged PRs to an environment, skipping everything else.

**Inputs:**

| Input | Description | Example |
|-------|-------------|---------|
| `pr_numbers` | Comma-separated PR numbers to deploy | `40,41,43` |
| `target_env` | Target environment | `stage` or `prod` |
| `base_ref` | Optional custom baseline (SHA/tag/branch) | Leave empty for auto-detect |
| `dry_run` | Validate only, skip actual deploy | `true` / `false` |

**How it works step by step:**

```
Step 1: Resolve baseline
         │
         ├── If last-deployed-<env> tag exists → use that as baseline
         ├── If user provided base_ref → use that
         └── If neither → use initial commit (first-ever deploy)
         │
Step 2: Create temp branch from baseline
         │
Step 3: For each PR number provided:
         │
         ├── Validate PR is merged to main
         ├── Fetch all commits from that PR
         └── Cherry-pick those commits onto the temp branch
         │
Step 4: Show diff (what changed from baseline)
         │
Step 5: Terraform init → plan → apply (if prod)
         │
Step 6: databricks bundle validate → deploy
         │
Step 7: Tag HEAD as last-deployed-<env>
```

**Solving Use Case 1 — deploying PRs #40, #41, #43 only:**
```
Inputs:
  pr_numbers: "40,41,43"
  target_env: prod
  dry_run: false

Result:
  ✅ PR #40 cherry-picked and deployed
  ✅ PR #41 cherry-picked and deployed
  ✅ PR #43 cherry-picked and deployed
  ❌ PR #42 skipped (not in the list)
  ❌ PR #44 skipped (not in the list)
```

---

### Workflow 2: `cd-folder-selective-deploy.yml` — Path-Level Deploy

**Purpose:** Deploy only specific file paths from a PR, with optional phased rollout for remaining files.

**Inputs:**

| Input | Description | Example |
|-------|-------------|---------|
| `pr_number` | PR number to analyze | `50` |
| `deploy_paths` | Comma-separated paths to deploy now | `src/notebook,resources/jobs/daily_job.yml` |
| `target_env` | Target environment | `stage` or `prod` |
| `deploy_remaining` | Also deploy leftover files (with approval)? | `true` / `false` |
| `dry_run` | Validate only, skip actual deploy | `true` / `false` |

**How it works step by step:**

```
Phase 1: Analyze & Deploy Selected Paths
         │
Step 1:  Fetch all changed files from PR via GitHub API
         │
Step 2:  If deploy_paths is empty:
         │   → Show all changed files and exit
         │   → User re-runs with specific paths
         │
Step 3:  If deploy_paths is provided:
         │   → Split files into "deploy now" vs "remaining"
         │   → Match files against provided paths (exact or prefix)
         │
Step 4:  Deploy matched files:
         │   → Terraform init → plan → apply (if prod)
         │   → databricks bundle validate → deploy
         │
Step 5:  Tag HEAD as last-deployed-<env>
         │
Step 6:  Show summary (deployed files, remaining files)
         │
         ▼
Phase 2: Deploy Remaining (Optional, requires approval)
         │
         ├── Only runs if deploy_remaining = true
         ├── Requires separate environment approval gate
         └── Deploys all files NOT deployed in Phase 1
```

**Solving Use Case 2 — deploying only `src/notebook/` from PR #50:**

```
Run 1 (discovery mode):
  Inputs:
    pr_number: 50
    deploy_paths: ""          ← empty, just show files

  Output:
    Changed files in PR #50:
      src/notebook/ingestion.py
      src/notebook/transform.py
      resources/jobs/daily_job.yml
      resources/jobs/weekly_job.yml
      src/shared/utils.py
      tests/test_ingestion.py
      tests/test_transform.py

Run 2 (selective deploy):
  Inputs:
    pr_number: 50
    deploy_paths: "src/notebook,resources/jobs/daily_job.yml"
    deploy_remaining: false

  Result:
    ✅ Deployed: src/notebook/ingestion.py
    ✅ Deployed: src/notebook/transform.py
    ✅ Deployed: resources/jobs/daily_job.yml
    ⏸️ Remaining (not deployed):
       resources/jobs/weekly_job.yml
       src/shared/utils.py
       tests/test_ingestion.py
       tests/test_transform.py
```

---

## Before vs After — Side-by-Side

### Use Case 1: Deploy specific PRs only

| | Before (Existing Workflows) | After (`cd-selective-deploy.yml`) |
|---|---|---|
| **Action** | Deploy PR one at a time, but each deploys from main HEAD which includes ALL merged PRs | Cherry-pick only selected PRs onto last-deployed baseline |
| **Risk** | Unintended changes from other PRs get deployed | Only the PRs you specify are deployed |
| **Rollback** | No baseline tracking — unclear what was deployed before | `last-deployed-<env>` tag tracks exact state |
| **Dry run** | Not available | `dry_run: true` validates without deploying |

### Use Case 2: Deploy specific files from a PR

| | Before (Existing Workflows) | After (`cd-folder-selective-deploy.yml`) |
|---|---|---|
| **Action** | Deploy entire PR — all changed files | Specify exact paths/folders to deploy |
| **Granularity** | All-or-nothing | File-level and folder-level control |
| **Discovery** | No way to see what files a PR changed before deploying | Run with empty `deploy_paths` to preview all changed files |
| **Phased rollout** | Not possible | Deploy selected paths first, remaining later with approval gate |
| **Dry run** | Not available | `dry_run: true` validates without deploying |

### Use Case 3: Deployment tracking & hotfixes

| | Before (Existing Workflows) | After (Both New Workflows) |
|---|---|---|
| **Baseline tracking** | No concept of "last deployed state" | `last-deployed-<env>` git tag auto-updated after each deploy |
| **Diff visibility** | Unknown what changed since last deploy | Clear diff from baseline shown before deploy |
| **Hotfix deploy** | Must create new release or deploy full PR | Cherry-pick just the hotfix PR, skip everything else |

### Use Case 4: Preview before deploying

| | Before (Existing Workflows) | After (Both New Workflows) |
|---|---|---|
| **Dry run** | ❌ Not available on any workflow | ✅ `dry_run: true` on both new workflows |
| **File preview** | ❌ No way to see what will be deployed | ✅ Changed files listed before deploy |
| **Approval gates** | Only environment-level protection rules | Environment protection + separate remaining-files approval |

---

## Feature Comparison Matrix

| Feature | CD-Workflow | cd release | cd-param | cd-param2test | **cd-selective-deploy** | **cd-folder-selective-deploy** |
|---------|:-----------:|:----------:|:--------:|:-------------:|:----------------------:|:-----------------------------:|
| Deploy by PR number | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Deploy by release tag | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Deploy by folder name | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Cherry-pick specific PRs | ❌ | ❌ | ❌ | ❌ | **✅** | ❌ |
| Deploy specific file paths | ❌ | ❌ | ❌ | ❌ | ❌ | **✅** |
| Skip unready PRs | ❌ | ❌ | ❌ | ❌ | **✅** | ❌ |
| Skip unready files in a PR | ❌ | ❌ | ❌ | ❌ | ❌ | **✅** |
| Dry-run mode | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** |
| Baseline tracking (last-deployed tag) | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** |
| Preview changed files before deploy | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** |
| Phased rollout (deploy now + later) | ❌ | ❌ | ❌ | ❌ | ❌ | **✅** |
| Approval gate for remaining files | ❌ | ❌ | ❌ | ❌ | ❌ | **✅** |
| Terraform integration (prod) | ❌ | ✅ | ❌ | ❌ | **✅** | **✅** |
| Concurrency control | ❌ | ✅ | ❌ | ❌ | **✅** | **✅** |
| Deploy summary in GitHub | ❌ | ❌ | ❌ | ❌ | **✅** | **✅** |
| Custom base ref support | ❌ | ❌ | ❌ | ❌ | **✅** | ❌ |
| Isolated temp folder deploy | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |

---

## When to Use Which Workflow

| Scenario | Recommended Workflow |
|----------|---------------------|
| Deploy a single PR (all files) to stage → prod | `CD-Workflow.yml` |
| Deploy a tagged release to stage → prod | `cd workflow release.yml` |
| Deploy specific bundle folders (e.g. `src_bundle`) | `cd-workflow-param.yml` |
| Deploy specific bundle folders in isolation | `cd_workdlow_param2test.yml` |
| Deploy only certain merged PRs, skip others | **`cd-selective-deploy.yml`** ✨ |
| Deploy only certain files/paths from a PR | **`cd-folder-selective-deploy.yml`** ✨ |
| Hotfix: deploy one urgent PR without other changes | **`cd-selective-deploy.yml`** ✨ |
| Preview what a PR changed before deploying | **`cd-folder-selective-deploy.yml`** ✨ (empty deploy_paths) |
| Validate without deploying (dry run) | **Either new workflow** ✨ (dry_run: true) |
| Phased rollout: deploy critical paths first, rest later | **`cd-folder-selective-deploy.yml`** ✨ |

---

## Summary

The existing CD workflows work well for **straightforward, all-or-nothing deployments** — deploy a full PR, a full release, or a full folder. But real-world production environments need more control:

- **"Not everything on main is ready for prod"** → `cd-selective-deploy.yml` lets you cherry-pick only the PRs that are ready.
- **"This PR is too big to deploy all at once"** → `cd-folder-selective-deploy.yml` lets you deploy specific paths and hold back the rest.
- **"What exactly is deployed right now?"** → Both new workflows track the `last-deployed-<env>` baseline.
- **"Let me validate before I deploy"** → Both new workflows support `dry_run: true`.

Together, the two new workflows fill every gap left by the original four, giving the team **full control over what gets deployed, when, and how**.
