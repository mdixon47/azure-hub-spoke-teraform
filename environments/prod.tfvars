# Prod environment - consumed by terraform-apply.yml via -var-file.
# Non-secret values only; vm_admin_password, sql_admin_password, and
# vm_admin_ssh_public_key are injected by the workflow from env secrets
# (TF_VAR_* env vars) so they MUST NOT appear here.

prefix   = "hubspkp"
location = "eastus"

# Networking ------------------------------------------------------------------
hub_vnet_cidr   = "10.0.0.0/16"
spoke_vnet_cidr = "10.1.0.0/16"

# Compute sizing --------------------------------------------------------------
web_vm_size = "Standard_B2s"
app_vm_size = "Standard_B2s"

# Observability & lifecycle ---------------------------------------------------
log_retention_days    = 90
enable_resource_locks = true

# HTTPS / Key Vault -----------------------------------------------------------
# First-apply posture: HTTPS off so the security module is skipped (KV firewall
# isn't JIT-opened by the workflow). Flip to true (with a JIT KV path or
# private endpoint) before declaring the prod environment production-ready.
enable_https                     = false
kv_public_network_access_enabled = false
kv_allowed_ip_ranges             = []

vm_admin_username  = "azureuser"
sql_admin_username = "sqladminuser"

tags = {
  environment = "prod"
  project     = "hub-spoke-reference"
  managed_by  = "terraform"
  owner       = "platform-team"
}
