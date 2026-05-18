#!/usr/bin/env bash
# Provisions workload-level GitHub secrets for the dev / dev-apply environments:
#   - VM_ADMIN_PASSWORD       (random, Azure VM complexity rules)
#   - SQL_ADMIN_PASSWORD      (random, Azure SQL complexity rules)
#   - VM_ADMIN_SSH_PUBLIC_KEY (RSA-4096; ed25519 is rejected by the azurerm
#                              provider's SSH key validator)
#
# Values are sent to `gh secret set` over stdin (never argv/logs).
# Re-runnable: existing SSH keypair is reused; passwords are regenerated.
#
# Flags:
#   --save-passwords   Also write the generated VM and SQL passwords to
#                      ${PW_FILE} (default ~/.ssh/gh-tf-dev-passwords.local)
#                      with 0600 perms so they can be recovered for an
#                      out-of-band login. File is .local — gitignored.
#   -h, --help         Show this help.
set -euo pipefail

REPO="${REPO:-mdixon47/terraform}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/gh-tf-dev-rsa}"
PW_FILE="${PW_FILE:-$HOME/.ssh/gh-tf-dev-passwords.local}"
ENVS=(dev dev-apply)
SAVE_PASSWORDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-passwords) SAVE_PASSWORDS=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

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
SSH_PUB_LEN="$(wc -c <"${KEY_PATH}.pub" | tr -d ' ')"

# Sanity checks (lengths only — never the values).
[[ ${#VM_PW}   -ge 16 ]] || { echo "ERR: VM_PW too short";   exit 2; }
[[ ${#SQL_PW}  -ge 16 ]] || { echo "ERR: SQL_PW too short";  exit 2; }
[[ ${SSH_PUB_LEN} -gt 60 ]] || { echo "ERR: SSH_PUB malformed"; exit 2; }
echo "Generated: VM_PW(len=${#VM_PW}) SQL_PW(len=${#SQL_PW}) SSH_PUB(len=${SSH_PUB_LEN})"

# ---- Push to GitHub via stdin (no values in argv) ---------------------------
# Passwords: pipe via printf (avoids leaking through argv or process listing).
# SSH key:   redirect stdin from the .pub file directly. Empirically, the
#            round-trip through a shell variable can drop the trailing newline
#            and produce a value the azurerm provider rejects as "not a
#            complete SSH2 Public Key"; reading the file as-is avoids that.
push_pw() {
  local env="$1" name="$2" value="$3"
  printf '%s' "${value}" | gh secret set "${name}" \
    --repo "${REPO}" --env "${env}" --body - >/dev/null
  echo "  ✓ ${env}/${name}"
}
push_file() {
  local env="$1" name="$2" file="$3"
  gh secret set "${name}" --repo "${REPO}" --env "${env}" <"${file}" >/dev/null
  echo "  ✓ ${env}/${name}"
}

for E in "${ENVS[@]}"; do
  echo "--- env: ${E} ---"
  push_pw   "${E}" VM_ADMIN_PASSWORD       "${VM_PW}"
  push_pw   "${E}" SQL_ADMIN_PASSWORD      "${SQL_PW}"
  push_file "${E}" VM_ADMIN_SSH_PUBLIC_KEY "${KEY_PATH}.pub"
done

# Optional local copy of the generated passwords for out-of-band recovery.
if [[ "${SAVE_PASSWORDS}" -eq 1 ]]; then
  ( umask 077
    {
      printf '# generated %s by %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$0"
      printf 'VM_ADMIN_PASSWORD=%s\n'  "${VM_PW}"
      printf 'SQL_ADMIN_PASSWORD=%s\n' "${SQL_PW}"
    } >"${PW_FILE}"
  )
  echo "Saved passwords to ${PW_FILE} (0600)"
fi

# Clear from shell memory promptly.
VM_PW=""; SQL_PW=""

# ---- Verify presence (names + updated timestamps only) ----------------------
for E in "${ENVS[@]}"; do
  echo "--- secrets in ${E} ---"
  gh secret list --repo "${REPO}" --env "${E}"
done
