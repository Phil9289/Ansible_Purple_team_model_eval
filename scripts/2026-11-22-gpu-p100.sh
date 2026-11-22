#!/bin/bash
# ==============================================================================
# 2026-11-22 : la VM agent utilise la Tesla P100 (passthrough, partage à tour de rôle).
# À exécuter DANS le LXC 300, en root : bash 2026-11-22-gpu-p100.sh
# Modifie seulement des fichiers de /root/lab-ansible (sauvegarde avant). Ne déploie rien.
#
#   1. proxmox_vms : la tâche « Attacher la P100 » passe par `qm set` sur le Proxmox
#      (machine q35 + hostpci0 mapping=p100 + hookscript). Le jeton API n'a donc
#      besoin d'aucun droit en plus (et seul root@pam peut poser un hookscript).
#   2. Hookscript /var/lib/vz/snippets/p100-hook.sh sur le Proxmox :
#        pre-start : refuse de démarrer la VM si un conteneur utilise la P100
#        post-stop : redonne la P100 au pilote nvidia (plus besoin de redémarrer)
#   3. agent_host (si gpu_passthrough) : dépôt non-free, pilote NVIDIA + Vulkan,
#      redémarrage de la VM, llama.cpp version Vulkan dans /opt/llama-vulkan, -ngl 99
#   4. gpu_passthrough: true
# ==============================================================================
set -euo pipefail
cd /root/lab-ansible

BACKUP=/root/lab-ansible-avant-gpu-p100.tgz
VMS=roles/proxmox_vms/tasks/main.yml
TASKS=roles/agent_host/tasks/main.yml
UNIT=roles/agent_host/templates/llama-server.service.j2
VARS=inventory/group_vars/all/vars.yml
AGENT=inventory/host_vars/agent.yml
VULKAN_URL="https://github.com/ggml-org/llama.cpp/releases/download/b12549/llama-b12549-bin-ubuntu-vulkan-x64.tar.gz"

# --- 0. Garde-fous -----------------------------------------------------------
[ -e "$BACKUP" ] && { echo "ERREUR : $BACKUP existe déjà. Script déjà exécuté ?"; exit 1; }
grep -q '^- name: Attacher la P100 à la VM agent' "$VMS" || { echo "ERREUR : tâche P100 introuvable dans $VMS"; exit 1; }
grep -q '^- name: Déployer le service systemd pour llama-server' "$TASKS" || { echo "ERREUR : tâche du service llama-server introuvable"; exit 1; }
grep -q -- '-t {{ llama_threads }}' "$UNIT" || { echo "ERREUR : $UNIT inattendu"; exit 1; }
grep -q '^gpu_passthrough: false' "$VARS" || { echo "ERREUR : 'gpu_passthrough: false' introuvable dans $VARS"; exit 1; }
grep -q '^llama_install_dir:' "$AGENT" && grep -q '^llama_release_url:' "$AGENT" \
    || { echo "ERREUR : llama_install_dir / llama_release_url absents de $AGENT"; exit 1; }
echo "=== Vérification de l'archive llama.cpp Vulkan ==="
if ! curl -sfIL -o /dev/null "$VULKAN_URL"; then
    echo "ERREUR : $VULKAN_URL introuvable. Archives Linux disponibles pour b12549 :"
    curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/b12549 | grep -o '"name": *"[^"]*ubuntu[^"]*"' || true
    echo "Rien n'est modifié. Envoie cette liste à Claude."
    exit 1
fi
echo "OK"

tar czf "$BACKUP" --exclude=lab-ansible/models-cache -C /root lab-ansible
ls -lh "$BACKUP"

# --- 1. Variables -------------------------------------------------------------
sed -i 's/^gpu_passthrough: false/gpu_passthrough: true/' "$VARS"
grep -q '^gpu_pci_address:' "$VARS" || cat >> "$VARS" << 'EOF'

# --- P100 partagée à tour de rôle (VM agent <-> conteneurs 240/242/245) ---
gpu_pci_address: "0000:04:00.0"
gpu_hookscript: "local:snippets/p100-hook.sh"
gpu_hookscript_path: "/var/lib/vz/snippets/p100-hook.sh"
EOF

grep -q '^llama_gpu_layers:' "$AGENT" || cat >> "$AGENT" << EOF

