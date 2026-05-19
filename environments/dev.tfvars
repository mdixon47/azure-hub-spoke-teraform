# Dev environment - consumed by terraform-apply.yml via -var-file.
# Non-secret values only; vm_admin_password, sql_admin_password, and
# vm_admin_ssh_public_key are injected by the workflow from env secrets
# (TF_VAR_* env vars) so they MUST NOT appear here.

prefix = "hubspkd"
# westus2: validated SQL provisioning (eastus + eastus2 are blocked by
# subscription policy with ProvisioningDisabled); GZRS replication
# supported for StorageV2.
location = "westus2"

# Networking ------------------------------------------------------------------
hub_vnet_cidr   = "10.0.0.0/16"
spoke_vnet_cidr = "10.1.0.0/16"

# Compute sizing --------------------------------------------------------------
# Both Standard_B2s and Standard_B2ms are capacity-restricted in westus2
# ("SkuNotAvailable: Capacity Restrictions"). B2s_v2 (newer B-series v2 family,
# same 2 vCPU / 8 GB shape as B2ms) has free capacity and validated via
# `az vm create --validate`.
web_vm_size = "Standard_B2s_v2"
app_vm_size = "Standard_B2s_v2"

# Observability & lifecycle ---------------------------------------------------
log_retention_days    = 30
enable_resource_locks = false

# HTTPS / Key Vault -----------------------------------------------------------
# First-apply posture: HTTPS off. The terraform-apply workflow JIT-opens the
# state SA firewall but NOT the Key Vault firewall, so enabling the security
# module here would block apply. Enable in a follow-up once a JIT KV path or
# private endpoint is in place.
enable_https                     = false
kv_public_network_access_enabled = false
kv_allowed_ip_ranges             = []

# Storage --------------------------------------------------------------------
# Dev-only: opens the blob SA public endpoint with default firewall Allow so
# the hosted GitHub runner can create the `app-data` container during apply.
# Tighten in staging/prod with a Private Endpoint or JIT firewall punch.
blob_public_network_access_enabled = true

vm_admin_username  = "azureuser"
sql_admin_username = "sqladminuser"

tags = {
  environment = "dev"
  project     = "hub-spoke-reference"
  managed_by  = "terraform"
  owner       = "platform-team"
}
