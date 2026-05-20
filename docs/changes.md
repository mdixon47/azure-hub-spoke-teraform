# Changes

Reverse-chronological log of notable changes to this repository. Entries are
grouped by the commit on `main` that introduced them.

## (pending) — 2026-05-19 — `fix(ci)`: remove redundant infracost workflow job (PR #21)

### Problem
The `cost estimate` job in `terraform-ci.yml` failed on every PR with
`INFRACOST_API_KEY is not set` (exit code 1). Although `continue-on-error: true`
prevents it from blocking the run, it still shows as a red ✗ in the PR checks
UI — noise that makes real failures harder to spot. The Infracost GitHub App
already posts cost-estimate comments to PRs via its own OAuth token; the
workflow job is completely redundant.

### Fixed
Removed the entire `infracost` job (all steps: `actions/checkout`,
`infracost/actions/setup`, `infracost breakdown`, `infracost comment github`)
from `.github/workflows/terraform-ci.yml`. Also removed the "Orphan cost
estimate" open item from this file.

---

## 738d8dd — 2026-05-19 — `fix`: prevent `InUseSubnetCannotBeDeleted` on `terraform destroy` (PR #20)

### Problem
`terraform destroy` raced the deletion of spoke NICs against spoke subnet
deletion, producing:

```
InUseSubnetCannotBeDeleted: Subnet web-subnet is in use by
…/networkInterfaces/HUBSPKD-WEB-NIC/ipConfigurations/INTERNAL
```

**Root cause 1 — implicit cross-module dependency is resource-level only.**
`module.spoke_compute` references subnet IDs from `module.networking`, giving
Terraform resource-to-resource edges. On destroy, Terraform reverses those
edges, but with `parallelism=10` it can begin subnet deletion at the same time
as (or immediately after) NIC deletion rather than waiting for all
`spoke_compute` resources to finish first.

**Root cause 2 — Azure control-plane eventual consistency.** The NIC DELETE
API returns 200 before the subnet's internal reference table is updated, so a
subnet DELETE attempted within seconds of a successful NIC DELETE still sees
the NIC as "in use".

### Fixed

**`main.tf`** — added `depends_on = [module.networking]` to `module.spoke_compute`:
this creates an explicit module-level fence. On destroy Terraform now fully
tears down every resource in `spoke_compute` (NICs, NSG associations, VMs)
before touching any resource in `networking` (subnets, VNet, peering). Without
the explicit fence Terraform's resource-level parallelism can race the two
modules during the destroy phase.

**`.github/workflows/terraform-destroy.yml`** — wrapped `terraform destroy` in
a 3-attempt retry loop (30s between attempts). The state file is re-read each
attempt so only remaining resources are retried. This absorbs Azure's eventual-
consistency window if the NIC-to-subnet reference hasn't cleared before the
first destroy attempt starts.

### Verified — PR #20
- `terraform plan` (CI): ✓ in 1m10s, no errors

---

## 78bc418 — 2026-05-19 — `fix(ci)`: replace IP-probe SA firewall pattern with `defaultAction` toggle (PR #18)

### Problem
The JIT firewall probe loop (detect runner IP → add IP rule → probe until propagation → remove
rule) fails on GitHub-hosted runners when egress to `blob.core.windows.net` uses IPv6. Azure
Storage IP allowlist rules only accept IPv4 CIDRs, so the registered IP never matches and all
72 probes return *"The request may be blocked by network rules of storage account"*. A prior
attempt to force IPv4 via `sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1` (PR #17 commit
`98cf536`) resolved one run but was unreliable across different runner allocations.

### Fixed
All three workflow files (`terraform-ci.yml`, `terraform-apply.yml`, `terraform-destroy.yml`):
replaced the four-step IP probe pattern with a simpler open / restore toggle:

- **Open** (before `terraform init`): `az storage account update --default-action Allow`
- **Restore** (`if: always()` cleanup): `az storage account update --default-action Deny`

Entra ID authentication is still required on every storage request; no anonymous access is
possible during the ~1–2 minute open window. The `|| true` on the restore step prevents a
failed cleanup from masking a real job failure.

### Verified — PR #18, run `26129544500`
- `terraform plan`: ✓ in 48s — no SA firewall error
- All checks (fmt, validate, tflint, security scanners) green

---

## 97e406b — 2026-05-19 — `fix(ci)`: SA firewall diagnostics, checkov suppressions, CI fixes (PR #17)

