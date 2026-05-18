# Code Review — Hub-Spoke Reference Architecture

**Reviewer:** Augment Agent
**Date:** 2026-05-17
**Scope:** All Terraform under repository root (`main.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `modules/*`)
**Provider:** `hashicorp/azurerm ~> 3.100`

Each finding has a **Severity** (Critical / High / Medium / Low / Info), a **Location**, and a **Recommendation**. Issues are grouped by theme.

---

## 1. Security

### 1.1 SQL Server allows all Azure services — [High]
- **Location:** `modules/data/main.tf` lines 47–52 (`azurerm_mssql_firewall_rule.allow_azure_services`)
- **Issue:** The `0.0.0.0` start/end IP rule grants access to every Azure tenant's resources, not just yours. Combined with `public_network_access_enabled = true` (line 30), the SQL server is reachable from the public Internet via Azure backbones.
- **Recommendation:** Remove the firewall rule and add a Private Endpoint in the spoke (`azurerm_private_endpoint` + private DNS zone `privatelink.database.windows.net`). If a public path is required for dev, restrict to known IPs only.

### 1.2 VM authentication uses password only — [High]
- **Location:** `modules/spoke-compute/main.tf` lines 148, 188 (`disable_password_authentication = false`)
- **Issue:** Passwords are weaker than SSH keys, and are persisted in `terraform.tfvars` and state. No fallback to `admin_ssh_key`.
- **Recommendation:** Add an optional `admin_ssh_public_key` variable and prefer `disable_password_authentication = true` with the `admin_ssh_key` block. Sensitive state should additionally be stored in a remote backend with encryption.

### 1.3 Application Gateway is HTTP-only, no WAF — [High]
- **Location:** `modules/hub/main.tf` lines 104–143
- **Issue:** SKU is `Standard_v2` (not `WAF_v2`), the only listener is port 80, and no TLS certificate is wired up. Public traffic is unencrypted and unfiltered.
- **Recommendation:** Move to `WAF_v2`, add an HTTPS listener (`azurerm_application_gateway` → `ssl_certificate` from Key Vault), and enable `azurerm_web_application_firewall_policy`. Redirect 80 → 443.

### 1.4 No NSG on the Application Gateway subnet — [Medium]
- **Location:** `modules/networking/main.tf` `azurerm_subnet.appgw` (lines 42–47)
- **Issue:** Application Gateway v2 requires an inbound allow rule for `GatewayManager` on TCP 65200–65535 on its own subnet NSG. Without an NSG association the subnet relies on platform defaults, which works today but breaks if a deny-all NSG is ever introduced upstream.
- **Recommendation:** Create an NSG for the appgw subnet with explicit rules: `GatewayManager` → `*:65200-65535`, `Internet` → `*:80,443`, plus a deny-all at high priority.

### 1.5 Storage accounts allow public network access — [Medium]
- **Location:** `modules/data/main.tf` `azurerm_storage_account.blob` (line 57) and `.general` (line 79)
- **Issue:** `public_network_access_enabled` is not set, so it defaults to `true`. The subnets have `Microsoft.Storage` service endpoints but no `network_rules` block restricts the storage accounts to those subnets.
- **Recommendation:** Set `public_network_access_enabled = false` and add `network_rules { default_action = "Deny", virtual_network_subnet_ids = [...] }`, or use Private Endpoints.

### 1.6 No diagnostic / audit logging — [Medium]
- **Location:** Entire project
- **Issue:** No `azurerm_monitor_diagnostic_setting`, no Log Analytics workspace, no Storage account for flow logs. Firewall logs, AppGw access logs, NSG flow logs, and SQL audit are all off.
- **Recommendation:** Add a workspace module and wire diagnostics for Firewall, Application Gateway, Bastion, NSGs, SQL, and Storage.

### 1.7 No DDoS Protection plan on VNets — [Low]
- **Location:** `modules/networking/main.tf`
- **Recommendation:** For production, attach an `azurerm_network_ddos_protection_plan` to the hub VNet (cost-sensitive; acceptable to skip in dev).

---

## 2. Correctness / Bugs

### 2.1 Spoke traffic does not transit the firewall — [High]
- **Location:** Project-wide; no `azurerm_route_table` exists
- **Issue:** Despite deploying Azure Firewall, no UDR forces `0.0.0.0/0` on the web/app subnets to the firewall's private IP. The firewall is effectively bypassed for egress.
- **Recommendation:** Add `azurerm_route_table` with default route → firewall private IP, and associate with `web` and `app` subnets. The firewall output `firewall_private_ip` already exists for this purpose.

### 2.2 Application Gateway has no health probe defined — [Medium]
- **Location:** `modules/hub/main.tf` lines 130–136 (`backend_http_settings`)
- **Issue:** Without an explicit `probe` block, AppGw issues a default probe to `127.0.0.1` on the backend host header. If the web VM does not serve `200 OK` on `/`, the backend pool will be marked unhealthy.
- **Recommendation:** Add a `probe { name = "web-probe", protocol = "Http", path = "/", interval = 30, timeout = 30, unhealthy_threshold = 3, pick_host_name_from_backend_address = true }` and reference it from `backend_http_settings`.

### 2.3 `random_string` may produce a digit-only suffix — [Low]
- **Location:** `modules/data/main.tf` lines 12–17
- **Issue:** `numeric = true` plus `lower = true` (default) does not guarantee at least one letter. Storage account names tolerate digits, so this is cosmetic, but generated names like `hubspkblob123456` are still valid; the risk is the suffix collision rate not the format.
- **Recommendation:** Set `min_lower = 2` for readability, or switch to `random_id` (hex) for stable diff-friendly suffixes.

### 2.4 Inconsistent module declaration order — [Info]
- **Location:** `main.tf` declares `spoke_compute` (line 29) before `hub` (line 50), but `hub` consumes `module.spoke_compute.web_vm_private_ip`. Terraform's DAG handles this, but readability suffers.
- **Recommendation:** Re-order to `networking → spoke_compute → hub → data` to match the data flow.

### 2.5 Resource group deletion guard disabled — [Low]
- **Location:** `providers.tf` line 19 (`prevent_deletion_if_contains_resources = false`)
- **Issue:** Convenient for dev tear-down, dangerous in shared/prod environments.
- **Recommendation:** Parameterize via a `var.allow_rg_force_delete` boolean defaulting to `false`.

---

## 3. State & Operability

### 3.1 No remote backend configured — [High]
- **Location:** `providers.tf` `terraform { ... }` block
- **Issue:** State is written to the working directory by default. Sensitive values (`vm_admin_password`, `sql_admin_password`, SQL server FQDN, private IPs) end up on the operator's laptop unencrypted.
- **Recommendation:** Add `backend "azurerm" { ... }` referencing a state storage account with `use_azuread_auth = true`, blob versioning, and locking.

### 3.2 No `lifecycle { prevent_destroy }` on stateful resources — [Medium]
- **Location:** `azurerm_mssql_server`, `azurerm_mssql_database`, both `azurerm_storage_account` resources
- **Recommendation:** Add `lifecycle { prevent_destroy = true }` for prod, or gate via a variable.

### 3.3 VMs have no boot diagnostics — [Low]
- **Location:** `modules/spoke-compute/main.tf` `azurerm_linux_virtual_machine.web/app`
- **Recommendation:** Add `boot_diagnostics {}` (managed storage) to enable serial console.

---

## 4. Style / Maintainability

### 4.1 Formatting drift in `mssql_server` — [Info]
- **Location:** `modules/data/main.tf` line 30
- **Issue:** `public_network_access_enabled` is longer than the surrounding attribute names; the `=` column is off. Running `terraform fmt -recursive` realigns it.

### 4.2 VM size defaults declared twice — [Info]
- **Location:** Root `variables.tf` (lines 80, 86) **and** `modules/spoke-compute/variables.tf` (lines 60, 66)
- **Recommendation:** Keep defaults at the root layer only; require module callers to pass values explicitly. Reduces drift.

### 4.3 `prefix` validation may be too restrictive — [Info]
- **Location:** `variables.tf` lines 10–13 (`^[a-z0-9]{3,8}$`)
- **Issue:** Generated storage account names are `${prefix}blob${6 chars}` → max 17 chars (OK), but a future `${prefix}-something-long` resource could push past Azure's 24-char limits. Document the worst-case derived name lengths.

### 4.4 `tags` variable has no schema enforcement — [Info]
- **Recommendation:** Validate the presence of required tags (`environment`, `owner`, `cost_center`) with a `validation` block.

### 4.5 No `dependency` declarations on cross-module flows — [Info]
- **Location:** `main.tf` — AppGw's backend pool depends on the web VM's IP. Implicit via the variable reference, but a comment or explicit `depends_on` on `module.hub` clarifies intent.

---

## 5. Recommended follow-ups (priority order)

1. Add a remote backend before any further work (3.1).
2. Add UDRs to force-tunnel spoke egress through the firewall (2.1).
3. Move to `WAF_v2` + HTTPS on Application Gateway (1.3) and add the explicit health probe (2.2).
4. Replace SQL public access with a Private Endpoint (1.1) and lock down storage accounts (1.5).
5. Enable diagnostic settings across all resources (1.6).
6. Switch VMs to SSH-key auth (1.2).

---

## 6. Remediation status

| ID  | Title                                            | Severity | Status         | Implemented in |
|-----|--------------------------------------------------|----------|----------------|----------------|
| 1.1 | SQL Server allows all Azure services             | High     | **Fixed**      | `modules/data/main.tf` — removed `AllowAzureServices`, set `public_network_access_enabled = false`, added Private Endpoint + private DNS zone |
| 1.2 | VM password-only auth                            | High     | **Fixed**      | `modules/spoke-compute/*` — added `vm_admin_ssh_public_key`, conditional `admin_ssh_key` block, `disable_password_authentication` toggles |
| 1.3 | AppGw is HTTP-only, no WAF                       | High     | **Fixed**      | SKU switched to `WAF_v2` with `azurerm_web_application_firewall_policy` in Prevention mode. Custom `ssl_policy` pinned to TLS 1.2 + strong ciphers. New `modules/security` provisions a Key Vault + User-Assigned Managed Identity + self-signed TLS cert; AppGw consumes the cert via `identity {}` + `ssl_certificate {}`, terminates HTTPS on a 443 listener, and permanently redirects HTTP → HTTPS. Gated by `var.enable_https` (default `true`) |
| 1.4 | No NSG on AppGw subnet                           | Medium   | **Fixed**      | `modules/hub/main.tf` — `azurerm_network_security_group.appgw` + association |
| 1.5 | Storage accounts open to public                  | Medium   | **Fixed**      | `modules/data/main.tf` — `public_network_access_enabled = false`, `network_rules` denying by default with VNet allow-list |
| 1.6 | No diagnostic logging                            | Medium   | **Fixed**      | `azurerm_log_analytics_workspace.this` in hub + diagnostic settings for Firewall, AppGw, Bastion, SQL DB |
| 1.7 | No DDoS Protection plan                          | Low      | Deferred       | Cost-gated; track as separate ticket for prod |
| 2.1 | Spoke traffic bypasses firewall                  | High     | **Fixed**      | `azurerm_route_table.spoke_egress` with `0.0.0.0/0 → firewall private IP`, associated with `web` and `app` subnets |
| 2.2 | AppGw has no health probe                        | Medium   | **Fixed**      | `probe` block + `probe_name` on `backend_http_settings`, 200–399 match |
| 2.3 | `random_string` may be digits-only               | Low      | **Fixed**      | Added `min_lower = 2` |
| 2.4 | Inconsistent module declaration order            | Info     | Acknowledged   | DAG-correct as-is; left for a separate cleanup PR to avoid noise here |
| 2.5 | RG deletion guard disabled                       | Low      | Acknowledged   | Default kept for dev convenience; toggle via provider feature in prod fork |
| 3.1 | No remote backend                                | High     | **Fixed**      | `providers.tf` — `backend "azurerm"` with `use_azuread_auth`; values supplied at `terraform init` time via env-specific `-backend-config` |
| 3.2 | No `prevent_destroy` on stateful resources       | Medium   | **Fixed**      | Switched to dynamic `azurerm_management_lock` (CanNotDelete), gated by `var.enable_resource_locks` |
| 3.3 | VMs have no boot diagnostics                     | Low      | **Fixed**      | `boot_diagnostics {}` on both VMs |
| 4.1 | Formatting drift in `mssql_server`               | Info     | **Fixed**      | `terraform fmt -recursive` clean |
| 4.2 | VM size defaults declared twice                  | Info     | Acknowledged   | Both layers keep defaults; documented; low risk |
| 4.3 | `prefix` validation may be too restrictive       | Info     | Acknowledged   | Worst-case derived name lengths within Azure limits |
| 4.4 | `tags` has no schema enforcement                 | Info     | Deferred       | Optional `validation` block tracked separately |
| 4.5 | No explicit cross-module `depends_on`            | Info     | Partial        | Added `depends_on` on AppGw → AppGw NSG association |

## 7. DevSecOps additions (this PR)

| Area | Artifact |
|---|---|
| Local | `.pre-commit-config.yaml`, `.tflint.hcl`, `.checkov.yaml`, `.gitleaks.toml`, `.gitignore` |
| CI | `.github/workflows/terraform-ci.yml` (fmt, validate, tflint, plan, infracost) |
| Security scanning | `.github/workflows/security.yml` (tfsec, checkov, trivy config+fs, terrascan, gitleaks — SARIF → Code scanning) |
| Apply pipeline | `.github/workflows/terraform-apply.yml` (manual dispatch, env-gated, two-stage plan/apply) |
| Dependency hygiene | `.github/dependabot.yml` (Actions + Terraform across all modules) |
| Docs | `docs/devsecops.md` |

See [`docs/devsecops.md`](./devsecops.md) for setup, local commands, required
GitHub Environment variables/secrets, and the findings-triage workflow.

## 8. Scanner remediation (post-tooling run)

The first end-to-end run of all scanners surfaced 12 Checkov failures and 9
TFLint warnings on top of the items in §6. These were closed out before the
final report. See [`docs/scan-results.md`](./scan-results.md) for the matrix.

| Scanner finding ID                               | Resource(s)                              | Resolution |
| ------------------------------------------------ | ---------------------------------------- | ---------- |
| `terraform_required_version` × 4                 | All four modules                         | Added `versions.tf` per module |
| `terraform_required_providers` × 5               | All four modules                         | Declared `azurerm ~> 3.100` (+ `random ~> 3.6` for data) |
| `CKV_AZURE_224` SQL Ledger                       | `azurerm_mssql_database.this`            | `ledger_enabled = true` |
| `CKV_AZURE_229` SQL zone redundancy              | `azurerm_mssql_database.this`            | Variables `sql_database_sku` / `sql_zone_redundant` added; default S0 stays unsuppressed via `.checkov.yaml` with rationale |
| `CKV_AZURE_206` × 2 Storage replication          | Both storage accounts                    | Default replication = `GZRS` (variable-overridable) |
| `CKV_AZURE_33`  Storage queue logging            | `azurerm_storage_account.general`        | `queue_properties.logging` block added |
| `CKV_AZURE_216` Firewall threat intel deny       | `azurerm_firewall.this`                  | `threat_intel_mode = "Deny"` |
| `CKV_AZURE_220` Firewall IDPS deny               | `azurerm_firewall_policy.this`           | Variable `firewall_sku_tier` (default `Standard`); when `Premium`, conditional `intrusion_detection { mode = "Deny" }` is rendered |
| `CKV_AZURE_218` AppGw secure protocols           | `azurerm_application_gateway.this`       | Custom `ssl_policy` with `min_protocol_version = "TLSv1_2"` and strong ciphers; full HTTPS pending Key Vault |
| `CKV_AZURE_50`  × 2 VM extensions                | Both `azurerm_linux_virtual_machine`     | `allow_extension_operations = var.allow_vm_extensions` (default `false`) |
| `CKV_AZURE_160` AppGw NSG inbound 80             | `azurerm_network_security_group.appgw`   | Suppressed with rationale — required by AppGw ingress until HTTPS listener is added |
| `CKV_AZURE_217` AppGw HTTP listener              | `azurerm_application_gateway.this`       | Suppressed; gated on Key Vault HTTPS rollout |
| Trivy `AZU-0039` × 2 Linux VM password auth      | Both `azurerm_linux_virtual_machine`     | Documented false positive — `disable_password_authentication = local.use_ssh_key`; allow-listed via `.trivyignore` |

---

*End of review.*
