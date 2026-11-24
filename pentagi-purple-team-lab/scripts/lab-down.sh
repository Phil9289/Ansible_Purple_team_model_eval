#!/usr/bin/env bash
# Arrête le labo.
#   ./scripts/lab-down.sh            # stoppe et retire les conteneurs (garde les volumes/données)
#   ./scripts/lab-down.sh --purge    # + supprime les volumes (données, BD, modèles) : IRRÉVERSIBLE
. "$(dirname "$0")/common.sh"
check_env

WITH_OLLAMA=1; export WITH_OLLAMA   # on inclut l'overlay ollama pour tout nettoyer

if [[ "${1:-}" == "--purge" ]]; then
  c_ylw "Suppression des conteneurs ET des volumes (données perdues)."
  dc down -v --remove-orphans
else
  c_info "Arrêt des conteneurs (volumes conservés)."
  dc down --remove-orphans
fi
c_grn "Labo arrêté."
