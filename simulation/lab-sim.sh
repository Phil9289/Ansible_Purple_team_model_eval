#!/bin/bash
# Simulation du labo fusionné (Strata via passerelle) avec des espaces de noms réseau Linux.
# Chaque « machine » est un netns ; « pve » joue le Proxmox (bridges + VRAI pare-feu nftables du labo).
#
#   sudo ./lab-sim.sh up      # construit le réseau, rend les gabarits Ansible, démarre les services
#   sudo ./lab-sim.sh down    # détruit tout
#
# Machines : agent 10.30.0.10, target 10.30.0.20, logging 10.30.0.30, gateway 10.30.0.40 + 10.40.0.40,
#            strata 10.40.0.42 (vmbr4) + 192.168.1.42 (vmbr0), lan 192.168.1.1, ctl 192.168.1.161 (LXC 300),
#            inet 1.1.1.1 (« Internet »).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/run"
NS="pve agent target logging gateway strata lan ctl inet"

x() { ip netns exec "$@"; }

link() { # link <ns> <ifname-in-ns> <ip/cidr> <bridge-in-pve> <veth-name-in-pve>
  ip link add "$5" type veth peer name "tmp$$"
  ip link set "tmp$$" netns "$1"
  x "$1" ip link set "tmp$$" name "$2"
  x "$1" ip addr add "$3" dev "$2"
  x "$1" ip link set "$2" up
  ip link set "$5" netns pve
  x pve ip link set "$5" master "$4" up
}

down() {
  for n in $NS; do
    [ -e "/run/netns/$n" ] && { ip netns pids "$n" 2>/dev/null | xargs -r kill 2>/dev/null || true; ip netns del "$n"; }
  done
  rm -rf "$RUN/pids"
  echo "Simulation détruite."
}

render() {
  rm -rf "$HERE/inventory"
  cp -r "$HERE/../lab-ansible/inventory" "$HERE/inventory"
  rm -f "$HERE/inventory/group_vars/all/vault.yml"
  cp "$HERE/sim-overrides.yml" "$HERE/inventory/group_vars/all/zz-simulation.yml"
  # Chaque hôte exécute ses modules Python DANS son netns
  # (petit script enveloppe par netns : Ansible récent n'accepte qu'un chemin d'exécutable)
  mkdir -p "$RUN/bin"
  for n in agent target logging gateway ctl; do
    printf '#!/bin/sh\nexec /usr/sbin/ip netns exec %s %s "$@"\n' "$n" "$(command -v python3)" > "$RUN/bin/py-$n"
    chmod +x "$RUN/bin/py-$n"
  done
  for h in agent target logging gateway; do
    printf 'ansible_python_interpreter: "%s"\n' "$RUN/bin/py-$h" >> "$HERE/inventory/host_vars/$h.yml"
  done
  printf 'ansible_python_interpreter: "%s"\n' "$RUN/bin/py-ctl" >> "$HERE/inventory/host_vars/pve.yml"
  (cd "$HERE" && ANSIBLE_CONFIG="$HERE/ansible.cfg" \
     ansible-playbook -i inventory render.yml)
}

