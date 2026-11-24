#!/bin/bash
# Test de bout en bout du labo simulé (à lancer après ./lab-sim.sh up).
# Rôles : agent = machine qui envoie les commandes, target = cible, logging = machine qui vérifie les journaux.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; RUN="$HERE/run"
x() { ip netns exec "$@"; }
PASS=0; FAIL=0
ok()  { echo "  [OK]    $1"; PASS=$((PASS+1)); }
ko()  { echo "  [ÉCHEC] $1"; FAIL=$((FAIL+1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
KEY="$(grep ^HERMES_LLM_API_KEY= "$RUN/hermes.env" | cut -d= -f2-)"
GW=http://10.30.0.40:8000
code() { x "$1" curl -s -o /dev/null -w '%{http_code}' -m 5 "${@:2}"; }
stats() { x strata curl -s http://127.0.0.1:8080/sim/stats; }

echo "== 1. Mission de l'agent (agent -> passerelle -> Strata, agent -> cible, journaux -> logging)"
rm -f "$RUN/agent/attack_report.json"
( set -a; . "$RUN/hermes.env"; set +a; PATH="$RUN/bin:$PATH" x agent python3 "$RUN/hermes_agent.py" ) > "$RUN/mission.out" 2>&1
check "le rapport attack_report.json existe" "test -s $RUN/agent/attack_report.json"
check "exploit_status = SUCCESS" "grep -q '\"exploit_status\": \"SUCCESS\"' $RUN/agent/attack_report.json"
check "l'analyse vient du modèle de Strata" "grep -q 'Service détecté' $RUN/agent/attack_report.json"
sleep 1
AL="$RUN/log/lab/10.30.0.10.log"
for tag in AGENT-INIT RECON EXPLOIT AGENT-FINISH; do check "journal $tag reçu par le serveur logging" "grep -q '\[$tag\]' $AL"; done
GL="$RUN/log/lab/10.30.0.40.log"
check "la passerelle journalise la requête de chat" "grep -q '\"event\": \"chat\"' $GL"
check "la cible a journalisé la requête de l'agent" "grep -q '10.30.0.10' $RUN/nginx-access.log"

echo "== 2. La passerelle filtre (depuis l'agent)"
[ "$(code agent $GW/v1/models)" = 401 ] && ok "sans clé -> 401" || ko "sans clé -> 401"
[ "$(code agent -H 'Authorization: Bearer mauvaise-cle-xxxxxxxxxxxxxxxx' $GW/v1/models)" = 401 ] && ok "mauvaise clé -> 401" || ko "mauvaise clé -> 401"
for p in / /api/models/delete /v1/completions /props /slots; do
  c=$(code agent -H "Authorization: Bearer $KEY" -X POST -d '{}' "$GW$p"); [ "$c" = 404 ] && ok "$p -> 404" || ko "$p -> $c (404 attendu)"
done
c=$(code agent -H "Authorization: Bearer $KEY" $GW/v1/models); [ "$c" = 200 ] && ok "/v1/models avec clé -> 200" || ko "/v1/models -> $c"
big=$(python3 -c "print('{\"messages\":[{\"role\":\"user\",\"content\":\"' + 'a'*300000 + '\"}]}')")
c=$(echo "$big" | x agent curl -s -o /dev/null -w '%{http_code}' -m 10 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' --data-binary @- $GW/v1/chat/completions)
[ "$c" = 413 ] || [ "$c" = 400 ] && ok "prompt trop long refusé ($c)" || ko "prompt trop long -> $c"

echo "== 3. Isolation réseau (l'agent ne doit rien atteindre d'autre)"
for t in "10.40.0.42:8080 Strata en direct (backend)" "192.168.1.42:8080 Strata par le réseau maison" \
         "192.168.1.1:80 réseau maison" "192.168.1.116:8006 interface Proxmox" "1.1.1.1:80 Internet"; do
  set -- $t; x agent timeout 4 bash -c "</dev/tcp/${1%:*}/${1#*:}" 2>/dev/null && ko "agent -> ${*:2} JOIGNABLE" || ok "agent -> ${*:2} bloqué"
done
x agent timeout 4 bash -c "</dev/tcp/10.30.0.40/22" 2>/dev/null && ko "agent -> SSH passerelle joignable" || ok "agent -> SSH passerelle bloqué"
echo "   (depuis la passerelle)"
x gateway timeout 4 bash -c "</dev/tcp/10.40.0.42/8080" 2>/dev/null && ok "passerelle -> Strata backend autorisé" || ko "passerelle -> Strata backend"
for t in "192.168.1.42:8080 Strata via vmbr0" "192.168.1.1:80 réseau maison" "1.1.1.1:80 Internet" "192.168.1.116:8006 Proxmox" "10.30.0.10:22 SSH agent"; do
  set -- $t; x gateway timeout 4 bash -c "</dev/tcp/${1%:*}/${1#*:}" 2>/dev/null && ko "passerelle -> ${*:2} JOIGNABLE" || ok "passerelle -> ${*:2} bloqué"
done
echo "   (depuis Strata : ne doit pas pouvoir ouvrir de connexion vers la passerelle ni le labo)"
x strata timeout 4 bash -c "</dev/tcp/10.40.0.40/8000" 2>/dev/null && ko "Strata -> passerelle joignable" || ok "Strata -> passerelle bloqué"
x strata timeout 4 bash -c "</dev/tcp/10.30.0.20/8080" 2>/dev/null && ko "Strata -> cible joignable" || ok "Strata -> labo bloqué"

echo "== 4. File d'attente : 1 requête à la fois vers Strata"
before=$(stats | python3 -c 'import json,sys;print(json.load(sys.stdin)["requests"])')
for i in 1 2 3; do
  x agent curl -s -m 60 -o "$RUN/par$i.json" -w '%{http_code}\n' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Reply exactly PAR$i $(printf 'x%.0s' $(seq 1 3000))\"}]}" $GW/v1/chat/completions > "$RUN/par$i.code" &
done; wait
n200=$(cat "$RUN"/par*.code | grep -c 200)
[ "$n200" = 3 ] && ok "3 requêtes parallèles servies (en série)" || ko "requêtes parallèles : $n200/3 en 200"
ma=$(stats | python3 -c 'import json,sys;print(json.load(sys.stdin)["max_active"])')
[ "$ma" = 1 ] && ok "Strata n'a jamais eu plus d'une requête à la fois (max_active=1)" || ko "max_active=$ma"

echo "== 5. Streaming SSE et appels d'outils (comme le vrai Hermes Agent)"
out=$(x agent curl -sN -m 30 -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"stream":true,"messages":[{"role":"user","content":"Lance un scan nmap de 10.30.0.20"}],"tools":[{"type":"function","function":{"name":"terminal","parameters":{"type":"object","properties":{"command":{"type":"string"}}}}}]}' \
  $GW/v1/chat/completions)
echo "$out" | grep -q 'data: \[DONE\]' && ok "flux SSE complet jusqu'à [DONE]" || ko "flux SSE incomplet"
echo "$out" | grep -q '"tool_calls"' && ok "appel d'outil relayé en streaming" || ko "pas d'appel d'outil"
echo "$out" | grep -q 'nmap -sV' && ok "arguments de l'outil intacts" || ko "arguments de l'outil"

echo "== 6. Bilan côté Strata"
S=$(stats); echo "   $S"
echo "$S" | python3 -c 'import json,sys;s=json.load(sys.stdin);sys.exit(0 if s["admin_hits"]==0 else 1)' && ok "route d'admin jamais atteinte" || ko "route d'admin atteinte !"
echo "$S" | python3 -c 'import json,sys;s=json.load(sys.stdin);sys.exit(0 if s["ui_hits"]==0 else 1)' && ok "interface web jamais atteinte" || ko "interface web atteinte"
echo "$S" | python3 -c 'import json,sys;s=json.load(sys.stdin);c=set(s["clients"])-{"127.0.0.1"};sys.exit(0 if c=={"10.40.0.40"} else 1)' && ok "seule la passerelle (10.40.0.40) parle à Strata" || ko "autres clients vus par Strata"

echo; echo "RÉSULTAT : $PASS réussis, $FAIL échoués"
[ $FAIL -eq 0 ]