Commits: `346b828` → `4a711d5` → `3f464a8` → `9512007` → `98cf536`

### Fixed — checkov false positives (`346b828`)
`.checkov.yaml`: two new suppressions with documented justification:
- `CKV_AZURE_33`: blob SA has no queue workload; queue logging on the general SA is configured
  via a separate `azurerm_storage_account_queue_properties` resource that checkov 3.2.527 does
  not resolve — false positive on both SAs.
- `CKV_AZURE_216`: `threat_intelligence_mode = "Deny"` is correctly set on
  `azurerm_firewall_policy` (required by azurerm v4); checkov 3.2.527 still inspects
  `azurerm_firewall`, which no longer carries this attribute in v4 — false positive.

Local result after suppression: **51 passed / 0 failed / 0 skipped**.

### Fixed — CI path filter (`4a711d5`)
`terraform-ci.yml` PR trigger: path filter now includes `.checkov.yaml` and `**/*.tfvars` so
changes to the checkov config or environment var files re-trigger the plan job.

### Fixed — infracost `continue-on-error` (`3f464a8`)
`terraform-ci.yml`: `cost estimate` job now has `continue-on-error: true`, preventing the
missing `INFRACOST_API_KEY` secret from marking the entire CI run as failed.

### Fixed — full stderr capture in probe (`9512007`)
All three workflow files: `head -1 "$err_file"` replaced with
`tr '\n' ' ' < "$err_file" | cut -c1-400` so the complete multi-line `az` CLI error is
captured in probe log lines and the final `::error::` annotation. This revealed the actual
failure message ("blocked by network rules") that was previously truncated to blank.

### Fixed — IPv4 forcing (`98cf536`, superseded by PR #18)
All three workflow files: added `sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1` and
`curl -4` before IP detection to force IPv4. Resolved run `26127298691` (1m6s, ✓) but proved
unreliable across runner allocations — fully superseded by the `defaultAction` toggle in PR #18.

### Verified — PR #17, run `26127298691`
- `terraform plan`: ✓ in 1m6s
- All other checks green; `cost estimate` non-blocking fail (expected — no API key)

---

## 791e4fb — 2026-05-19 — `docs`: add `final-code-review.md`

### Added
- `docs/final-code-review.md`: automated code review against commit `e9698d6` on `main`.
  Documents six test suites (terraform fmt, validate, tflint, checkov local, CI security
  workflow `26117001627`, CI apply `26114963018`) — all passing. Nine findings (F-01–F-09):
  two checkov false positives (now suppressed in PR #17), operational hardening tasks (HTTPS
  enablement, image pinning, disk tier), and informational items. All prior HIGH/MEDIUM
  vulnerabilities from the original `code-review.md` confirmed resolved.

---

## e9698d6 — 2026-05-19 — `fix(oidc)`: correct federated credential subjects — all envs + script default

### Problem
`plan (dev)` (and `apply (dev)`) failed with `az` exit code 1 — OIDC
token-exchange error. Investigation revealed the same wrong-repo-slug
defect existed on all three environments and in the script itself.

### Root cause
`oidc-create-app.sh` had `REPO="${REPO:-mdixon47/terraform}"` as the
default. The repo has since been renamed to `azure-hub-spoke-teraform`.
All six federated credentials (`dev`, `dev-apply`, `staging`,
`staging-apply`, `prod`, `prod-apply`) were created with this old slug
and were therefore unreachable via OIDC token exchange. In addition, the
`dev-apply` credential subject was incorrectly set to `environment:dev`
instead of `environment:dev-apply`, leaving that job with no valid match.

### Fixed (Azure — `az ad app federated-credential update`)

| App | Credential | Old subject | New subject |
|---|---|---|---|
| `gh-tf-dev` | `…-env-dev` | `…mdixon47/terraform:environment:dev` | `…azure-hub-spoke-teraform:environment:dev` |
| `gh-tf-dev` | `…-env-dev-apply` | `…azure-hub-spoke-teraform:environment:dev` | `…azure-hub-spoke-teraform:environment:dev-apply` |
| `gh-tf-staging` | `…-env-staging` | `…mdixon47/terraform:environment:staging` | `…azure-hub-spoke-teraform:environment:staging` |
| `gh-tf-staging` | `…-env-staging-apply` | `…mdixon47/terraform:environment:staging-apply` | `…azure-hub-spoke-teraform:environment:staging-apply` |
| `gh-tf-prod` | `…-env-prod` | `…mdixon47/terraform:environment:prod` | `…azure-hub-spoke-teraform:environment:prod` |
| `gh-tf-prod` | `…-env-prod-apply` | `…mdixon47/terraform:environment:prod-apply` | `…azure-hub-spoke-teraform:environment:prod-apply` |

