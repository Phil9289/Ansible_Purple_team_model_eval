#!/usr/bin/env bash
# Récupère l'état et les résultats d'un flow PentAGI via l'API.
#   export PENTAGI_API_TOKEN=...
#   ./scripts/export-results.sh            # liste tous les flows
#   ./scripts/export-results.sh <flow_id>  # détail + tâches d'un flow, sauvé dans results/
. "$(dirname "$0")/common.sh"
check_env
require_cmd curl; require_cmd jq

BASE_URL="${PENTAGI_BASE_URL:-https://127.0.0.1:8443}"
[[ -n "${PENTAGI_API_TOKEN:-}" ]] || die "export PENTAGI_API_TOKEN=..."

gql() { # $1 = requête GraphQL
  curl -sS -k -X POST "${BASE_URL}/api/v1/graphql" \
    -H "Authorization: Bearer ${PENTAGI_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$(jq -n --arg q "$1" '{query:$q}')"
}

if [[ $# -eq 0 ]]; then
  c_info "Liste des flows"
  gql '{ flows { id title status createdAt } }' | jq '.data.flows'
  exit 0
fi

flow_id="$1"
outdir="${REPO_ROOT}/results"
mkdir -p "${outdir}"
ts=$(date +%Y%m%d-%H%M%S)
out="${outdir}/flow-${flow_id}-${ts}.json"

c_info "Export du flow ${flow_id} -> ${out}"
gql "{ flow(id: ${flow_id}) { id title status createdAt updatedAt tasks { id title status result } } }" \
  | tee "${out}" | jq '.data.flow | {id, title, status, tasks: (.tasks | length)}' 2>/dev/null || cat "${out}"

c_grn "Détail complet sauvegardé : ${out}"
c_info "Le rapport formaté (Markdown/PDF) se télécharge aussi depuis le menu Report de la page du flow dans l'UI."
