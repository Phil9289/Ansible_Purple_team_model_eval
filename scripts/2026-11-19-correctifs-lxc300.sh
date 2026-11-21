#!/bin/bash
# Correctifs du 2026-11-19, a executer DANS le LXC 300 (noeud de controle Ansible).
#   1. Route permanente vers le lab (10.30.0.0/24 via pve)
#   2. Table nftables lab_l2 restreinte au bridge du lab (vmbr3)
#   3. wait_for_connection plus patient (delay + sleep)
#   4. Hot-plug reseau : ne plus reconfigurer une VM deja allumee
# Sauvegardes : fichiers *.bak a cote des fichiers modifies.
set -e
cd /root/lab-ansible

cp -a roles/proxmox_vms/tasks/main.yml roles/proxmox_vms/tasks/main.yml.bak
cp -a roles/proxmox_network/templates/nftables.conf.j2 roles/proxmox_network/templates/nftables.conf.j2.bak
cp -a 01-infra.yml 01-infra.yml.bak

# --- 1. Route permanente (if-up.d n'est pas reecrit par Proxmox) -------------
cat > /etc/network/if-up.d/lab-route << 'EOF'
#!/bin/sh
[ "$IFACE" = "eth0" ] || exit 0
ip route replace 10.30.0.0/24 via 192.168.1.116 dev eth0
EOF
chmod +x /etc/network/if-up.d/lab-route
ip route replace 10.30.0.0/24 via 192.168.1.116 dev eth0

# --- 2 et 3. Edition du template nftables et de 01-infra.yml -----------------
python3 - << 'PY'
p = 'roles/proxmox_network/templates/nftables.conf.j2'
s = open(p).read()
old = 'table bridge lab_l2 {\n    chain forward {\n        type filter hook forward priority 0; policy accept;\n'
assert old in s and 'ibrname' not in s, 'template inattendu, rien modifie'
new = old + '\n        # Ne rien filtrer en dehors du bridge du lab (vmbr0, Security Onion, Ludus...)\n        meta ibrname != "{{ lab_bridge }}" accept\n'
open(p, 'w').write(s.replace(old, new, 1))

p = '01-infra.yml'
s = open(p).read()
old = '        timeout: 300\n'
assert old in s and 'delay:' not in s, '01-infra.yml inattendu, rien modifie'
open(p, 'w').write(s.replace(old, '        delay: 15\n        sleep: 5\n        timeout: 300\n', 1))
PY

# --- 4. Role proxmox_vms : reconfigurer seulement les VM qui ne tournent pas --
cat > roles/proxmox_vms/tasks/main.yml << 'EOF'
---
- name: Cloner chaque VM du lab depuis le template
  community.proxmox.proxmox_kvm:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    node: "{{ proxmox_node }}"
    clone: "{{ lab_template_name }}"
    newid: "{{ hostvars[item]['vmid'] }}"
    name: "{{ item }}"
    full: true
    storage: "{{ lab_storage }}"
    timeout: 300
  loop: "{{ groups['lab'] }}"
  no_log: true

- name: Agrandir le disque système scsi0 si supérieur à 20 Go
  community.proxmox.proxmox_disk:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    vmid: "{{ hostvars[item]['vmid'] }}"
    disk: scsi0
    size: "{{ hostvars[item]['disk_gb'] }}G"
    state: resized
  loop: "{{ groups['lab'] }}"
  when: hostvars[item]['disk_gb'] | int > 20
  no_log: true

- name: Lire l'état de chaque VM (une VM allumée ne doit pas être reconfigurée à chaud)
  community.proxmox.proxmox_vm_info:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ hostvars[item]['vmid'] }}"
  loop: "{{ groups['lab'] }}"
  register: vm_info
  no_log: true

- name: Repérer les VM déjà allumées
  ansible.builtin.set_fact:
    running_vms: "{{ vm_info.results | selectattr('proxmox_vms.0.status', 'equalto', 'running') | map(attribute='item') | list }}"

- name: Configurer ressources, réseau vmbr3 et cloud-init (VM éteintes seulement)
  community.proxmox.proxmox_kvm:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ hostvars[item]['vmid'] }}"
    name: "{{ item }}"
    cores: "{{ hostvars[item]['vcpu'] }}"
    memory: "{{ hostvars[item]['ram_mb'] }}"
    net:
      net0: "virtio,bridge={{ lab_bridge }},firewall=0"
    ipconfig:
      ipconfig0: "ip={{ hostvars[item]['ansible_host'] }}/24,gw={{ lab_gateway }}"
    nameservers:
      - "{{ lab_dns }}"
    ciuser: "{{ ansible_svc_user }}"
    sshkeys: "{{ lookup('file', lab_ssh_pubkey) }}"
    update: true
    update_unsafe: true
  loop: "{{ groups['lab'] }}"
  when: item not in running_vms
  no_log: true

- name: Attacher la P100 à la VM agent (VM éteinte seulement)
  community.proxmox.proxmox_kvm:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ hostvars[groups['attacker'][0]]['vmid'] }}"
    hostpci:
      hostpci0: "mapping={{ gpu_pci_mapping }},pcie=1"
    update: true
    update_unsafe: true
  when: gpu_passthrough | bool and groups['attacker'][0] not in running_vms
  no_log: true

- name: Démarrer chaque VM du lab
  community.proxmox.proxmox_kvm:
    api_host: "{{ vault_proxmox_api_host }}"
    validate_certs: false
    api_user: "{{ vault_proxmox_api_user }}"
    api_token_id: "{{ vault_proxmox_api_token_id }}"
    api_token_secret: "{{ vault_proxmox_api_token_secret }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ hostvars[item]['vmid'] }}"
    state: started
    timeout: 300
  loop: "{{ groups['lab'] }}"
  no_log: true
EOF

# --- Verification : 2 passages (le 2e doit afficher changed=0), puis ping ----
ansible-playbook 01-infra.yml
ansible-playbook 01-infra.yml
ansible lab -m ping
# fin