up() {
  down >/dev/null 2>&1 || true
  mkdir -p "$RUN/pids" "$RUN/agent" "$RUN/www" "$RUN/log/lab" "$RUN/bin"
  render
  for n in $NS; do ip netns add "$n"; x "$n" ip link set lo up; done

  # --- « Proxmox » : trois bridges, dont vmbr4 SANS adresse IP
  x pve ip link add vmbr3 type bridge; x pve ip addr add 10.30.0.1/24 dev vmbr3; x pve ip link set vmbr3 up
  x pve ip link add vmbr4 type bridge; x pve ip link set vmbr4 up
  x pve ip link add vmbr0 type bridge; x pve ip addr add 192.168.1.116/24 dev vmbr0; x pve ip link set vmbr0 up
  x pve sysctl -qw net.ipv4.ip_forward=1

  # --- VM du labo (noms d'interface côté hôte = ceux de Proxmox : tap<vmid>i<n>, veth<ctid>i<n>)
  link agent   eth0 10.30.0.10/24 vmbr3 tap301i0
  link target  eth0 10.30.0.20/24 vmbr3 tap302i0
  link logging eth0 10.30.0.30/24 vmbr3 tap303i0
  link gateway eth0 10.30.0.40/24 vmbr3 tap304i0
  link gateway eth1 10.40.0.40/24 vmbr4 tap304i1
  for n in agent target logging gateway; do x $n ip route add default via 10.30.0.1; done
  # --- Strata (LXC 242) : eth0 sur le réseau maison, eth1 sur le backend
  link strata  eth0 192.168.1.42/24 vmbr0 veth242i0
  link strata  eth1 10.40.0.42/24   vmbr4 veth242i1
  x strata ip route add default via 192.168.1.1
  x strata sysctl -qw net.ipv4.ip_forward=0
  # --- Réseau maison et « Internet »
  link lan eth0 192.168.1.1/24 vmbr0 vethlan
  link ctl eth0 192.168.1.161/24 vmbr0 vethctl
  x ctl ip route add 10.30.0.0/24 via 192.168.1.116
  ip link add wan0 type veth peer name tmpwan; ip link set wan0 netns pve; ip link set tmpwan netns inet
  x pve ip addr add 203.0.113.1/24 dev wan0; x pve ip link set wan0 up
  x inet ip link set tmpwan name eth0; x inet ip addr add 203.0.113.2/24 dev eth0; x inet ip addr add 1.1.1.1/32 dev eth0
  x inet ip link set eth0 up; x inet ip route add default via 203.0.113.1
  x pve ip route add default via 203.0.113.2
  x lan ip route add default via 192.168.1.116

  # --- Le VRAI pare-feu du labo, rendu depuis roles/proxmox_network/templates/nftables.conf.j2
  # (adapt_nft.py remplace seulement 2 fonctions absentes du noyau de simulation, voir le fichier)
  python3 -I "$HERE/adapt_nft.py" "$RUN/lab.nft" "$RUN/lab-sim.nft"
  x pve nft -f "$RUN/lab-sim.nft"

  # --- Services
  bg() { local n=$1; shift; x "$n" "$@" >"$RUN/pids/$n-$(basename "$1").log" 2>&1 & echo $! > "$RUN/pids/$n-$(basename "$1").pid"; }
  # Faux services « interdits » : ils DOIVENT rester injoignables depuis le labo
  bg pve   python3 -m http.server 8006 --bind 192.168.1.116 --directory "$RUN/www"
  bg lan   python3 -m http.server 80 --directory "$RUN/www"
  bg inet  python3 -m http.server 80 --directory "$RUN/www"
  # Journaux : rsyslog avec la VRAIE config du serveur de journaux (un fichier par IP source)
  sed "s#/var/log/lab/#$RUN/log/lab/#" "$RUN/rsyslog-server.conf" > "$RUN/rsyslog-sim.conf"
  bg logging rsyslogd -n -f "$RUN/rsyslog-sim.conf" -i "$RUN/pids/rsyslogd.pid.real"
  # Cible : nginx avec la VRAIE config du site (listage de répertoire actif)
  echo "Fichier de test de la cible du lab (contenu fictif)." > "$RUN/www/notes-internes.txt"
  sed "s#/var/www/html#$RUN/www#" "$RUN/nginx-site.conf" > "$RUN/nginx-site-sim.conf"
  cat > "$RUN/nginx.conf" <<NGX
worker_processes 1; pid $RUN/pids/nginx.pid.real; error_log $RUN/nginx-error.log;
events {} http { access_log $RUN/nginx-access.log; include /etc/nginx/mime.types; include $RUN/nginx-site-sim.conf; }
NGX
  bg target nginx -g "daemon off;" -c "$RUN/nginx.conf"
  # Faux Strata (écoute sur 0.0.0.0:8080, comme le vrai : joignable par vmbr0 ET vmbr4)
  bg strata python3 -I "$HERE/mock_strata.py"
  sleep 1
  # Passerelle : le VRAI programme du rôle strata_gateway, avec la config rendue
  bg gateway env $(grep -v '^#' "$RUN/gateway.env" | xargs) python3 -I "$HERE/../lab-ansible/roles/strata_gateway/files/strata_gateway.py"
  # « logger » de l'agent : envoie au serveur de journaux comme le ferait rsyslog (rôle common)
  printf '#!/bin/sh\nexec /usr/bin/logger -n 10.30.0.30 -P 514 -T "$@"\n' > "$RUN/bin/logger"; chmod +x "$RUN/bin/logger"
  sleep 1
  echo "Simulation prête. Tests : sudo $HERE/run-tests.sh"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down"; exit 1 ;;
esac
