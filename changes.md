# Changes

Reverse-chronological log of notable changes to this repository. Entries are
grouped by the commit on `main` that introduced them.

## c5da57e — 2026-05-19 — `feat(envs)`: per-environment tfvars (dev, staging, prod)

### Added
- `environments/dev.tfvars`, `environments/staging.tfvars`,
  `environments/prod.tfvars` — non-secret inputs consumed by the
  `terraform-apply` workflow via `-var-file=environments/<env>.tfvars`.
  Passwords and SSH key continue to come from GitHub env secrets via
  `TF_VAR_*` (never committed).

### Choices baked in
- Prefixes: `hubspkd` / `hubspks` / `hubspkp` (6–7 lowercase alnum).
- Shared CIDRs across envs (`10.0.0.0/16` hub, `10.1.0.0/16` spoke) —
  safe because each env has its own resource group + state file and
  the VNets do not peer cross-env.
- `enable_https = false` on all envs for the first apply: the workflow
  JIT-opens the **state SA** firewall but not Key Vault. Until a JIT KV
  path or private endpoint is in place, the security module would block
  apply. Flip to `true` once that path lands.
- `prod`: `enable_resource_locks = true`, `log_retention_in_days = 90`.
- `dev` / `staging`: locks off, retention 30 days.

### Changed
- `.gitignore` — keep root-level `*.tfvars` ignored (so the local dev
  override `terraform.tfvars` cannot be committed accidentally) but add
  an explicit `!environments/*.tfvars` exception so committed env files
  persist.

### Verified
- Local `terraform plan -var-file=environments/dev.tfvars` →
  `Plan: 47 to add, 0 to change, 0 to destroy` (uses the locally cached
  state — same state file the apply pipeline will use).

## b9ea3d7 — 2026-05-19 — `chore(ide)`: add `cspell.json`

### Added
- `cspell.json` — whitelist of Azure/Terraform/CI domain words
  (`vnet`, `appgw`, `azurerm`, `tfstate`, `oidc`, `rbac`, …) actually
  used in this repo, plus `ignorePaths` for `.terraform/`, `*.tfstate*`,
  `*.lock.hcl`, `*.sarif`, `*.pub`, `*.local`, `checkov-results/`.
- IDE-only config; no runtime / pipeline impact.

## 6b2248e — 2026-05-18 — OIDC: onboard `staging` and `prod` + runbook

### Added
- `docs/oidc-setup.md` — step-by-step runbook for onboarding a new
  environment: app/SP/federated credentials, RBAC, GitHub envs,
  identity + workload secrets, verification, and troubleshooting
  (failure modes carried over from PR #11).
- `README.md` — "Further reading" section linking the OIDC, remote-
  state, DevSecOps, and changes docs.

### Changed
- `scripts/oidc-grant-rbac.sh` — now also grants
  `Storage Account Contributor` at the state SA scope (the F2 JIT
  firewall toggle requires it). Output progress is `[1/3]…[3/3]`.
  Idempotent on existing assignments.
- `scripts/oidc-set-workload-secrets.sh` — accepts an `<env>`
  positional argument (defaults to `dev`); the SSH key path and
  passwords file follow `gh-tf-<env>-*`. The `<env>` and
  `<env>-apply` GitHub environments receive the secrets.

### Azure / GitHub side (out-of-tree, captured for the audit trail)
- App registration `gh-tf-staging` created with two federated
  credentials (`environment:staging`, `environment:staging-apply`).
- App registration `gh-tf-prod` created with two federated credentials
  (`environment:prod`, `environment:prod-apply`).
- Both SPs granted the three F2 roles: `Contributor` @ subscription,
  `Storage Blob Data Contributor` @ state container,
  `Storage Account Contributor` @ state SA.
- GitHub environments `staging`, `staging-apply`, `prod`, `prod-apply`
  created. Identity secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
  `AZURE_SUBSCRIPTION_ID`) seeded on each.

### Known limitation
- Required-reviewers / wait-timer protection rules on `staging-apply`
  and `prod-apply` are blocked by the GitHub free-plan billing
  restriction for private repos (HTTP 422). Tracked under Open items.

## (PR #11) — 2026-05-18 — OIDC + JIT state-SA firewall (F2), end-to-end

Smoke-tested on PR #11 (`ci/smoke-test-oidc` → `main`). Final state on
commit `4e16aa0`: `terraform plan` green with `Plan: 53 to add`,
artifact uploaded, SA firewall back to 1 rule (operator IP only). The
only red check is the orphan `cost estimate` workflow job (the
Infracost GitHub App itself posts the PR comment fine).

