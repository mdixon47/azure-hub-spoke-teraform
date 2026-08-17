terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state backend. The values below are placeholders satisfying the
  # provider schema for `terraform validate`; the real values MUST be supplied
  # at init time via `-backend-config` flags or an `-backend-config=<file>.hcl`
  # file (see docs/devsecops.md and the `terraform-apply` workflow). In CI the
  # runner authenticates via GitHub OIDC and the state SA admits the runner's
  # egress IP just-in-time for the duration of the job (see changes.md).
  backend "azurerm" {
    resource_group_name  = "PLACEHOLDER"
    storage_account_name = "PLACEHOLDER"
    container_name       = "PLACEHOLDER"
    key                  = "PLACEHOLDER.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}
