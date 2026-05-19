#!/usr/bin/env bash
# Creates an Azure AD app + SP + federated credentials for a single
# GitHub Environment. Idempotent on the SP / federated-credential creation
# steps (the underlying `az` commands will error on duplicates; we ignore
# those errors and re-query).
#
# Usage:
#   scripts/oidc-create-app.sh <env-name>
#
# Example:
#   scripts/oidc-create-app.sh dev
#
# Effect:
#   - Creates Azure AD app  "gh-tf-<env>"
#   - Creates service principal for that app
#   - Adds federated credential for subject:
#       repo:<REPO>:environment:<env>
#   - Adds federated credential for subject:
#       repo:<REPO>:environment:<env>-apply
#
# Side effects (local):
#   - Writes .gh-tf-<env>-appid.local  (public client ID)
#   - Writes .gh-tf-<env>-spid.local   (public SP object ID)
# These are NOT secrets but are gitignored to keep the repo clean.

set -euo pipefail

ENV="${1:?usage: $0 <env-name>}"
REPO="${REPO:-mdixon47/azure-hub-spoke-teraform}"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"
APP_NAME="gh-tf-${ENV}"

echo "=== gh-tf-${ENV}: app + SP + federated credentials ==="
echo "Repo:    ${REPO}"
echo "App:     ${APP_NAME}"
echo

echo "[1/4] Create or fetch app: ${APP_NAME}"
APP_ID=$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)
if [ -z "${APP_ID}" ]; then
  APP_ID=$(az ad app create \
    --display-name "${APP_NAME}" \
    --sign-in-audience "AzureADMyOrg" \
    --query "appId" -o tsv)
  echo "      created appId=${APP_ID}"
else
  echo "      reused  appId=${APP_ID}"
fi
echo "${APP_ID}" > ".gh-tf-${ENV}-appid.local"

echo
echo "[2/4] Create or fetch service principal"
SP_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)
if [ -z "${SP_ID}" ]; then
  SP_ID=$(az ad sp create --id "${APP_ID}" --query "id" -o tsv)
  echo "      created spObjectId=${SP_ID}"
else
  echo "      reused  spObjectId=${SP_ID}"
fi
echo "${SP_ID}" > ".gh-tf-${ENV}-spid.local"

add_fic() {
  local SUFFIX="$1"   # e.g. dev or dev-apply
  local NAME="github-${REPO//\//-}-env-${SUFFIX}"
  local SUBJECT="repo:${REPO}:environment:${SUFFIX}"

  local EXISTING
  EXISTING=$(az ad app federated-credential list --id "${APP_ID}" \
    --query "[?subject=='${SUBJECT}'].name" -o tsv 2>/dev/null || true)

  if [ -n "${EXISTING}" ]; then
    echo "      reused  federated-credential: subject=${SUBJECT}"
    return 0
  fi

  local TMP
  TMP=$(mktemp)
  cat > "${TMP}" <<JSON
{
  "name": "${NAME}",
  "issuer": "${ISSUER}",
  "subject": "${SUBJECT}",
  "audiences": ["${AUDIENCE}"]
}
JSON
  az ad app federated-credential create \
    --id "${APP_ID}" \
    --parameters "@${TMP}" \
    --query "subject" -o tsv > /dev/null
  rm -f "${TMP}"
  echo "      created federated-credential: subject=${SUBJECT}"
}

echo
echo "[3/4] Federated credential: environment:${ENV} (plan job)"
add_fic "${ENV}"

echo
echo "[4/4] Federated credential: environment:${ENV}-apply (apply job)"
add_fic "${ENV}-apply"

echo
echo "=== Done: ${APP_NAME} ==="
echo "appId:      ${APP_ID}"
echo "spObjectId: ${SP_ID}"
echo "(appId and spObjectId are public client identifiers, not credentials)"