### Added
- `scripts/oidc-create-app.sh` — idempotent creator for `gh-tf-<env>`
  Azure AD app + service principal + two federated credentials (subjects
  `repo:mdixon47/terraform:environment:<env>` and `…:<env>-apply`).
- `scripts/oidc-grant-rbac.sh` — idempotent role grants:
  `Contributor` at subscription scope, `Storage Blob Data Contributor`
  on the state container, and `Storage Account Contributor` on the state
  SA (required to mutate `networkRuleSet` from the runner).
- `scripts/oidc-set-workload-secrets.sh` — provisions
  `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`, and `VM_ADMIN_SSH_PUBLIC_KEY`
  to the `dev` and `dev-apply` environments. Values are sent over stdin
  (never argv/logs). Optional `--save-passwords` flag writes them to
  `~/.ssh/gh-tf-dev-passwords.local` (0600) for out-of-band recovery.

### Changed
- `providers.tf` (`cd1f177`): documentation comment on the `azurerm`
  backend block noting the OIDC + JIT firewall flow; `use_azuread_auth`
  retained.
- `.github/workflows/terraform-ci.yml` (plan job) and
  `.github/workflows/terraform-apply.yml` (plan + apply jobs):
  1. **Job-level env** (`9f75ddc`): set `ARM_USE_OIDC=true`,
     `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` so the
     azurerm provider and backend use the federated identity instead of
     falling back to CLI-as-user auth.
  2. **JIT firewall** (`b11fbbc`, refined in `bd841f0`, `a10b02b`):
     between `azure/login` and `terraform init`, add the runner's egress
     IP to the SA `networkRuleSet`, wait for propagation, run TF, then
     `if: always()` remove the rule.
  3. **Stable-readiness probe** (`a10b02b`): the original `sleep 30`
     raced Azure Storage's multiple front-end IPs (rule propagation is
     per-front-end). Replaced with `az storage blob list --auth-mode
     login` against the state container, requiring **3 consecutive
     successes 5s apart** (≥15s dwell, capped at 180s total). Same auth
     path Terraform uses, so a pass guarantees both firewall propagation
     and RBAC are effective.
  4. **Init retry** (`a10b02b`): `terraform init` is wrapped in a
     3-attempt loop with 15s backoff (init is idempotent), catching the
     residual case where a healthy-during-probe front-end later 403s.

### Azure side (out-of-tree, captured here for the audit trail)
- App registration `gh-tf-dev` created with two federated credentials.
- SP `gh-tf-dev` granted the three roles above.
- GitHub environments `dev` and `dev-apply` created.
- Env-scoped secrets: `AZURE_{CLIENT_ID,TENANT_ID,SUBSCRIPTION_ID}` plus
  workload secrets `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`,
  `VM_ADMIN_SSH_PUBLIC_KEY`.
- Repo variables: `TFSTATE_RG`, `TFSTATE_SA`, `TFSTATE_CONTAINER`.

### Why F2 (vs. F1 / F3)
- **F1** (drop SA firewall, rely on Entra-ID-only auth) was simpler but
  removes a layer of network defense-in-depth.
- **F2** (this change) keeps `defaultAction = Deny` and adds only the
  current runner's IP for the duration of the job. ~45s probe + minor
  cleanup overhead per run.
- **F3** (self-hosted runner in the hub VNet with a private endpoint on
  the SA) is the long-term target but is a separate workstream.

### Why GitHub-hosted runner CIDR whitelisting is **not** viable
- `https://api.github.com/meta` returns ~6.5k CIDRs in `actions[]`.
- Azure Storage SA firewalls cap at **200** IP rules; service-tag
  whitelisting (`GitHubActions`) is not supported on SA firewalls.

### Failure modes encountered and resolved
- **`AADSTS90002` / "Tenant not found"** during initial federation —
  caused by hidden characters during manual secret entry. Resolved by
  re-setting via `gh secret set` over stdin.
- **`Authenticating using the Azure CLI is only supported as a User`**
  — provider/backend didn't pick up the OIDC token from
  `azure/login`'s CLI session. Fixed by setting the `ARM_*` env vars
  job-side (`9f75ddc`).
- **`Failed to get existing workspaces: 403 AuthorizationFailure`** —
  firewall propagation race. Fixed by the streak-probe approach
  (`a10b02b`).
- **`"admin_ssh_key.0.public_key" is not a complete SSH2 Public Key`**
  — initially ed25519 (rejected by the azurerm schema); then RSA but
  uploaded via `printf '%s' | gh secret set --body -`, which stripped a
  byte. Fixed by uploading the `.pub` directly via `gh secret set <
  file` (`4e16aa0` updates the helper script accordingly).