# --- Moteur GPU (P100) : choisi automatiquement selon gpu_passthrough ---
llama_release_url_gpu: "$VULKAN_URL"
llama_gpu_layers: "{{ 99 if gpu_passthrough | bool else 0 }}"
EOF
# llama.cpp GPU dans un dossier séparé (le "creates" de l'unarchive ne réinstalle pas sinon)
python3 - "$AGENT" << 'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
s, n1 = re.subn(r'^llama_install_dir:.*$',
    "llama_install_dir: \"{{ '/opt/llama-vulkan' if gpu_passthrough | bool else '/opt/llama' }}\"", s, flags=re.M)
s, n2 = re.subn(r'^llama_release_url:.*$',
    "llama_release_url: \"{{ llama_release_url_gpu if gpu_passthrough | bool else llama_release_url_cpu }}\"\nllama_release_url_cpu: \"https://github.com/ggml-org/llama.cpp/releases/download/b12549/llama-b12549-bin-ubuntu-x64.tar.gz\"", s, flags=re.M)
if n1 != 1 or n2 != 1:
    raise SystemExit("ERREUR : llama_install_dir / llama_release_url introuvables dans %s (n=%d,%d)" % (p, n1, n2))
open(p, 'w', encoding='utf-8').write(s)
print("host_vars/agent.yml mis à jour")
PY
grep -q '^llama_gpu_layers:' roles/agent_host/defaults/main.yml || echo 'llama_gpu_layers: 0' >> roles/agent_host/defaults/main.yml

# --- 2. Hookscript --------------------------------------------------------------
mkdir -p roles/proxmox_vms/templates
cat > roles/proxmox_vms/templates/p100-hook.sh.j2 << 'EOF'
#!/bin/sh
# {{ ansible_managed }}
# Hookscript de la VM agent : partage de la Tesla P100 avec les conteneurs.
dev={{ gpu_pci_address }}
case "$2" in
  pre-start)
    if command -v nvidia-smi >/dev/null 2>&1 && \
       nvidia-smi --query-compute-apps=gpu_bus_id --format=csv,noheader 2>/dev/null | grep -qi "${dev#0000:}"; then
        echo "P100 utilisée par un conteneur : éteins-le (240, 242, 245) avant de démarrer la VM $1."
        exit 1
    fi ;;
  post-stop)
    [ -e /sys/bus/pci/drivers/vfio-pci/$dev ] && echo $dev > /sys/bus/pci/drivers/vfio-pci/unbind
    [ -e /sys/bus/pci/drivers/nvidia/$dev ] || echo $dev > /sys/bus/pci/drivers/nvidia/bind
    echo "P100 rendue au pilote nvidia." ;;
esac
exit 0
EOF
grep -q 'pre-start' roles/proxmox_vms/templates/p100-hook.sh.j2 || { echo "ERREUR : hookscript non écrit"; exit 1; }

# --- 3. proxmox_vms : remplacer la tâche d'attache de la P100 -----------------------
python3 - "$VMS" << 'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
debut = s.index("- name: Attacher la P100 à la VM agent")
fin = s.index("\n- name:", debut + 1)
s = s[:debut] + '''- name: Vérifier que le stockage local accepte les snippets (hookscript)
  ansible.builtin.command: pvesm status --content snippets
  register: snippets_storage
  changed_when: false
  delegate_to: "{{ groups['proxmox_host'][0] }}"
  when: gpu_passthrough | bool

- name: Arrêter si le stockage local n'accepte pas les snippets
  ansible.builtin.assert:
    that: "'local ' in snippets_storage.stdout"
    fail_msg: >-
      Le stockage 'local' n'accepte pas les snippets. Sur le Proxmox, une seule fois :
      pvesm set local --content "$(pvesm config local | awk '/content/{print $2}'),snippets"
  when: gpu_passthrough | bool

- name: Déployer le hookscript de partage de la P100 sur le Proxmox
  ansible.builtin.template:
    src: p100-hook.sh.j2
    dest: "{{ gpu_hookscript_path }}"
    mode: "0755"
  delegate_to: "{{ groups['proxmox_host'][0] }}"
  when: gpu_passthrough | bool

- name: Lire la configuration actuelle de la VM agent
  ansible.builtin.command: "qm config {{ hostvars[groups['attacker'][0]]['vmid'] }}"
  register: agent_qm_config
  changed_when: false
  delegate_to: "{{ groups['proxmox_host'][0] }}"
  when: gpu_passthrough | bool

- name: Attacher la P100 à la VM agent (q35 + mapping + hookscript, VM éteinte seulement)
  ansible.builtin.command: >-
    qm set {{ hostvars[groups['attacker'][0]]['vmid'] }}
    --machine q35
    --hostpci0 mapping={{ gpu_pci_mapping }},pcie=1
    --hookscript {{ gpu_hookscript }}
  delegate_to: "{{ groups['proxmox_host'][0] }}"
  when:
    - gpu_passthrough | bool
    - groups['attacker'][0] not in running_vms
    - >-
      ("mapping=" ~ gpu_pci_mapping) not in agent_qm_config.stdout
      or ("hookscript: " ~ gpu_hookscript) not in agent_qm_config.stdout
      or "machine: q35" not in agent_qm_config.stdout
''' + s[fin:]
open(p, 'w', encoding='utf-8').write(s)
print("proxmox_vms mis à jour")
PY

