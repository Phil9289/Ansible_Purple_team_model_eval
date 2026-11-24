#!/usr/bin/env bash
# Lance une mission PentAGI (un "flow" autonome) contre une cible du champ de tir,
# via l'API GraphQL. Nécessite un jeton API créé dans l'UI :
#   Settings -> API Tokens -> Create Token  (copie-le, il n'est montré qu'une fois)
#   export PENTAGI_API_TOKEN=....
#
# Exemples :
#   ./scripts/new-mission.sh --target juice
#   ./scripts/new-mission.sh --target dvwa --provider anthropic
#   ./scripts/new-mission.sh --prompt-file config/missions/web_juice_shop.md --provider openai
. "$(dirname "$0")/common.sh"
check_env

PROVIDER="${PENTAGI_PROVIDER:-openai}"
TARGET=""
PROMPT_FILE=""
BASE_URL="${PENTAGI_BASE_URL:-https://127.0.0.1:8443}"

usage() {
  cat <<EOF
usage: $0 [--target juice|dvwa] [--prompt-file FICHIER] [--provider NOM] [--base-url URL]

  --target juice|dvwa   utilise une mission prédéfinie (config/missions/*.md)
  --prompt-file FICHIER  utilise ton propre fichier de consigne
  --provider NOM         fournisseur LLM déclaré côté PentAGI : openai | anthropic |
                         gemini | ollama | custom | bedrock ... (défaut: ${PROVIDER})
  --base-url URL         défaut: ${BASE_URL}

Jeton requis : export PENTAGI_API_TOKEN=... (créé dans l'UI, Settings -> API Tokens)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "argument inconnu: $1 (voir --help)" ;;
  esac
done

[[ -n "${PENTAGI_API_TOKEN:-}" ]] || die "export PENTAGI_API_TOKEN=... (jeton créé dans l'UI)"

if [[ -z "${PROMPT_FILE}" ]]; then
  case "${TARGET}" in
    juice) PROMPT_FILE="${REPO_ROOT}/config/missions/web_juice_shop.md" ;;
    dvwa)  PROMPT_FILE="${REPO_ROOT}/config/missions/dvwa_sqli.md" ;;
    *) usage; die "précise --target ou --prompt-file" ;;
  esac
fi
[[ -f "${PROMPT_FILE}" ]] || die "fichier de consigne introuvable: ${PROMPT_FILE}"

require_cmd curl; require_cmd jq
INPUT="$(cat "${PROMPT_FILE}")"

c_info "Création d'un flow PentAGI (provider=${PROVIDER}) à partir de ${PROMPT_FILE##*/}"

# GraphQL createFlow(modelProvider, input) — schéma officiel PentAGI.
payload=$(jq -n --arg p "${PROVIDER}" --arg i "${INPUT}" '{
  query: "mutation CreateFlow($provider: String!, $input: String!) { createFlow(modelProvider: $provider, input: $input) { id title status createdAt } }",
  variables: { provider: $p, input: $i }
}')

resp=$(curl -sS -k -X POST "${BASE_URL}/api/v1/graphql" \
  -H "Authorization: Bearer ${PENTAGI_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${payload}")

echo "${resp}" | jq . 2>/dev/null || { echo "${resp}"; die "réponse inattendue de l'API"; }

flow_id=$(echo "${resp}" | jq -r '.data.createFlow.id // empty')
if [[ -n "${flow_id}" ]]; then
  c_grn "Flow créé : id=${flow_id}"
  c_info "Suis-le dans l'UI (${BASE_URL}) ou récupère le rapport : ./scripts/export-results.sh ${flow_id}"
else
  c_ylw "Pas d'id de flow dans la réponse — vérifie le jeton, le provider, et que le fournisseur est bien configuré dans .env."
fi
