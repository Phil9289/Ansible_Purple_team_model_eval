#!/usr/bin/env bash
# Vérifie les prérequis et peut générer les secrets du .env.
#   ./scripts/preflight.sh                 # vérifications seulement
#   ./scripts/preflight.sh --gen-secrets   # génère COOKIE_SIGNING_SALT + mot de passe PG
. "$(dirname "$0")/common.sh"

GEN=0
[[ "${1:-}" == "--gen-secrets" ]] && GEN=1

c_info "Vérification des prérequis"
require_cmd docker
docker compose version >/dev/null 2>&1 || die "docker compose (v2) requis"
require_cmd curl
c_grn "  docker + compose: OK"

# RAM / CPU / disque (seuils PentAGI : 2 vCPU, 4 Go RAM, 20 Go disque)
cpus=$(nproc 2>/dev/null || echo '?')
memg=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo '?')
diskg=$(df -BG --output=avail "${REPO_ROOT}" 2>/dev/null | tail -1 | tr -dc '0-9' || echo '?')
c_info "Ressources: ${cpus} vCPU, ${memg} Go RAM, ${diskg} Go libres sur le dépôt"
[[ "${cpus}" != '?' && "${cpus}" -lt 2 ]] && c_ylw "  (PentAGI recommande >= 2 vCPU)"

if [[ "${GEN}" == "1" ]]; then
  [[ -f "${ENV_FILE}" ]] || die ".env introuvable. Fais d'abord: cp .env.lab.example .env"
  salt=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
  pgpw=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 28)
  # Remplace les valeurs CHANGE_ME (compatible GNU/BSD sed via fichier temporaire)
  tmp=$(mktemp)
  sed -e "s|^COOKIE_SIGNING_SALT=.*|COOKIE_SIGNING_SALT=${salt}|" \
      -e "s|^PENTAGI_POSTGRES_PASSWORD=.*|PENTAGI_POSTGRES_PASSWORD=${pgpw}|" \
      "${ENV_FILE}" > "${tmp}" && mv "${tmp}" "${ENV_FILE}"
  c_grn "  Secrets générés dans .env (COOKIE_SIGNING_SALT, PENTAGI_POSTGRES_PASSWORD)"
fi

if [[ -f "${ENV_FILE}" ]]; then
  if grep -qE '^(OPEN_AI_KEY|ANTHROPIC_API_KEY|LLM_SERVER_URL|OLLAMA_SERVER_URL)=.+' "${ENV_FILE}"; then
    c_grn "  Cerveau LLM: au moins un fournisseur configuré."
  else
    c_ylw "  Cerveau LLM: AUCUN fournisseur actif dans .env (section 2). PentAGI ne pourra pas lancer de mission."
  fi
  if grep -qE '^COOKIE_SIGNING_SALT=CHANGE_ME' "${ENV_FILE}"; then
    c_ylw "  Secrets encore par défaut. Lance: ./scripts/preflight.sh --gen-secrets"
  fi
else
  c_ylw "  .env absent. Fais: cp .env.lab.example .env"
fi
c_grn "Préflight terminé."
