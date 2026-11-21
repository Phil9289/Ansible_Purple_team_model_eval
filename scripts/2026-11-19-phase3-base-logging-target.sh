#!/bin/bash
# Phase 3 du plan (T011 a T014) : roles common, log_server, web_target
# + playbooks 02-base, 03-logging, 04-target + site.yml.
# A executer DANS le LXC 300 (noeud de controle Ansible).
set -e
cd /root/lab-ansible

# --- 0. Reparation des accents de roles/proxmox_vms (corrompus a l'envoi precedent) ---
python3 - << 'PY'
p = 'roles/proxmox_vms/tasks/main.yml'
s = open(p, encoding='utf-8').read()
if '\u00c3' in s:
    open(p + '.bak2', 'w', encoding='utf-8').write(s)
    try:
        fixed = s.encode('cp1252').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError) as e:
        raise SystemExit('Reparation impossible, fichier non modifie : %s' % e)
    open(p, 'w', encoding='utf-8').write(fixed)
    print('Accents repares dans', p)
else:
    print('Accents deja corrects dans', p)
PY

mkdir -p roles/common/{tasks,handlers,templates,defaults}
mkdir -p roles/log_server/{tasks,handlers,templates}
mkdir -p roles/web_target/{tasks,handlers,templates,defaults}

