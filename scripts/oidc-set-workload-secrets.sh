#!/usr/bin/env bash
# Provisions workload-level GitHub secrets for the dev / dev-apply environments:
#   - VM_ADMIN_PASSWORD       (random, Azure VM complexity rules)
#   - SQL_ADMIN_PASSWORD      (random, Azure SQL complexity rules)
#   - VM_ADMIN_SSH_PUBLIC_KEY (ed25519, generated if missing)
#
# Values are piped into `gh secret set` via stdin and never echoed, logged,
# or passed as command arguments. Re-runnable: existing SSH key is reused.
set -euo pipefail

REPO="${REPO:-mdixon47/terraform}"
# Azure VMs accept RSA keys via the azurerm provider schema; ed25519 is
# rejected with "is not a complete SSH2 Public Key". Use 4096-bit RSA.
KEY_PATH="${KEY_PATH:-$HOME/.ssh/gh-tf-dev-rsa}"
ENVS=(dev dev-apply)

umask 077

# ---- SSH keypair ------------------------------------------------------------
if [[ ! -f "${KEY_PATH}" ]]; then
  ssh-keygen -t rsa -b 4096 -f "${KEY_PATH}" -N "" \
    -C "gh-tf-dev@$(date -u +%Y%m%dT%H%M%SZ)" >/dev/null
  echo "Generated new RSA-4096 keypair at ${KEY_PATH}{,.pub}"
else
  echo "Reusing existing keypair at ${KEY_PATH}{,.pub}"
fi

# ---- Password generator -----------------------------------------------------
# 28 chars: guaranteed upper, lower, digit, special, rest from a safe alphabet.
# Avoids quoting hazards: no $ ` " ' \ space.
gen_pw() {
  local alpha="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
  local sym="!@#%^*-_=+"
  local pw=""
  pw+="$(LC_ALL=C tr -dc 'A-Z'         </dev/urandom | head -c 1)"
  pw+="$(LC_ALL=C tr -dc 'a-z'         </dev/urandom | head -c 1)"
  pw+="$(LC_ALL=C tr -dc '0-9'         </dev/urandom | head -c 1)"
  pw+="$(printf '%s' "${sym}" | fold -w1 | shuf -n1 2>/dev/null \
        || printf '%s' "${sym:RANDOM%${#sym}:1}")"
  pw+="$(LC_ALL=C tr -dc "${alpha}${sym}" </dev/urandom | head -c 24)"
  printf '%s' "${pw}"
}

VM_PW="$(gen_pw)"
SQL_PW="$(gen_pw)"
SSH_PUB="$(cat "${KEY_PATH}.pub")"

# Sanity checks (lengths only — never the values).
[[ ${#VM_PW}  -ge 16 ]] || { echo "ERR: VM_PW too short";  exit 2; }
[[ ${#SQL_PW} -ge 16 ]] || { echo "ERR: SQL_PW too short"; exit 2; }
[[ ${#SSH_PUB} -gt 60 ]] || { echo "ERR: SSH_PUB malformed"; exit 2; }
echo "Generated: VM_PW(len=${#VM_PW}) SQL_PW(len=${#SQL_PW}) SSH_PUB(len=${#SSH_PUB})"

# ---- Push to GitHub via stdin (no values in argv) ---------------------------
set_secret() {
  local env="$1" name="$2" value="$3"
  printf '%s' "${value}" | gh secret set "${name}" \
    --repo "${REPO}" --env "${env}" --body - >/dev/null
  echo "  ✓ ${env}/${name}"
}

for E in "${ENVS[@]}"; do
  echo "--- env: ${E} ---"
  set_secret "${E}" VM_ADMIN_PASSWORD       "${VM_PW}"
  set_secret "${E}" SQL_ADMIN_PASSWORD      "${SQL_PW}"
  set_secret "${E}" VM_ADMIN_SSH_PUBLIC_KEY "${SSH_PUB}"
done

# Clear from shell memory promptly.
VM_PW=""; SQL_PW=""; SSH_PUB=""

# ---- Verify presence (names + updated timestamps only) ----------------------
for E in "${ENVS[@]}"; do
  echo "--- secrets in ${E} ---"
  gh secret list --repo "${REPO}" --env "${E}"
done
