# OIDC + JIT firewall setup (runbook)

How to onboard a new Terraform environment so its CI workflows can
authenticate to Azure with GitHub OIDC (no long-lived secrets) and
reach the state Storage Account through a just-in-time firewall
toggle (Option F2 from the design notes).

The procedure has been exercised end-to-end for `dev`, `staging`, and
`prod`. See `changes.md` → PR #11 entry for the rationale and the
failure modes that shaped the current implementation.

## Model

Per environment `<env>` we provision:

| Artifact | Where | Identifier |
|---|---|---|
| Azure AD application + service principal | Entra ID | `gh-tf-<env>` |
| Federated credential (plan jobs) | Entra ID | subject `repo:<org>/<repo>:environment:<env>` |
| Federated credential (apply jobs) | Entra ID | subject `repo:<org>/<repo>:environment:<env>-apply` |
| RBAC: `Contributor` | Subscription | grant to SP |
| RBAC: `Storage Blob Data Contributor` | State container | grant to SP |
| RBAC: `Storage Account Contributor` | State SA | grant to SP (needed for F2 firewall toggle) |
| GitHub Environment `<env>` | GitHub | used by `terraform-ci.yml` plan job and `terraform-apply.yml` plan job |
| GitHub Environment `<env>-apply` | GitHub | used by `terraform-apply.yml` apply job |
| Env secrets | GitHub | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (both envs) |
| Workload secrets | GitHub | `VM_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`, `VM_ADMIN_SSH_PUBLIC_KEY` (both envs) |

The plan/apply split is intentional: required-reviewers can be applied
to `<env>-apply` without blocking PR plans.

## Prerequisites

- `az login` to the target tenant; current subscription set to the one
  hosting the state SA.
- `gh auth status` showing an account with `repo` and `workflow` scopes
  on `<org>/<repo>`.
- Repo variables already set (one-time): `TFSTATE_RG`, `TFSTATE_SA`,
  `TFSTATE_CONTAINER`. Override the script defaults via env vars if
  yours differ.

## Procedure

All commands are run from the repo root. Use `<env>` literally — the
helper scripts derive `<env>-apply` automatically.

### 1. Create the app, SP, and federated credentials

```bash
bash scripts/oidc-create-app.sh <env>
```

Writes `.gh-tf-<env>-appid.local` and `.gh-tf-<env>-spid.local` (public
client identifiers, gitignored for tidiness). Idempotent.

### 2. Grant RBAC

```bash
bash scripts/oidc-grant-rbac.sh <env>
```

Grants the three roles listed in the table above. Idempotent — re-runs
report `reused` for existing assignments. Allow ~15s after step 1 for
the new SP to propagate before role assignment succeeds.

### 3. Create the two GitHub environments

```bash
for E in <env> <env>-apply; do
  gh api -X PUT "/repos/<org>/<repo>/environments/$E" --silent
done
```

Private repos on the free GitHub plan cannot attach `required_reviewers`
or `wait_timer` rules; the API returns HTTP 422 with a billing-plan
message. Upgrade to Pro/Team to add manual approvals on `<env>-apply`.

### 4. Seed identity secrets

```bash
APP_ID=$(cat ".gh-tf-<env>-appid.local")
TENANT_ID=$(az account show --query tenantId -o tsv)
SUB_ID=$(az account show --query id -o tsv)

for E in <env> <env>-apply; do
  printf '%s' "${APP_ID}"    | gh secret set AZURE_CLIENT_ID       --env "$E" --body -
  printf '%s' "${TENANT_ID}" | gh secret set AZURE_TENANT_ID       --env "$E" --body -
  printf '%s' "${SUB_ID}"    | gh secret set AZURE_SUBSCRIPTION_ID --env "$E" --body -
done
```

Values flow over stdin (`--body -`) so they are not visible in the
process listing or shell history.

### 5. Seed workload secrets

```bash
bash scripts/oidc-set-workload-secrets.sh <env> [--save-passwords]
```

Generates an RSA-4096 SSH keypair at `~/.ssh/gh-tf-<env>-rsa` and two
strong passwords. The `.pub` is uploaded by stdin-redirect (variable
round-trips were observed to drop a byte, producing a value the
`azurerm` provider rejects as "not a complete SSH2 Public Key").
`--save-passwords` writes them to `~/.ssh/gh-tf-<env>-passwords.local`
(0600) for out-of-band login recovery.

> The `azurerm_linux_virtual_machine.admin_ssh_key` schema rejects
> Ed25519 keys with the same message. Use RSA-4096 only.

### 6. Verify

```bash
APP_ID=$(cat ".gh-tf-<env>-appid.local")
SP_ID=$(cat ".gh-tf-<env>-spid.local")

az ad app federated-credential list --id "$APP_ID" \
  --query "[].{name:name,subject:subject}" -o table
az role assignment list --assignee "$SP_ID" --all \
  --query "[].{role:roleDefinitionName,scope:scope}" -o table

for E in <env> <env>-apply; do gh secret list --env "$E"; done
```

## Smoke-testing

- **Plan**: open a no-op PR; the `terraform plan` job in
  `terraform-ci.yml` will exercise the OIDC exchange against the
  `<env>=dev` environment (the PR plan job is currently pinned to
  `dev`).
- **Apply**: `Actions → terraform-apply → Run workflow`, pick the new
  `<env>` from the dropdown. The plan stage uses `<env>`, the apply
  stage uses `<env>-apply`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `AADSTS70021: No matching federated identity record found` | Subject mismatch between the federated credential and the workflow's environment name. | Recheck step 1 — `<env>` and the GitHub Environment name must match exactly. |
| `Authenticating using the Azure CLI is only supported as a User` from azurerm | Backend/provider fell back to CLI session auth. | Ensure the job has `ARM_USE_OIDC=true` and `ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` set in the job `env:` (already wired in our workflows). |
| `403 AuthorizationFailure` during `terraform init` | State SA firewall rule for the runner IP hasn't propagated to the front-end Terraform happens to hit. | The CI workflows wait for 3 consecutive successful data-plane probes before init, then wrap init in a 3-attempt retry. Increase the streak or retry count if you continue to see flakes. |
| `admin_ssh_key.0.public_key … is not a complete SSH2 Public Key` | Either the key is Ed25519 (rejected) or a stripped/trailing byte from a printf-piped secret. | Use RSA-4096; upload via `gh secret set < file` so the `.pub` is sent byte-exact. The helper script does this. |
| `HTTP 422 — Please ensure the billing plan supports the wait timer protection rule` | Free-plan private repo doesn't allow environment protection rules. | Either upgrade the plan or skip the `wait_timer` / `required_reviewers` input. |

## Reference

- Workflow files: `.github/workflows/terraform-ci.yml`,
  `.github/workflows/terraform-apply.yml`
- Provisioning scripts: `scripts/oidc-create-app.sh`,
  `scripts/oidc-grant-rbac.sh`, `scripts/oidc-set-workload-secrets.sh`
- F2 audit trail (probe streak, init retry, failure modes):
  `changes.md` → PR #11 entry
