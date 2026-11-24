#!/bin/bash
# Prépare et lance Strata (profil Dual-3-A1) avec 64k de contexte, pour Hermes Agent.
# À lancer PAR PHIL, en root DANS le LXC 242 :   pct enter 242   puis   bash strata-64k.sh [prepare|start|check]
#
#   prepare : copie les scripts du profil A1 en *_64k.sh (32768 -> 65536). Ne touche pas aux originaux.
#   start   : arrête le Strata en cours, lance la version 64k, attend l'API.
#   check   : contexte annoncé, adresse d'écoute, VRAM et températures, une requête de test.
#
# Repli si la VRAM manque au démarrage : KV=q4_0 bash strata-64k.sh prepare  (puis start).
set -euo pipefail
CTX="${CTX:-65536}"
KV="${KV:-int8}"
BG="/root/start_bg_dual_inv_a1.sh"          # lanceur du profil champion (fiche Hermes/Strata)
BG64="/root/start_bg_dual_inv_a1_64k.sh"
API="http://127.0.0.1:8080"

prepare() {
  [ -f "$BG" ] || { echo "Introuvable : $BG (ls /root/*.sh pour trouver le lanceur A1)"; exit 1; }
  # Le lanceur appelle un run_server_*.sh : on copie les deux pour ne rien modifier de l'original.
  RUN=$(grep -oE '[^ "]*run_server[^ "]*\.sh' "$BG" | head -1 || true)
  echo "Lanceur : $BG ; serveur : ${RUN:-aucun (options dans le lanceur)}"
  for f in "$BG" ${RUN:+"$RUN"}; do
    out="${f%.sh}_64k.sh"
    sed -E "s/--max-context[ =][0-9]+/--max-context $CTX/g; s/--kv[ =][a-z0-9_]+/--kv $KV/g" "$f" > "$out"
    [ -n "$RUN" ] && sed -i "s#$RUN#${RUN%.sh}_64k.sh#g" "$out"
    chmod +x "$out"; echo "  écrit $out"
  done
  # Le contexte peut aussi être dans le JSON du profil (strata-iq2_xs-dual-inv*.json)
  for j in /root/Strata/*dual-inv*.json /root/*dual-inv*.json; do
    [ -f "$j" ] && grep -nE '32768|max_context|"kv"' "$j" | sed "s#^#  $j: #" || true
  done
  echo "Vérifie ci-dessous que 32768 n'apparaît plus et que --max-context $CTX --kv $KV est présent :"
  grep -nE 'max-context|--kv|32768|--host|--port' "${BG64}" ${RUN:+"${RUN%.sh}_64k.sh"} || true
}

start() {
  [ -x "$BG64" ] || prepare
  pkill -f "engine-cuda12/strata" || true; sleep 5
  "$BG64"
  echo -n "Chargement du modèle (68 Go, plusieurs minutes)"
  for i in $(seq 1 120); do curl -sf -m 3 "$API/v1/models" >/dev/null && { echo " prêt."; return 0; }; echo -n .; sleep 10; done
  echo; echo "L'API ne répond pas après 20 min : tail -n 50 des journaux de Strata, et nvidia-smi."; exit 1
}

check() {
  echo "--- /v1/models"; curl -s -m 5 "$API/v1/models"; echo
  echo "--- Écoute (doit être 0.0.0.0:8080 ou inclure 10.40.0.42, sinon la passerelle ne joindra pas Strata)"
  ss -ltnp | grep ':8080' || echo "rien sur 8080 !"
  echo "--- Interfaces (eth1 10.40.0.42 apparaît après 01-infra.yml)"; ip -br addr
  echo "--- ip_forward (doit être 0)"; cat /proc/sys/net/ipv4/ip_forward
  echo "--- GPU"; nvidia-smi --query-gpu=index,name,memory.used,memory.total,temperature.gpu --format=csv
  echo "--- Requête de test"
  t0=$(date +%s)
  curl -s -m 300 "$API/v1/chat/completions" -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Reply exactly STRATA_64K_OK"}],"max_tokens":512}' \
    | python3 -c 'import json,sys;r=json.load(sys.stdin);print(r["choices"][0]["message"]["content"].strip());print("timings:",r.get("timings",{}))'
  echo "($(( $(date +%s) - t0 )) s)"
}

case "${1:-check}" in prepare) prepare;; start) start;; check) check;; *) echo "usage: $0 prepare|start|check"; exit 1;; esac
