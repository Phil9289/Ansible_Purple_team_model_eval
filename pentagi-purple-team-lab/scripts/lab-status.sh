#!/usr/bin/env bash
# État du labo : conteneurs, santé, réseau isolé, cibles atteignables.
. "$(dirname "$0")/common.sh"
check_env

c_info "Conteneurs du stack"
dc ps

echo
c_info "Réseau isolé 'pentagi-range' (doit être internal=true)"
if docker network inspect pentagi-range >/dev/null 2>&1; then
  internal=$(docker network inspect pentagi-range -f '{{.Internal}}')
  subnet=$(docker network inspect pentagi-range -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
  echo "  internal=${internal}  subnet=${subnet}"
  [[ "${internal}" == "true" ]] && c_grn "  OK : le champ de tir n'a aucune route vers le LAN/Internet." \
                                 || c_red "  ALERTE : le réseau n'est PAS internal. Les cibles/agents peuvent sortir !"
else
  c_ylw "  réseau non créé (labo arrêté ?)"
fi

echo
c_info "Cibles : test d'atteignabilité depuis l'intérieur du réseau isolé"
# On lance un conteneur jetable SUR le réseau isolé pour simuler un agent.
for pair in "juice-shop:3000" "dvwa:80"; do
  host="${pair%%:*}"; port="${pair##*:}"
  if docker run --rm --network pentagi-range curlimages/curl:8.11.1 \
        -sS -o /dev/null -m 5 "http://${host}:${port}/" >/dev/null 2>&1; then
    c_grn "  ${host}:${port} atteignable depuis le réseau isolé."
  else
    c_ylw "  ${host}:${port} pas (encore) prêt — laisse quelques secondes au démarrage."
  fi
done
