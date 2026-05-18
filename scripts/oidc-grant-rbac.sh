#!/usr/bin/env bash
# Grants RBAC to the gh-tf-<env> service principal:
#   - Contributor on the subscription (per decision B1)
#   - Storage Blob Data Contributor on the state container scope
#
# Idempotent: az role assignment create is safe to re-run (returns existing).
#
# Usage:
#   scripts/oidc-grant-rbac.sh <env-name>
#
# Requires:
#   - .gh-tf-<env>-spid.local (written by oidc-create-app.sh)
#   - $TFSTATE_RG, $TFSTATE_SA, $TFSTATE_CONTAINER environment overrides
#     (default values reflect the current bootstrap)

set -euo pipefail

ENV="${1:?usage: $0 <env-name>}"
TFSTATE_RG="${TFSTATE_RG:-tfstate-rg}"
TFSTATE_SA="${TFSTATE_SA:-tfstate066541de13d8e2}"
TFSTATE_CONTAINER="${TFSTATE_CONTAINER:-tfstate}"

SP_ID_FILE=".gh-tf-${ENV}-spid.local"
if [ ! -s "${SP_ID_FILE}" ]; then
  echo "error: ${SP_ID_FILE} missing or empty; run oidc-create-app.sh ${ENV} first" >&2
  exit 1
fi
SP_ID=$(cat "${SP_ID_FILE}")

SUB_ID=$(az account show --query id -o tsv)
SUB_SCOPE="/subscriptions/${SUB_ID}"
CONTAINER_SCOPE="${SUB_SCOPE}/resourceGroups/${TFSTATE_RG}/providers/Microsoft.Storage/storageAccounts/${TFSTATE_SA}/blobServices/default/containers/${TFSTATE_CONTAINER}"

echo "=== gh-tf-${ENV}: RBAC grants ==="
echo "SP object id:    ${SP_ID}"
echo "Subscription:    ${SUB_SCOPE}"
echo "State container: ${CONTAINER_SCOPE}"
echo

grant() {
  local ROLE="$1"
  local SCOPE="$2"
  local EXISTING
  EXISTING=$(az role assignment list \
    --assignee "${SP_ID}" \
    --role "${ROLE}" \
    --scope "${SCOPE}" \
    --query "[0].id" -o tsv 2>/dev/null || true)
  if [ -n "${EXISTING}" ]; then
    echo "      reused  ${ROLE} on ${SCOPE##*/providers/}"
    return 0
  fi
  az role assignment create \
    --assignee-object-id "${SP_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "${ROLE}" \
    --scope "${SCOPE}" \
    --query "id" -o tsv > /dev/null
  echo "      granted ${ROLE} on ${SCOPE##*/providers/}"
}

echo "[1/2] Contributor @ subscription"
grant "Contributor" "${SUB_SCOPE}"

echo
echo "[2/2] Storage Blob Data Contributor @ state container"
grant "Storage Blob Data Contributor" "${CONTAINER_SCOPE}"

echo
echo "=== Done: ${ENV} RBAC ==="