### Fixed (`scripts/oidc-create-app.sh`)
- Default `REPO` changed from `mdixon47/terraform` →
  `mdixon47/azure-hub-spoke-teraform`. Future `./oidc-create-app.sh
  <env>` invocations will produce correct subjects without needing
  `REPO=… ./oidc-create-app.sh`.

### Verified — run `26114963018` (dev)
- `plan (dev)`: ✓ in 47s — `Plan: 0 to add, 1 to change, 0 to destroy.`
- `apply (dev)`: ✓ in 1m26s — `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`

## 105e733 — 2026-05-19 — `fix(dev)`: switch VMs from `Standard_B2s_v2` → `Standard_D2als_v7` (quota exhausted)

### Fixed
- `environments/dev.tfvars`: `web_vm_size` and `app_vm_size` changed from
  `Standard_B2s_v2` to `Standard_D2als_v7`. Root cause: `standardBsv2Family`
  has an approved quota of **0** on this subscription in `westus2`
  (`OperationNotAllowed: Current Limit: 0, Additional Required: 2`). This is a
  quota cap, not a capacity restriction — the SKU is simply unapproved for the
  subscription.

### Selection rationale
- Scanned all SKUs in `westus2` for x86 2-vCPU ≥ 4 GB with no
  `NotAvailableForSubscription` restriction and `limit > 0` quota.
  `Standard_D2als_v7` (2 vCPU / 4 GB / AMD Genoa, `StandardDalsv7Family`,
  quota limit = 10) was the smallest eligible match. Validated with
  `az vm create --validate` against the `0001-com-ubuntu-server-jammy:22_04-lts-gen2`
  image before applying.

### Apply result
- First apply attempt (`Standard_B2s_v2`): 12 of 14 resources succeeded; both
  VMs failed with quota error. All other resources — subnets (6 in-place
  updates), storage accounts (2 updates), storage container, SQL database,
  diagnostic setting, and queue-properties resource — applied cleanly.
- Second apply attempt (`Standard_D2als_v7`): `hubspkd-web-vm` and
  `hubspkd-app-vm` created in 52 s. `Apply complete! Resources: 2 added,
  1 changed, 0 destroyed.`

### Also fixed (same session, backend config)
- `backend.hcl`: `key` corrected from `dev.tfstate` → `dev.terraform.tfstate`
  to match the key pattern used by the `terraform-apply` workflow
  (`${{ inputs.environment }}.terraform.tfstate`). The old key pointed to a
  181-byte empty state file; the real state (121 KB) is in
  `dev.terraform.tfstate`.

### Outputs (post-apply)
```
web_vm_private_ip              = 10.1.1.4
app_vm_private_ip              = 10.1.2.4
application_gateway_public_ip  = 20.64.201.199
firewall_public_ip             = 20.64.201.203
sql_server_fqdn                = hubspkd-sql-zdltzn.database.windows.net
bastion_dns_name               = bst-e679b46d-ddd5-4174-87d8-1abcab3bc36c.bastion.azure.com
```

## df1cffb — 2026-05-19 — `chore(deps)`: bump azurerm provider 3.117.1 → `~> 4.x` and clear deprecations

### Changed
- `providers.tf` and all `modules/*/versions.tf` (5 files): version constraint
  `~> 3.100` → `~> 4.0`. Lock file regenerated at `4.73.0` for `linux_amd64`,
  `darwin_amd64`, and `darwin_arm64`.

### Fixed (breaking changes in azurerm v4)
- `modules/data/main.tf` — `azurerm_storage_container.app`: `storage_account_name`
  removed in v4; replaced with `storage_account_id`.
- `modules/data/main.tf` — `azurerm_storage_account.general`: `queue_properties`
  inline block removed in v4; extracted to new
  `azurerm_storage_account_queue_properties.general` resource (same logging config).
- `modules/data/main.tf` — `azurerm_mssql_server_extended_auditing_policy.this`:
  `enabled` attribute removed in v4; attribute dropped (resource presence implies
  enabled).
- `modules/hub/main.tf` — `azurerm_firewall.this`: `threat_intel_mode` removed in v4
  (must live on the policy only); attribute dropped. `azurerm_firewall_policy.this`
  already carries `threat_intelligence_mode = "Deny"`.

