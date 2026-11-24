#!/usr/bin/env bash
# Fonctions et variables communes à tous les scripts du labo.
# Sourcé par les autres scripts : . "$(dirname "$0")/common.sh"
set -euo pipefail

# Racine du dépôt = dossier parent de scripts/
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"
ENV_FILE="${REPO_ROOT}/.env"

# Fichiers compose : stack officiel PentAGI + overlay du champ de tir isolé
COMPOSE_FILES=(-f "${COMPOSE_DIR}/docker-compose.pentagi.yml"
               -f "${COMPOSE_DIR}/docker-compose.range.yml")

# Overlay Ollama ajouté à la demande (--with-ollama)
OLLAMA_FILE="${COMPOSE_DIR}/docker-compose.ollama.yml"

c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_grn()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_ylw()   { printf '\033[33m%s\033[0m\n' "$*"; }
c_info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }

die() { c_red "ERREUR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "commande requise introuvable: $1"
}

# Construit la commande docker compose avec les bons -f et --env-file.
# On exécute depuis COMPOSE_DIR pour que les chemins relatifs du compose
# officiel (./example.*.provider.yml, ./docker-ssl) se résolvent au bon endroit.
dc() {
  local extra=()
  if [[ "${WITH_OLLAMA:-0}" == "1" ]]; then
    extra=(-f "${OLLAMA_FILE}")
  fi
  ( cd "${COMPOSE_DIR}" && docker compose \
      --env-file "${ENV_FILE}" \
      "${COMPOSE_FILES[@]}" "${extra[@]}" "$@" )
}

check_env() {
  [[ -f "${ENV_FILE}" ]] || die ".env introuvable. Fais: cp .env.lab.example .env  puis remplis-le."
}
