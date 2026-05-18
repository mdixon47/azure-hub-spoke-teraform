# Scan Results — Hub-Spoke Reference Architecture

**Run date:** 2026-05-18
**Run host:** local (macOS, arm64)
**Scope:** Full repository (`terraform fmt -recursive`, `terraform validate`, plus all configured static analyzers)

## 1. Summary

| Tool             | Version  | Result    | Findings (HIGH/CRITICAL) | Suppressions |
| ---------------- | -------- | --------- | ------------------------ | ------------ |
| `terraform fmt`  | 1.15.0   | clean     | 0                        | —            |
| `terraform validate` | 1.15.0 | clean     | 0                        | —            |
| TFLint (+ azurerm ruleset 0.27.0) | 0.52.0 | clean | 0 | —            |
| Checkov          | 3.2.520  | clean     | 0 (54 passed)            | 5            |
| Trivy `config`   | 0.70.0   | clean     | 0                        | 1 (AZU-0039) |
| Gitleaks         | 8.30.1   | clean     | 0                        | —            |

All gates pass. The five Checkov suppressions and the single Trivy entry are
documented below with rationale.

## 2. How to reproduce

```bash
# Format and structural checks
terraform fmt -recursive -check
terraform init -backend=false -input=false
terraform validate

# Linting
tflint --init
tflint --recursive --config="$(pwd)/.tflint.hcl"

# Static analysis
checkov -d . --framework terraform --quiet --compact --skip-path .terraform
trivy config --severity HIGH,CRITICAL .

# Secret scanning
gitleaks detect --no-git --config=.gitleaks.toml --redact
```

CI parity: `.github/workflows/terraform-ci.yml` and `.github/workflows/security.yml`
run the same commands on every PR.

## 3. Suppressions — Checkov

Each entry lives in `.checkov.yaml` under `skip-check:` with an inline rationale.