### Fixed (v4 deprecations, removed in v5)
- `modules/data/main.tf` + `modules/hub/main.tf` — `azurerm_monitor_diagnostic_setting`
  (4 resources): `metric` block renamed to `enabled_metric`.
- `modules/security/main.tf` — `azurerm_key_vault.this`: `enable_rbac_authorization`
  renamed to `rbac_authorization_enabled`.

### Verified
- `terraform validate` → `Success! The configuration is valid.` (zero warnings,
  zero errors) against `azurerm 4.73.0`.

## a6713f0 — 2026-05-19 — `build(deps)`: bump `actions/checkout` 4 → 6 (Dependabot #15)

### Changed
- `.github/workflows/security.yml` (5 refs), `.github/workflows/terraform-apply.yml`
  (2 refs), `.github/workflows/terraform-ci.yml` (5 refs),
  `.github/workflows/terraform-destroy.yml` (1 ref): `actions/checkout@v4` →
  `@v6`. Required a Dependabot rebase after PRs #12, #14, #6, and #13 merged
  ahead of it; no input/output schema change.

## fd4fdfe — 2026-05-19 — `build(deps)`: bump `actions/upload-artifact` 4 → 7 (Dependabot #13)

### Changed
- `.github/workflows/security.yml` (4 refs), `.github/workflows/terraform-apply.yml`
  (1 ref), `.github/workflows/terraform-ci.yml` (1 ref): `upload-artifact@v4` →
  `@v7`. Remains in the v4+ Artifact API generation; compatible with
  `download-artifact` at any v4+ version including v8.

## cfbaa5f — 2026-05-19 — `build(deps)`: bump `actions/download-artifact` 4 → 8 (Dependabot #6)

