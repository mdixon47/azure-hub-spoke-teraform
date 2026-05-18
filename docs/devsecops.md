# DevSecOps Toolchain

This repository ships with a layered DevSecOps setup: **pre-commit** (developer
laptop) → **GitHub Actions CI** (every PR) → **GitHub Actions security**
(every PR + weekly schedule) → **Apply pipeline** (gated by GitHub
Environments). Findings flow into the GitHub **Security → Code scanning**
view via SARIF uploads.

## Layered controls

| Layer | Tool | Purpose | Where |
|---|---|---|---|
| Format | `terraform fmt` | Canonical formatting | pre-commit + `terraform-ci` |
| Static validity | `terraform validate` | HCL & schema sanity | pre-commit + `terraform-ci` |
| Lint | TFLint (`+ azurerm` ruleset) | Style & provider best-practice | pre-commit + `terraform-ci` |
| IaC security | tfsec | Policy-as-code scan, SARIF | `security.yml` |
| IaC security | Checkov | Broader IaC policy set, SARIF | `security.yml` + pre-commit |
| IaC security | Terrascan | OPA-based IaC scan | `security.yml` |
| Multi-purpose | Trivy (`config`, `fs`) | Misconfig + secrets + vulns | `security.yml` |
| Secrets | Gitleaks | Repo + commit history scan | `security.yml` + pre-commit |
| Cost | Infracost | PR cost diff | `terraform-ci` |
| Docs | terraform-docs | Auto-generates module READMEs | pre-commit |
| Deps | Dependabot | Updates providers & Actions | `.github/dependabot.yml` |

## Running locally

```bash
# One-time setup
brew install pre-commit terraform tflint tfsec checkov gitleaks trivy
pre-commit install
pre-commit install --hook-type commit-msg

# Run everything on demand
pre-commit run --all-files

# Targeted runs
terraform fmt -recursive -check -diff
terraform init -backend=false && terraform validate
tflint --recursive --config="$(pwd)/.tflint.hcl"
tfsec .
checkov -d . --config-file .checkov.yaml
trivy config .
gitleaks detect --config=.gitleaks.toml --redact
```

## Workflows

### `terraform-ci.yml` (PR + push to main)

Jobs:
1. `fmt` — `terraform fmt -check -recursive`
2. `validate` — `terraform init -backend=false && terraform validate`
3. `tflint` — recursive lint with the azurerm ruleset
4. `plan` — Azure OIDC login → `terraform plan` → uploads artifact
5. `infracost` — posts a sticky PR comment with cost delta

### `security.yml` (PR + push + weekly cron)

All scanners produce SARIF and upload to the GitHub Security tab, with one
`category:` per tool so findings don't collide.

| Job | Severity gate |
|---|---|
| `tfsec` | Reports all, does not fail build |
| `checkov` | `soft_fail: true` (governed by `.checkov.yaml`) |
| `trivy` (config + fs) | HIGH/CRITICAL only, no fail |
| `terrascan` | `only_warn: true` |
| `gitleaks` | Fails the build on any finding |

The "no fail" stance for scanners is intentional: results are tracked in the
Security tab, and the PR author/code-owner triages. Switch to hard-fail by
removing `soft_fail` / `exit-code` overrides per scanner.

### `terraform-apply.yml` (manual dispatch)

- Two jobs (`plan`, `apply`) running in two distinct GitHub Environments:
  `<env>` for plan and `<env>-apply` for apply.
- Configure the `*-apply` environments with **required reviewers** so that
  staging/prod cannot apply without human approval.
- Plan output is passed between jobs as an artifact; the apply job replays the
  exact plan binary.

## Required GitHub configuration

Create one **Environment** per target (`dev`, `staging`, `prod`) and one
`<env>-apply` per target with required reviewers. In each environment set:

| Type | Name | Purpose |
|---|---|---|
| Variable | `TFSTATE_RG` | Resource group holding the state SA |
| Variable | `TFSTATE_SA` | Storage account name for state |
| Variable | `TFSTATE_CONTAINER` | Blob container for state |
| Secret | `AZURE_CLIENT_ID` | OIDC federated app ID |
| Secret | `AZURE_TENANT_ID` | AAD tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Target subscription |
| Secret | `VM_ADMIN_PASSWORD` | Fallback when SSH key not used |
| Secret | `VM_ADMIN_SSH_PUBLIC_KEY` | Preferred VM auth |
| Secret | `SQL_ADMIN_PASSWORD` | Azure SQL admin |
| Secret | `INFRACOST_API_KEY` | Cost reporting (CI only) |

Use Azure **workload identity federation** for `AZURE_CLIENT_ID`; no long-lived
service-principal secret needed.

## Remote state bootstrap

The backend block in `providers.tf` requires a pre-existing Azure storage
account. Bootstrap once per organisation:

```bash
LOCATION=eastus
RG=tfstate-rg
SA=tfstate$RANDOM$RANDOM
CONTAINER=tfstate

az group create -n $RG -l $LOCATION
az storage account create -g $RG -n $SA -l $LOCATION \
  --sku Standard_GRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container create --account-name $SA -n $CONTAINER --auth-mode login
```

Record `$RG`, `$SA`, `$CONTAINER` as environment variables in GitHub.

## Findings triage workflow

1. Open PR → CI + security workflows run.
2. Reviewer opens **Security → Code scanning alerts** filtered by branch.
3. For each finding either:
   - Fix the code, or
   - Add a justified suppression in `.checkov.yaml` / inline `# tfsec:ignore:RULE_ID`.
4. Approve PR only when the alert list is empty or has documented dismissals.

## Pipeline diagram

```
  Developer  ──pre-commit──▶  Local fixes
       │
       ▼  git push
  ┌─────────────────────────────────────────────────────────┐
  │ GitHub PR                                                │
  │  ├── terraform-ci (fmt, validate, tflint, plan, cost)    │
  │  └── security (tfsec, checkov, trivy, gitleaks, terrascan)│
  └─────────────────────────────────────────────────────────┘
       │  approved + merged
       ▼
  workflow_dispatch ──▶ plan (env: dev) ──▶ apply (env: dev-apply, manual) ──▶ Azure
```
