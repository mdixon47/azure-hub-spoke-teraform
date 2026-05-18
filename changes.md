# Changes

Reverse-chronological log of notable changes to this repository. Entries are
grouped by the commit on `main` that introduced them.

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

- PRs #4 (`codeql-action` v3 → v4), #5 (`azure/login` v2 → v3),
  #9 (`setup-terraform` v3 → v4): verified safe, awaiting merge.
- PR #6 (`download-artifact` v4 → v8): held pending first successful
  `terraform-apply` run.
- OIDC federation + apply-pipeline runner (self-hosted-in-VNet or
  state-firewall allow-list) so `terraform-apply.yml` can reach the
  state backend.