# =============================== role common ===============================
cat > roles/common/tasks/main.yml << 'EOF'
---
- name: Installer rsyslog et sudo (absents de l'image Debian minimale)
  ansible.builtin.apt:
    name:
      - rsyslog
      - sudo
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Confirmer l'utilisateur de service (déjà créé par cloud-init)
  ansible.builtin.user:
    name: "{{ ansible_svc_user }}"
    groups: sudo
    append: true
    shell: /bin/bash

- name: Installer la clé publique du nœud de contrôle
  ansible.posix.authorized_key:
    user: "{{ ansible_svc_user }}"
    key: "{{ lookup('file', lab_ssh_pubkey) }}"

- name: Donner sudo sans mot de passe à l'utilisateur de service
  ansible.builtin.copy:
    content: "{{ ansible_svc_user }} ALL=(ALL) NOPASSWD:ALL\n"
    dest: "/etc/sudoers.d/{{ ansible_svc_user }}"
    mode: "0440"
    validate: "visudo -cf %s"

- name: Déployer la configuration sshd durcie
  ansible.builtin.template:
    src: sshd_config.j2
    dest: /etc/ssh/sshd_config
    mode: "0644"
    validate: "/usr/sbin/sshd -t -f %s"
  notify: redémarrer ssh

- name: Déployer la configuration client rsyslog (pas sur le serveur de journaux)
  ansible.builtin.template:
    src: rsyslog-client.conf.j2
    dest: /etc/rsyslog.d/60-lab.conf
    mode: "0644"
  when: inventory_hostname not in groups['logs']
  notify: redémarrer rsyslog

- name: S'assurer que rsyslog est actif au démarrage
  ansible.builtin.systemd:
    name: rsyslog
    state: started
    enabled: true
EOF

cat > roles/common/handlers/main.yml << 'EOF'
---
- name: redémarrer ssh
  ansible.builtin.systemd:
    name: ssh
    state: restarted

- name: redémarrer rsyslog
  ansible.builtin.systemd:
    name: rsyslog
    state: restarted
EOF

cat > roles/common/templates/sshd_config.j2 << 'EOF'
# Géré par Ansible : ne pas modifier à la main.
Port 22
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM yes
AllowUsers {{ ansible_svc_user }}
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

cat > roles/common/templates/rsyslog-client.conf.j2 << 'EOF'
# Géré par Ansible : envoie tous les journaux au serveur de journaux du lab (TCP).
*.* @@{{ hostvars[groups['logs'][0]]['ansible_host'] }}:514
EOF

# ============================== role log_server ============================
cat > roles/log_server/tasks/main.yml << 'EOF'
---
- name: Créer le dossier des journaux du lab
  ansible.builtin.file:
    path: /var/log/lab
    state: directory
    owner: root
    group: adm
    mode: "0750"

- name: Déployer la configuration serveur rsyslog
  ansible.builtin.template:
    src: rsyslog-server.conf.j2
    dest: /etc/rsyslog.d/10-server.conf
    mode: "0644"
  notify: redémarrer rsyslog serveur

- name: S'assurer que rsyslog est actif au démarrage
  ansible.builtin.systemd:
    name: rsyslog
    state: started
    enabled: true
EOF

cat > roles/log_server/handlers/main.yml << 'EOF'
---
- name: redémarrer rsyslog serveur
  ansible.builtin.systemd:
    name: rsyslog
    state: restarted
EOF

cat > roles/log_server/templates/rsyslog-server.conf.j2 << 'EOF'
# Géré par Ansible.
module(load="imtcp")

# Un fichier par IP SOURCE RÉELLE de la connexion (%FROMHOST-IP%), pas par nom
# d'hôte déclaré : une VM compromise ne peut pas écrire dans le fichier d'une autre.
template(name="ParIP" type="string" string="/var/log/lab/%FROMHOST-IP%.log")

# Les messages reçus du réseau ont leur propre ruleset : ils ne se mélangent
# pas aux journaux locaux et ne sont jamais renvoyés ailleurs.
ruleset(name="distant") {
    action(type="omfile" dynaFile="ParIP")
}

input(type="imtcp" port="514" ruleset="distant")
EOF

# ============================== role web_target ============================
cat > roles/web_target/defaults/main.yml << 'EOF'
---
# Valeur par défaut : la plus faible précédence. host_vars/target.yml la remplace par 8080.
nginx_listen_port: 80
EOF

cat > roles/web_target/tasks/main.yml << 'EOF'
---
- name: Installer nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Déployer le site volontairement mal configuré (listage de répertoire activé)
  ansible.builtin.template:
    src: nginx-site.conf.j2
    dest: /etc/nginx/sites-available/default
    mode: "0644"
  notify: redémarrer nginx

- name: Déposer un fichier fictif visible dans le listage
  ansible.builtin.copy:
    content: "Fichier de test de la cible du lab (contenu fictif).\n"
    dest: /var/www/html/notes-internes.txt
    mode: "0644"

- name: S'assurer que nginx est actif au démarrage
  ansible.builtin.systemd:
    name: nginx
    state: started
    enabled: true
EOF

cat > roles/web_target/handlers/main.yml << 'EOF'
---
- name: redémarrer nginx
  ansible.builtin.systemd:
    name: nginx
    state: restarted
EOF

cat > roles/web_target/templates/nginx-site.conf.j2 << 'EOF'
# Géré par Ansible : cible volontairement exposée.
server {
    listen {{ nginx_listen_port }} default_server;
    server_name target.lab;
    root /var/www/html;
    index index.html;
    autoindex on;
}
EOF

# ================================ playbooks ================================
cat > 02-base.yml << 'EOF'
---
- name: Appliquer la configuration commune (utilisateur, sudo, SSH, client rsyslog)
  hosts: lab
  become: true
  roles:
    - common
EOF

cat > 03-logging.yml << 'EOF'
---
- name: Déployer le serveur de journalisation
  hosts: logs
  become: true
  roles:
    - common
    - log_server
EOF

cat > 04-target.yml << 'EOF'
---
- name: Déployer la cible web volontairement vulnérable
  hosts: web
  become: true
  roles:
    - common
    - web_target
EOF

cat > site.yml << 'EOF'
---
# 05-agent.yml sera ajouté quand le rôle agent_host existera.
- import_playbook: 01-infra.yml
- import_playbook: 02-base.yml
- import_playbook: 03-logging.yml
- import_playbook: 04-target.yml
EOF

# ===================== execution, preuve d'idempotence, tests ==============
echo "=== 1er passage de chaque playbook ==="
ansible-playbook 02-base.yml
ansible-playbook 03-logging.yml
ansible-playbook 04-target.yml

echo "=== Passage global site.yml : doit afficher changed=0 partout ==="
ansible-playbook site.yml

echo "=== Test : la cible repond sur le port 8080 depuis agent ==="
ansible agent -m uri -a "url=http://10.30.0.20:8080/ status_code=200"

echo "=== Test : journaux recus par logging (un fichier par IP) ==="
ansible web,attacker -b -m command -a "logger -t labtest bonjour-depuis-le-lab"
sleep 3
ansible logs -b -m shell -a "ls -l /var/log/lab; tail -n 3 /var/log/lab/*.log"
# fin