## 8e2c913 — 2026-05-18 — `build(deps)`: bump `hashicorp/setup-terraform` 3 → 4 (Dependabot #9)

### Changed
- `.github/workflows/terraform-ci.yml` (3 refs) and
  `.github/workflows/terraform-apply.yml` (1 ref): `setup-terraform@v3` →
  `@v4`. Node runtime bumps 20 → 24 with no input/output schema change.

### Verified
- All scanner checks (checkov, tfsec, terrascan, trivy config + fs,
  gitleaks) green on the rebased PR head.
- Post-merge `terraform-ci` workflow correctly skipped on `main` push
  (path filter `**/*.tf` — no Terraform code changed).
- `cost estimate` and `terraform plan` failures on the PR head are
  expected (Dependabot PRs run with `Secret source: Dependabot`, so the
  `INFRACOST_API_KEY` and Azure OIDC `client-id`/`tenant-id` secrets are
  not available). Same checks ran clean on the equivalent push to `main`
  prior to the Dependabot bump.

## 6709a2b — 2026-05-18 — `build(deps)`: bump `azure/login` 2 → 3 (Dependabot #5)

### Changed
- `.github/workflows/terraform-ci.yml` (1 ref) and
  `.github/workflows/terraform-apply.yml` (2 refs): `azure/login@v2` →
  `@v3`. Node runtime bumps 20 → 24; input schema unchanged.

### Verified
- 8/8 substantive checks green on the rebased PR head; 2 expected
  Dependabot-secret-restricted failures as above.

## e92068f — 2026-05-18 — `build(deps)`: bump `github/codeql-action` 3 → 4 (Dependabot #4)

### Changed
- `.github/workflows/security.yml` (5 refs): `codeql-action/upload-sarif@v3`
  → `@v4`. Steps are already `continue-on-error: true` (from `d3190c0`),
  so a regression cannot block CI. Node runtime bumps 20 → 24; API
  unchanged.

### Verified
- 5/5 checks green on the PR head; 8/8 substantive checks green on the
  post-merge `main` push.

## c2b13b2 — 2026-05-18 — `docs`: add `changes.md`

### Added
- `changes.md`: this file. Reverse-chronological log of all commits on
  `main`, grouped by type (Fixed / Changed / Added / Verified / Closed /
  Held / Open items).

## a5bf12b — 2026-05-18 — `fix(hub)`: static-keyed map for spoke route table associations

### Fixed
- `Invalid for_each argument` plan-time error on
  `module.hub.azurerm_subnet_route_table_association.spoke`. The `for_each`
  set was previously derived from `module.networking` subnet IDs that are
  `(known after apply)`, so Terraform could not determine instance keys at
  plan time. Switched to a `map(string)` keyed by stable names so addresses
  resolve to `...spoke["web"]` / `...spoke["app"]` deterministically.

### Changed
- `modules/hub/variables.tf`: renamed `spoke_subnet_ids_for_firewall_egress`
  (`list(string)`) → `spoke_subnet_associations` (`map(string)`), default
  `{}`.
- `modules/hub/main.tf`: `for_each = var.spoke_subnet_associations`
  (no `toset(...)` wrapper).
- `main.tf`: passes `{ web = …, app = … }` to the hub module.
- `terraform.tfvars.example`: documents HTTPS / Key Vault bootstrap inputs
  (`enable_https`, `kv_public_network_access_enabled`,
  `kv_allowed_ip_ranges`, `appgw_cert_subject`, `appgw_cert_dns_names`) so
  `terraform plan` succeeds out of the box.

### Verified
- `terraform fmt -recursive` clean.
- `terraform validate` → `Success! The configuration is valid.`
- `terraform plan` → `Plan: 53 to add, 0 to change, 0 to destroy.` (zero
  errors; 51 prior + 2 newly-resolvable route table associations).
- CI on `a5bf12b`: 8/8 substantive checks green (terraform fmt, validate,
  tflint, checkov, tfsec, terrascan, trivy config + fs, gitleaks).

## 74f6040 — 2026-05-17 — `docs(state)`: state-account hardening

### Added
- Blob versioning + 14-day blob/container soft-delete on
  `tfstate066541de13d8e2`.
- Storage-account firewall: `default-action Deny`, bypass `AzureServices,
  Logging, Metrics`, IPv4 allow-list `73.142.209.141/32`.
- `CanNotDelete` resource lock (`tfstate-rg-no-delete`) on `tfstate-rg`.
- `docs/remote-state.md` updated to reflect applied hardening and the
  CI-runner constraint introduced by the firewall (any future
  `terraform-apply` runner must be either on the allow-list or inside the
  VNet via private/service endpoint).