### Changed
- `.github/workflows/terraform-apply.yml` (1 ref): `download-artifact@v4` →
  `@v8`. Clears the hold noted in `983a2d6`; the `digest-mismatch` default
  change (`warn` → `error`) and ESM migration are consistent with
  `upload-artifact@v7` (latest available — no v8 upload-artifact exists).
  Merged immediately after `upload-artifact` bump (#13) to keep the
  tfplan upload/download pair in the same API generation.

## 14c9899 — 2026-05-19 — `build(deps)`: bump `infracost/actions` 3 → 4 (Dependabot #14)

### Changed
- `.github/workflows/terraform-ci.yml` (1 ref): `infracost/actions/setup@v3` →
  `@v4`.

## 1074a3b — 2026-05-19 — `build(deps)`: bump `terraform-linters/setup-tflint` 4 → 6 (Dependabot #12)

### Changed
- `.github/workflows/terraform-ci.yml` (1 ref): `setup-tflint@v4` → `@v6`.

## eab8537 — 2026-05-19 — `ci`: relax SA firewall probe streak 3 → 1

### Changed
- `.github/workflows/terraform-apply.yml` (plan + apply jobs) and
  `.github/workflows/terraform-destroy.yml` and
  `.github/workflows/terraform-ci.yml`: lower the `required` streak in the
  JIT firewall stabilisation loop from **3 consecutive** successful
  `az storage blob list` probes to **1** success. The 3-probe streak was
  introduced (PR #11) to ride out Azure Storage's multi-front-end
  propagation race, but run `26078095239` failed the entire 360s window
  even though a single probe would have likely passed sooner. The
  follow-on `terraform init` step already retries 3× with 15s backoff,
  which is sufficient to absorb a single front-end being late.

### Rationale
- Worst seen propagation delay (run `26078095239`): probes 1–72 all
  failed with `The request may be blocked by network rules of storage
  account`. The previous run on the same SA (`26076400576`) passed in
  17s. The 1-success threshold trades a small reliability margin (any
  later 403s caught by `terraform init`'s retry loop) for faster
  recovery and a smaller failure surface.

## ecaba13 — 2026-05-19 — `fix(dev)`: SQL maxsize 32 → 30 GB, VMs to `Standard_B2s_v2`

### Fixed
- `azurerm_mssql_database.this`: `InvalidMaxSizeTierCombination` on
  apply — the Standard SKU tier (default `sql_database_sku = "S0"`)
  does not support `max_size_gb = 32`. Valid Standard-tier sizes are
  `0.1 / 0.5 / 1 / 2 / 5 / 10 / 20 / 30 / 50 / 100 / 150 / 200 / 250`
  GB. Changed `modules/data/main.tf` to `max_size_gb = 30`, which is
  universally supported across Standard and vCore SKUs.
- `azurerm_linux_virtual_machine.{web,app}`: `SkuNotAvailable` /
  Capacity Restrictions in `westus2` on `Standard_B2ms`, despite the
  management plane reporting no subscription-level restrictions on
  that SKU. Verified via `az vm create --validate` that
  `Standard_B2s_v2` (newer B-series v2, same 2 vCPU / 8 GB shape) has
  free capacity. `environments/dev.tfvars` now sets
  `web_vm_size = app_vm_size = "Standard_B2s_v2"`. Staging/prod still
  use `Standard_B2s` and may need similar evaluation on first apply.

## 7958fa0 — 2026-05-19 — `ci`: extend SA firewall probe budget to 360s and capture stderr

### Changed
- `.github/workflows/terraform-apply.yml` (plan + apply jobs),
  `.github/workflows/terraform-destroy.yml`, and
  `.github/workflows/terraform-ci.yml`: JIT firewall stabilisation
  loop budget raised from 36 iterations / 180s to 72 / 360s. Each
  failing probe now captures the first 200 chars of `az` stderr to an
  `err_file`; the terminal `::error::` annotation includes the last
  3 lines of that file so transient propagation delays can be
  distinguished from RBAC / network rule misconfigurations.

### Why
- Run `26075271542` (apply on `dev`) failed at this step with 36/36
  probe failures and no captured stderr. The added diagnostics on the
  next failure (run `26078095239`, full 360s) confirmed the underlying
  error is `The request may be blocked by network rules of storage
  account` — i.e. firewall-edge propagation lag, not RBAC. See the
  follow-up entry (probe streak 3 → 1) for the durable mitigation.

## 1eb5b59 — 2026-05-19 — `dev`: open blob SA for CI bootstrap, switch VMs to `Standard_B2ms`

### Fixed
- `azurerm_storage_container.app`: `403 AuthorizationFailure` on apply
  in run `26073654800` — the workload blob SA had
  `default_action = Deny` and no firewall entry for the GitHub runner,
  so the data-plane container-create call from the runner was blocked
  even though the management-plane SA itself was reachable. Added a
  `blob_public_network_access_enabled` toggle (off by default; `true`
  in `dev.tfvars`) that lets the dev SA accept public ingress during
  bootstrap. Staging / prod should remain locked down and use a
  Private Endpoint or a JIT firewall punch when they ship.
- `azurerm_linux_virtual_machine.{web,app}`: `SkuNotAvailable` on
  `Standard_B2s` in `westus2` (zone-level
  `NotAvailableForSubscription`). Switched dev VMs to
  `Standard_B2ms`, verified as unrestricted in the SKU probe.
  (Superseded by `ecaba13`: B2ms also hit capacity restrictions
  later — moved to `B2s_v2`.)

### Added
- Root `variable "blob_public_network_access_enabled"` and the
  matching `modules/data` plumbing. Default `false`, set to `true`
  only in `environments/dev.tfvars`.

## f06158b — 2026-05-19 — `fix(envs)`: switch dev location from `eastus2` → `westus2`

### Fixed
- `azurerm_mssql_server.this`: `ProvisioningDisabled` in `eastus2`
  (and previously `eastus`). Per-region probe via `az sql server
  create --validate` across `westus2`, `westus3`, `centralus`,
  `southcentralus`, `northcentralus`, `canadacentral` confirmed
  `westus2` is the closest region with free SQL provisioning quota
  on this subscription.

### Changed
- `environments/dev.tfvars`: `location = "westus2"`.
- GZRS replication for `azurerm_storage_account` remains valid in
  `westus2` (was the secondary blocker that pushed us off `eastus`).

## f9ac2d2 — 2026-05-19 — `ci(workflows)`: opt into Node.js 24 across all workflows

### Changed
- `.github/workflows/terraform-apply.yml`,
  `.github/workflows/terraform-destroy.yml`, and
  `.github/workflows/terraform-ci.yml`: added top-level
  `env: FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"` so the
  `actions/checkout`, `actions/upload-artifact`,
  `actions/download-artifact`, and `hashicorp/setup-terraform` JS
  actions run on Node.js 24. Silences the
  `Node.js 20 actions are deprecated` warning ahead of the
  2026-09-16 removal of Node 20 from GitHub-hosted runners.

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
