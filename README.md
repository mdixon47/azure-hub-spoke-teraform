# Azure Hub-Spoke Reference Architecture (Terraform)

Terraform code for the architecture in the design diagram: a hub-spoke topology
on Azure with Bastion + Firewall + Application Gateway in the hub, a Web tier
and App tier in the spoke (each guarded by an NSG), and an Azure SQL database
plus two storage accounts for data services.

## Topology

```
Internet user
   |
   v
Azure Firewall (hub)        Azure Bastion (hub) -- management --+
   |                                                            |
   v                                                            |
Application Gateway (hub) --VNet Peering--> Web Tier VM (spoke) | Web NSG
                                              |                 |
                                              v                 |
                                            App Tier VM (spoke) | App NSG
                                              |
                                              v
                                            Azure SQL / Blob Storage / Storage Account
```

## Layout

```
.
├── main.tf                 # Composes the four modules
├── providers.tf            # azurerm + random
├── variables.tf            # Root-level inputs
├── outputs.tf              # Root-level outputs
├── terraform.tfvars.example
└── modules/
    ├── networking/         # VNets, subnets, peering
    ├── hub/                # Bastion, Firewall, Application Gateway
    ├── spoke-compute/      # Web/App NSGs and Linux VMs
    └── data/               # Azure SQL + storage accounts
```

## Prerequisites

- Terraform >= 1.5
- Azure CLI logged in (`az login`) or a service principal exported via
  `ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID`.

## Quick start

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set vm_admin_password and sql_admin_password.

terraform init
terraform plan
terraform apply
```

Or keep secrets out of files entirely:

```bash
export TF_VAR_vm_admin_password='S0meStr0ng!Pass'
export TF_VAR_sql_admin_password='S0meStr0ng!Pass'

terraform init
terraform apply
```

## Notes & trade-offs

- The Application Gateway has a single HTTP listener on port 80 pointed at the
  web VM's private IP. For production, add HTTPS, a TLS cert (Key Vault), and
  a WAF SKU.
- The Azure SQL firewall rule `AllowAzureServices` is included for convenience.
  Remove it and put the SQL server behind a Private Endpoint + Private DNS
  zone for stricter network isolation.
- VMs use password authentication for simplicity. Prefer SSH keys
  (`admin_ssh_key` block) and `disable_password_authentication = true` in
  production.
- No User-Defined Routes (UDRs) are wired to force spoke traffic through the
  firewall. To enforce that, add a route table on each spoke subnet with a
  `0.0.0.0/0` next-hop pointing at `module.hub.firewall_private_ip`.
- Storage account names must be globally unique; a random 6-character suffix
  is appended.

## Destroy

```bash
terraform destroy
```

## Further reading

- [`docs/remote-state.md`](docs/remote-state.md) — bootstrapped remote
  state backend (RG, SA, container, RBAC).
- [`docs/oidc-setup.md`](docs/oidc-setup.md) — runbook for onboarding
  a new environment with GitHub OIDC + the just-in-time state-SA
  firewall toggle used by the CI workflows.
- [`docs/devsecops.md`](docs/devsecops.md) — scanner toolchain and
  policy gates in CI.
- [`docs/changes.md`](docs/changes.md) — reverse-chronological log of
  notable changes (architecture decisions, OIDC, failure modes resolved).