## 983a2d6 — 2026-05-17 — `docs(state)`: remote-state bootstrap + Dependabot triage

### Added
- `docs/remote-state.md`: end-to-end bootstrap procedure (RG, storage
  account creation, RBAC propagation, container, `terraform init` against
  the `azurerm` backend with `use_azuread_auth = true`).
- `backend.hcl.example`: template for the gitignored `backend.hcl`.
- `.gitignore` entries: `backend.hcl`, `*.backend.hcl`,
  `.tfstate-sa-name.local`, `*.local`.

### Closed (not merged)
- Dependabot PRs #1, #2, #3, #7, #10 (`azurerm` v3 → v4 — major migration
  deferred).
- Dependabot PR #8 (`trivy-action` 0.24 → 0.36 — superseded by explicit
  `0.35.0` pin in `d3190c0`).

### Held with comment
- Dependabot PR #6 (`actions/download-artifact` v4 → v8). Held pending the
  first successful `terraform-apply` round-trip; v8 changes the
  `digest-mismatch` default to `error` and migrates to ESM, which is worth
  validating against real artifacts.

## d3190c0 — 2026-05-17 — `ci(security)`: non-blocking SARIF upload + pinned trivy-action

### Fixed
- `github/codeql-action/upload-sarif` SARIF upload failures on a private
  repository (no Advanced Security entitlement). All five SARIF upload
  steps in `.github/workflows/security.yml` are now
  `continue-on-error: true`, so scanner output is captured as an artifact
  even when the upload step 403s.

### Changed
- `aquasecurity/trivy-action` pinned to `0.35.0` (was `master`) to make
  the security workflow deterministic across re-runs.

## 0e77db0 — 2026-05-17 — Initial commit

Initial import of the Azure hub-spoke reference architecture. Plans 51
resources across:

| Module | Resources |
|---|---|
| `hub` (Bastion, Firewall, App Gateway, Log Analytics, diagnostics) | 15 |
| `data` (SQL, storage, private endpoint, DNS zone) | 11 |
| `networking` (hub + spoke VNets, subnets, peering, route tables) | 10 |
| `spoke_compute` (web + app Linux VMs, NICs, NSGs) | 8 |
| `security[0]` (Key Vault + UAMI + TLS cert, gated by `enable_https`) | 6 |
| root (resource group) | 1 |

DevSecOps toolchain in CI:

- `terraform-ci.yml`: fmt, validate, tflint
- `security.yml`: checkov, tfsec, terrascan, trivy config + fs, gitleaks
- `terraform-apply.yml`: gated apply pipeline (not yet exercised
  end-to-end; depends on OIDC + a runner that satisfies the state-account
  firewall)

## Open items

- PR #6 (`download-artifact` v4 → v8): held pending first successful
  `terraform-apply` round-trip. v8 changes the `digest-mismatch` default
  from `warn` to `error` and migrates to ESM; worth validating against
  real artifacts before landing.
- **Gating posture on `*-apply` environments**.
  Current state: `wait_timer = 0`, `required_reviewers = 0`,
  `protected_branches = false` on all six envs (`dev`, `dev-apply`,
  `staging`, `staging-apply`, `prod`, `prod-apply`). Verified via
  `gh api /repos/mdixon47/terraform/environments/<env>`.
  - `required_reviewers` and `wait_timer` rules return HTTP 422 on the
    current plan because **environment protection rules on private repos
    require GitHub Pro / Team / Enterprise** (the repo is on the free
    plan). Tested directly: `gh api -X PUT … -F wait_timer=30` → 422
    "Failed to create the environment protection rule. Please ensure the
    billing plan supports the wait timer protection rule."
  - **Compensating control until that lands:** the `terraform-apply`
    workflow runs **only on `workflow_dispatch`** (no `push` /
    `pull_request` triggers), so the gate is the GitHub permission to
    trigger that workflow + select the environment. Only repo
    admins/maintainers can do that.
  - **When the plan is upgraded (or the repo is made public)**:
    add `required_reviewers` to each `*-apply` env (1 reviewer is
    enough for solo-maintainer flow; 2 for prod with a second pair of
    eyes). Optionally add `wait_timer` (e.g., 5 min on `prod-apply`).
- **Orphan `cost estimate` workflow job** — superseded by the Infracost
  GitHub App (which already posts PR comments). Either delete the job
  from `terraform-ci.yml` or set `INFRACOST_API_KEY` at repo scope.
- **PR #6 (`download-artifact` v4 → v8)** — held pending first
  successful `terraform-apply` round-trip. v8 changes the
  `digest-mismatch` default from `warn` to `error` and migrates to
  ESM; worth validating against real artifacts before landing.
