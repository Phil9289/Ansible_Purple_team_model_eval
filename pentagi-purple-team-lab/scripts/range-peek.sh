#!/usr/bin/env bash
# Jeter un oeil aux cibles toi-même, SANS casser l'isolation.
# Comme le réseau est "internal", on ouvre un tunnel temporaire local->cible
# via un conteneur socat jetable attaché au réseau isolé.
#   ./scripts/range-peek.sh juice   # expose Juice Shop sur http://127.0.0.1:13000
#   ./scripts/range-peek.sh dvwa    # expose DVWA       sur http://127.0.0.1:13080
# Ctrl-C pour fermer le tunnel (rien n'est laissé ouvert).
. "$(dirname "$0")/common.sh"

case "${1:-}" in
  juice) target="juice-shop:3000"; lport=13000 ;;
  dvwa)  target="dvwa:80";          lport=13080 ;;
  *) die "usage: $0 {juice|dvwa}" ;;
esac

c_info "Tunnel 127.0.0.1:${lport} -> ${target} (réseau isolé). Ctrl-C pour fermer."
c_info "Ouvre : http://127.0.0.1:${lport}/"
docker run --rm -it \
  --network pentagi-range \
  -p "127.0.0.1:${lport}:${lport}" \
  alpine/socat:1.8.0.0 \
  "TCP-LISTEN:${lport},fork,reuseaddr" "TCP:${target}"
