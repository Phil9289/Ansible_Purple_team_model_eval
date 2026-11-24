#!/usr/bin/env bash
# Démarre le labo : stack PentAGI + champ de tir isolé.
#   ./scripts/lab-up.sh                # cerveau = cloud/local selon .env
#   ./scripts/lab-up.sh --with-ollama  # ajoute un service Ollama hors-ligne
. "$(dirname "$0")/common.sh"

WITH_OLLAMA=0
[[ "${1:-}" == "--with-ollama" ]] && WITH_OLLAMA=1
export WITH_OLLAMA

check_env

c_info "Rappel de sécurité : ne vise JAMAIS un hôte réel. Le champ de tir isolé"
c_info "(Juice Shop 172.30.0.10, DVWA 172.30.0.20) est la seule cible autorisée."

c_info "Téléchargement des images et démarrage des conteneurs"
dc pull
dc up -d

echo
c_info "Attente de l'état 'healthy' de la base pgvector..."
for i in $(seq 1 30); do
  if dc ps --format '{{.Service}} {{.Health}}' 2>/dev/null | grep -q 'pgvector healthy'; then
    c_grn "  pgvector: healthy"; break
  fi
  sleep 3
done

if [[ "${WITH_OLLAMA}" == "1" ]]; then
  model=$(grep -E '^OLLAMA_SERVER_MODEL=' "${ENV_FILE}" | cut -d= -f2-)
  if [[ -n "${model}" ]]; then
    c_info "Pré-téléchargement du modèle Ollama: ${model} (peut être long)"
    docker exec lab-ollama ollama pull "${model}" || c_ylw "  pull échoué, PentAGI le retentera (OLLAMA_SERVER_PULL_MODELS_ENABLED)"
  fi
fi

echo
dc ps
echo
listen_ip=$(grep -E '^PENTAGI_LISTEN_IP=' "${ENV_FILE}" | cut -d= -f2-)
listen_port=$(grep -E '^PENTAGI_LISTEN_PORT=' "${ENV_FILE}" | cut -d= -f2-)
c_grn "Labo démarré."
c_grn "UI PentAGI : https://${listen_ip:-127.0.0.1}:${listen_port:-8443}  (admin@pentagi.com / admin — à changer)"
c_info "Accès distant sécurisé : voir docs/02 (tunnel SSH). Lancer une mission : ./scripts/new-mission.sh --help"