# --- 4. agent_host : pilote NVIDIA + Vulkan ----------------------------------------
cat > roles/agent_host/tasks/gpu.yml << 'EOF'
---
# Exécuté seulement si gpu_passthrough est vrai. Nécessite Internet (mode provisioning).
- name: Ajouter les composants non-free de Debian (pilote NVIDIA)
  ansible.builtin.deb822_repository:
    name: debian-nonfree
    types: [deb]
    uris: [http://deb.debian.org/debian]
    suites: ["{{ ansible_distribution_release }}", "{{ ansible_distribution_release }}-updates"]
    components: [non-free, non-free-firmware]
    signed_by: /usr/share/keyrings/debian-archive-keyring.gpg

- name: Installer le pilote NVIDIA, Vulkan et les en-têtes du noyau
  ansible.builtin.apt:
    name:
      - "linux-headers-{{ ansible_kernel }}"
      - nvidia-driver
      - nvidia-kernel-dkms
      - nvidia-smi
      - firmware-misc-nonfree
      - nvidia-vulkan-icd
      - libvulkan1
      - vulkan-tools
    state: present
    update_cache: true
    install_recommends: false
  register: nvidia_install

- name: Redémarrer la VM pour charger le pilote NVIDIA (première installation seulement)
  ansible.builtin.reboot:
    reboot_timeout: 600
  when: nvidia_install is changed

- name: Vérifier que la P100 est vue par le pilote
  ansible.builtin.command: nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
  register: nvidia_smi
  changed_when: false

- name: Afficher la carte détectée
  ansible.builtin.debug:
    msg: "GPU : {{ nvidia_smi.stdout }}"

- name: Donner à l'utilisateur de service l'accès au GPU (groupes video et render)
  ansible.builtin.user:
    name: "{{ ansible_svc_user }}"
    groups: [video, render]
    append: true
  notify: Redémarrer llama-server
EOF

python3 - "$TASKS" << 'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
if "import_tasks: gpu.yml" not in s:
    cible = "- name: Déployer le service systemd pour llama-server"
    s = s.replace(cible, '''- name: Préparer le GPU (pilote NVIDIA + Vulkan) si la P100 est attachée
  ansible.builtin.import_tasks: gpu.yml
  when: gpu_passthrough | bool

''' + cible, 1)
open(p, 'w', encoding='utf-8').write(s)
print("agent_host/tasks/main.yml mis à jour")
PY

sed -i 's/-t {{ llama_threads }}/-t {{ llama_threads }} -ngl {{ llama_gpu_layers }}/' "$UNIT"
grep -q '^SupplementaryGroups=' "$UNIT" || sed -i '/^Group=/a SupplementaryGroups=video render' "$UNIT"

# --- Vérifications -------------------------------------------------------------
echo
echo "=== Variables vues par l'agent ==="
ansible-inventory --host agent --yaml | grep -E "^(gpu_passthrough|llama_install_dir|llama_release_url|llama_gpu_layers):" || true
echo
echo "=== Service llama-server (template) ==="
grep -E "ExecStart|Groups" "$UNIT"
echo
echo "=== Syntaxe ==="
for pb in site.yml 01-infra.yml 05-agent.yml; do ansible-playbook --syntax-check "$pb"; done
echo
echo "=== Prêt. Rien n'est déployé. Suite dans le message de Claude. ==="
