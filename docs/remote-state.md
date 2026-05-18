# Remote State Bootstrap

This document captures the one-time bootstrap of the Azure remote state backend
used by every `terraform init` against this repo. The bootstrap is intentionally
**not** managed by Terraform itself (chicken-and-egg with the backend), and is
performed via `az` CLI.

## Target topology

| Item | Value |
|---|---|
| Subscription | `Azure subscription 1` (`2afdabf1-1767-4a37-af66-b394d15f2afb`) |
| Tenant | `Default Directory` (`73d205d0-e09a-4450-ab12-ae6a5b8226db`) |
| Region | `eastus` |
| Resource group | `tfstate-rg` |
| Storage account | `tfstate066541de13d8e2` (Standard_GRS, TLS 1.2, HTTPS-only, public-blob-access disabled) |
| Container | `tfstate` |
| State key | `dev.tfstate` |
| Auth mode | Azure AD (`use_azuread_auth = true`) |

The storage-account name is globally unique and intentionally non-obvious; it is
captured here for traceability rather than secrecy (it is not a credential).

## Bootstrap commands (already executed)

```bash
az login
az account set --subscription 2afdabf1-1767-4a37-af66-b394d15f2afb

# Register required resource providers (idempotent)
for ns in Microsoft.Network Microsoft.Compute Microsoft.Storage Microsoft.Sql \
          Microsoft.KeyVault Microsoft.OperationalInsights Microsoft.Insights \
          Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns"
done

# Resource group + storage account + container
LOCATION=eastus
RG=tfstate-rg
SA=tfstate066541de13d8e2          # generated; persist in .tfstate-sa-name.local
CONTAINER=tfstate

az group create -n "$RG" -l "$LOCATION"

az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_GRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true

az storage container create -n "$CONTAINER" --account-name "$SA" \
  --auth-mode login

# Grant the human operator data-plane access (control-plane Owner is not enough
# for AAD-auth state reads/writes).
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
SCOPE=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Owner" \
  --scope "$SCOPE"
```

## Local initialization

```bash
cp backend.hcl.example backend.hcl
# edit storage_account_name → tfstate066541de13d8e2
terraform init -backend-config=backend.hcl
```

`backend.hcl` is gitignored. Only `backend.hcl.example` is committed.

## Dependabot triage — initial pass

Following the first push, six Dependabot PRs were closed:

| PR | Subject | Decision | Reason |
|---|---|---|---|
| #1, #2, #3, #7, #10 | `azurerm` `~> 3.100` → `~> 4.73` (per-module + root) | **Closed** | Major release; v3→v4 has breaking schema changes. Deferred to a tracked migration. `@dependabot ignore this major version` added. |
| #8 | `aquasecurity/trivy-action` 0.24.0 → 0.36.0 | **Closed** | Superseded by commit `d3190c0` which explicitly pins to `0.35.0` (verified-clean re-tag after the Nov 2025 supply-chain incident). |

Still open and pending review:

| PR | Subject | Notes |
|---|---|---|
| #4 | `github/codeql-action` v3 → v4 | Workflow currently uses `@v3` refs; bump is mechanical but should land alongside a green run. |
| #5 | `azure/login` v2 → v3 | Used by `terraform-apply`; verify OIDC config still works. |
| #6 | `actions/download-artifact` v4 → v8 | Not currently referenced; safe to defer. |
| #9 | `hashicorp/setup-terraform` v3 → v4 | Node 24 baseline; GitHub-hosted runners support it. |

## Next steps

1. **Plan** (`terraform plan`) once required inputs are provided (Key Vault IP
   allow-list, VM admin password, etc.).
2. **Harden** the state account: enable blob versioning + soft delete; restrict
   the storage firewall to operator `/32` + Azure services; place a
   `CanNotDelete` lock on `tfstate-rg`.
3. **Wire OIDC** for the `terraform-apply` workflow so CI uses a federated
   identity instead of a service-principal secret.