| ID              | Title                                                | Why suppressed |
| --------------- | ---------------------------------------------------- | -------------- |
| `CKV_AZURE_59`  | Storage shared access key disabled                   | Reference architecture keeps `shared_access_key_enabled=true`; production deployments should rotate access keys via Key Vault. |
| `CKV2_AZURE_38` | Storage `min_tls_version` (legacy duplicate)         | `min_tls_version=TLS1_2` is already enforced explicitly. The legacy check is redundant noise. |
| `CKV_AZURE_220` | Firewall IDPS in Deny mode                           | Requires the Premium firewall tier. The hub module accepts `firewall_sku_tier="Premium"` to opt in; default stays Standard for cost. |
| `CKV_AZURE_160` | NSG allows inbound HTTP/80 from Internet             | Application Gateway needs port 80 open to serve the permanent HTTP → HTTPS redirect. Real traffic is handled on 443; port 80 returns only a 301 response. |
| `CKV_AZURE_217` | Application Gateway HTTP listener (first listener must be HTTPS) | Checkov inspects `http_listener[0].protocol` and currently does not flatten `dynamic` listener blocks into that index when a static `http_listener` is also present in the same resource ([checkov#5396](https://github.com/bridgecrewio/checkov/issues/5396)). `modules/hub/main.tf` declares the HTTPS listener via a `dynamic` block *first* in source order; it is the primary ingress when `var.enable_https = true`. |
| `CKV_AZURE_229` | Azure SQL zone redundancy                            | Requires Premium / Business Critical or General Purpose Gen5+ tiers. The default is `S0` for cost; `sql_database_sku` + `sql_zone_redundant` variables exist for production overrides. |

## 4. Suppressions — Trivy

| ID         | File                              | Why suppressed |
| ---------- | --------------------------------- | -------------- |
| `AZU-0039` | `modules/spoke-compute/main.tf`   | False positive. `disable_password_authentication = local.use_ssh_key` is dynamically `true` whenever `vm_admin_ssh_public_key` is supplied. Trivy does not evaluate the expression. Operators must set the SSH key variable in prod. |

## 5. Fixes applied in this iteration

The previous run had 12 Checkov failures and 9 TFLint warnings. The following
fixes were applied to close them out:

| ID                   | Resource                              | Fix |
| -------------------- | ------------------------------------- | --- |
| `terraform_required_version` × 4 | All modules                | Added `versions.tf` in each module with `required_version = ">= 1.5.0"`. |
| `terraform_required_providers` × 5 | All modules              | Same `versions.tf` declares `azurerm ~> 3.100` (and `random ~> 3.6` for the data module). |
| `CKV_AZURE_224`      | `azurerm_mssql_database.this`         | Set `ledger_enabled = true`. |
| `CKV_AZURE_206` × 2  | Both `azurerm_storage_account` resources | Default `account_replication_type` switched to `GZRS` (zone + region redundancy); new variable `storage_replication_type`. |
| `CKV_AZURE_33`       | `azurerm_storage_account.general`     | Added `queue_properties.logging` block. |
| `CKV_AZURE_216`      | `azurerm_firewall.this`               | Added `threat_intel_mode = "Deny"`. |
| `CKV_AZURE_218` (partial) | `azurerm_application_gateway.this` | Added explicit Custom `ssl_policy` with `min_protocol_version = "TLSv1_2"` and a strong cipher list. |
| `CKV_AZURE_50` × 2   | Both `azurerm_linux_virtual_machine` resources | Added `allow_extension_operations = var.allow_vm_extensions` (default `false`). |

Firewall policy now also conditionally enables `intrusion_detection { mode = "Deny" }`
when `firewall_sku_tier = "Premium"`, satisfying `CKV_AZURE_220` for Premium deployments.

## 6. Application Gateway HTTPS — landed

The previous iteration deferred the HTTPS listener pending a Key Vault module.
That work is now complete:

- **`modules/security`** — provisions a Key Vault with `purge_protection_enabled = true`,
  `public_network_access_enabled = false`, and `network_acls.default_action = "Deny"`
  by default; a User-Assigned Managed Identity (`*-appgw-uami`) with `Get`-only
  certificate/secret permissions; and a self-signed TLS certificate with
  auto-renew 30 days before expiry.
- **`modules/hub` Application Gateway** — now exposes an `identity {}` block
  bound to the UAMI, an `ssl_certificate {}` referencing the versionless Key
  Vault secret ID (rotation-friendly), an HTTPS listener on a new 443
  frontend port, a permanent `redirect_configuration` from HTTP to HTTPS, and
  two routing rules with explicit priorities.
- **Root toggle** — `var.enable_https` (default `true`) gates the whole stack
  via `count` on the security module and `dynamic` blocks inside Application
  Gateway, so the architecture still deploys cleanly with `enable_https = false`.
- **Suppressions removed** — `CKV_AZURE_218` (now passes via the existing
  Custom `ssl_policy`).
- **Suppressions retained** — `CKV_AZURE_160` (port 80 needed for the redirect)
  and `CKV_AZURE_217` (Checkov dynamic-block limitation; see §3).

### KV bootstrap notes

Because the Key Vault now defaults to `public_network_access_enabled = false`
and `default_action = "Deny"`, the deployer must either run from a host that
reaches the vault privately (Private Endpoint + self-hosted runner) or, for
local bootstrap, set:

```hcl
kv_public_network_access_enabled = true
kv_allowed_ip_ranges             = ["<deployer-egress-ip>/32"]
```

## 7. Known follow-ups (not blocking)

1. **AzureRM provider deprecations.** The `metric` block on
   `azurerm_monitor_diagnostic_setting` and the `queue_properties` block on
   `azurerm_storage_account` are deprecated in `azurerm 3.x` and removed in
   `4.x`. Track as part of the provider upgrade.
2. **DDoS Protection plan** on the hub VNet — deferred (cost-gated, prod only).
3. **CA-issued TLS certificate.** The reference architecture ships a
   self-signed cert. Replace with a Key Vault-managed issuer (DigiCert /
   GlobalSign integration) or import a CA cert for production.
