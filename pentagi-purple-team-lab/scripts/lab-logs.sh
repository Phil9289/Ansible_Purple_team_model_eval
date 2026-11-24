#!/usr/bin/env bash
# Suit les logs. Par défaut le service pentagi ; sinon passe un nom de service.
#   ./scripts/lab-logs.sh            # logs du backend pentagi
#   ./scripts/lab-logs.sh pgvector   # logs d'un autre service
. "$(dirname "$0")/common.sh"
check_env
svc="${1:-pentagi}"
dc logs -f --tail=200 "${svc}"
