#!/bin/bash
# ==============================================================================
# 2026-11-22 : accès SSH multi-postes + Hermes configurable par Ansible.
# À exécuter DANS le LXC 300 (nœud de contrôle), en root :
#     bash 2026-11-22-acces-ssh-et-hermes.sh
#
# Ce script MODIFIE SEULEMENT des fichiers dans /root/lab-ansible.
# Il ne déploie rien et ne touche ni au Proxmox ni aux VM.
#
# Ce qu'il fait :
#   1. Nouveau playbook 06-acces-ssh.yml (+ templates/ssh_config_lab.j2)
#      - contrôleur : alias "ssh agent/target/logging" dans /root/.ssh/config
#                     + ANSIBLE_CONFIG dans /root/.bashrc (ansible marche de partout)
#      - hôte Proxmox : clé dédiée /root/.ssh/id_lab_ed25519 + mêmes alias
#      - VM du lab : autorise la clé du Proxmox et les clés de lab_admin_ssh_pubkeys
#   2. site.yml importe 06-acces-ssh.yml (l'accès revient seul après un rebuild)
#   3. Hermes : fichier de config hermes.env, service systemd hermes-agent,
#      script hermes_agent.py qui lit sa config au lieu de valeurs en dur
#   4. Nouvelles variables : lab_admin_ssh_pubkeys (group_vars/all)
#      et hermes_* (host_vars/agent.yml)
#
# Sauvegarde AVANT modification : /root/lab-ansible-avant-acces-ssh-hermes.tgz
# Retour arrière : rm -rf /root/lab-ansible && tar xzf <sauvegarde> -C /root
# ==============================================================================
set -euo pipefail
cd /root/lab-ansible

BACKUP=/root/lab-ansible-avant-acces-ssh-hermes.tgz
TASKS=roles/agent_host/tasks/main.yml

# --- 0. Garde-fous -----------------------------------------------------------
[ -f inventory/hosts.yml ] || { echo "ERREUR : lancer depuis /root/lab-ansible"; exit 1; }
[ -e "$BACKUP" ] && { echo "ERREUR : $BACKUP existe déjà. Script déjà exécuté ?"; exit 1; }
grep -q "^- name: Déployer le script autonome de l'agent Hermes" "$TASKS" \
    || { echo "ERREUR : tâche Hermes introuvable dans $TASKS, rien n'est modifié."; exit 1; }
grep -q "^- name: Recharger systemd" roles/agent_host/handlers/main.yml \
    || { echo "ERREUR : handler 'Recharger systemd' introuvable, rien n'est modifié."; exit 1; }
python3 - "$TASKS" << 'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
apres = s.split("- name: Déployer le script autonome de l'agent Hermes", 1)[1]
if "\n- name:" in apres:
    raise SystemExit("ERREUR : des tâches suivent la tâche Hermes dans tasks/main.yml, arrêt (rien n'est modifié).")
PY

echo "=== Sauvegarde vers $BACKUP ==="
tar czf "$BACKUP" --exclude=lab-ansible/models-cache -C /root lab-ansible
ls -lh "$BACKUP"
mkdir -p templates

# --- 1. Playbook d'accès SSH ---------------------------------------------------
cat > templates/ssh_config_lab.j2 << 'EOF'
# Alias SSH vers les VM du lab, générés depuis inventory/hosts.yml.
# Les VM sont jetables (90-destroy) : leur clé d'hôte change à chaque rebuild,
# on ne l'enregistre donc pas (sinon "REMOTE HOST IDENTIFICATION HAS CHANGED").
{% for h in groups['lab'] %}
Host {{ h }}
    HostName {{ hostvars[h]['ansible_host'] }}
    User {{ ansible_svc_user }}
    IdentityFile {{ ssh_lab_identity }}
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

{% endfor %}
EOF

cat > 06-acces-ssh.yml << 'EOF'
---
# Accès SSH d'administration aux VM du lab depuis trois postes :
#   - le nœud de contrôle (LXC 300) : root -> ansible@VM, clé /root/.ssh/id_ed25519
#   - l'hôte Proxmox : root -> ansible@VM, clé dédiée /root/.ssh/id_lab_ed25519
#   - le PC de l'admin : ProxyJump par le LXC 300 (seule source autorisée par nftables)
# Tout est regénéré à chaque site.yml : rien à refaire à la main après un rebuild.

- name: Hôte Proxmox — clé SSH dédiée au lab et alias
  hosts: proxmox_host
  gather_facts: false
  vars:
    ssh_lab_identity: /root/.ssh/id_lab_ed25519
  tasks:
    - name: Créer le dossier /root/.ssh
      ansible.builtin.file:
        path: /root/.ssh
        state: directory
        mode: "0700"

    - name: Générer la clé dédiée au lab (une seule fois)
      ansible.builtin.command:
        cmd: ssh-keygen -t ed25519 -N "" -C "root@{{ inventory_hostname }}-lab" -f {{ ssh_lab_identity }}
        creates: "{{ ssh_lab_identity }}"

    - name: Lire la clé publique du Proxmox
      ansible.builtin.slurp:
        src: "{{ ssh_lab_identity }}.pub"
      register: pve_lab_pubkey

    - name: Écrire les alias des VM dans /root/.ssh/config
      ansible.builtin.blockinfile:
        path: /root/.ssh/config
        create: true
        mode: "0600"
        insertbefore: BOF
        marker: "# {mark} ANSIBLE — alias du lab Purple Team"
        block: "{{ lookup('ansible.builtin.template', 'ssh_config_lab.j2') }}"

- name: VM du lab — autoriser les clés d'administration
  hosts: lab
  become: true
  gather_facts: false
  vars:
    admin_keys: >-
      {{ [hostvars[groups['proxmox_host'][0]]['pve_lab_pubkey']['content'] | b64decode | trim]
         + (lab_admin_ssh_pubkeys | default([])) }}
  tasks:
    - name: Ajouter la clé du Proxmox et celles de lab_admin_ssh_pubkeys
      ansible.posix.authorized_key:
        user: "{{ ansible_svc_user }}"
        key: "{{ item }}"
        state: present
      loop: "{{ admin_keys }}"
      loop_control:
        label: "{{ item.split(' ')[-1] }}"

- name: Nœud de contrôle — alias SSH et configuration Ansible
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ssh_lab_identity: "{{ lab_ssh_pubkey | regex_replace('\\.pub$', '') }}"
  tasks:
    - name: Écrire les alias des VM dans /root/.ssh/config
      ansible.builtin.blockinfile:
        path: /root/.ssh/config
        create: true
        mode: "0600"
        insertbefore: BOF
        marker: "# {mark} ANSIBLE — alias du lab Purple Team"
        block: "{{ lookup('ansible.builtin.template', 'ssh_config_lab.j2') }}"

    - name: Rendre l'inventaire visible depuis n'importe quel dossier
      ansible.builtin.blockinfile:
        path: /root/.bashrc
        marker: "# {mark} ANSIBLE — configuration du lab"
        block: |
          export ANSIBLE_CONFIG={{ playbook_dir }}/ansible.cfg
          alias lab='cd {{ playbook_dir }}'
EOF

grep -q "06-acces-ssh.yml" site.yml || echo "- import_playbook: 06-acces-ssh.yml" >> site.yml

# --- 2. Variables ----------------------------------------------------------------
if ! grep -q "^lab_admin_ssh_pubkeys:" inventory/group_vars/all/vars.yml; then
cat >> inventory/group_vars/all/vars.yml << 'EOF'

# --- Clés SSH d'administration supplémentaires (une ligne .pub par poste) ---
# Elles sont ajoutées à l'utilisateur de service de chaque VM par 06-acces-ssh.yml.
# Exemple (PC Windows, contenu de C:\Users\phil\.ssh\phil_lxc300.pub) :
#   - "ssh-ed25519 AAAA... phil@PC"
lab_admin_ssh_pubkeys: []
EOF
fi

if ! grep -q "^hermes_dir:" inventory/host_vars/agent.yml; then
cat >> inventory/host_vars/agent.yml << 'EOF'

# --- Agent Hermes (lues par roles/agent_host -> /opt/hermes/hermes.env) ---
hermes_dir: "/opt/hermes"
# Moteur LLM : par défaut le llama-server local de la VM (aucune clé, marche en mode isolated).
hermes_llm_api_url: "http://127.0.0.1:{{ llama_port }}/v1"
hermes_llm_model: "{{ llm_model_name }}"
# Vide pour llama-server local. Pour une API externe : "{{ vault_hermes_llm_api_key }}"
hermes_llm_api_key: ""
hermes_temperature: 0.2
hermes_max_tokens: 300
hermes_llm_timeout: 600
# Cible lue dans l'inventaire (rien en dur)
hermes_target_host: "{{ hostvars[groups['web'][0]]['ansible_host'] }}"
hermes_target_port: "{{ hostvars[groups['web'][0]]['nginx_listen_port'] }}"
# true = lancer une mission à chaque 05-agent.yml (casse l'idempotence, garder false)
hermes_run_on_deploy: false
EOF
fi

# Valeurs par défaut du rôle (plus faible précédence)
if ! grep -q "^hermes_dir:" roles/agent_host/defaults/main.yml; then
cat >> roles/agent_host/defaults/main.yml << 'EOF'

# --- Agent Hermes : valeurs par défaut, remplacées par host_vars/agent.yml ---
hermes_dir: "/opt/hermes"
hermes_llm_api_url: "http://127.0.0.1:8081/v1"
hermes_llm_model: "local-model"
hermes_llm_api_key: ""
hermes_temperature: 0.2
hermes_max_tokens: 300
hermes_llm_timeout: 600
hermes_target_host: "10.30.0.20"
hermes_target_port: 8080
hermes_run_on_deploy: false
EOF
fi

# --- 3. Templates Hermes -------------------------------------------------------
cat > roles/agent_host/templates/hermes.env.j2 << 'EOF'
# {{ ansible_managed }}
# Configuration de l'agent Hermes. Modifier inventory/host_vars/agent.yml,
# puis relancer 05-agent.yml : ne pas éditer ce fichier sur la VM.
HERMES_LLM_API_URL={{ hermes_llm_api_url }}
HERMES_LLM_MODEL={{ hermes_llm_model }}
HERMES_LLM_API_KEY={{ hermes_llm_api_key }}
HERMES_TEMPERATURE={{ hermes_temperature }}
HERMES_MAX_TOKENS={{ hermes_max_tokens }}
HERMES_LLM_TIMEOUT={{ hermes_llm_timeout }}
HERMES_TARGET_HOST={{ hermes_target_host }}
HERMES_TARGET_PORT={{ hermes_target_port }}
HERMES_REPORT={{ hermes_dir }}/attack_report.json
EOF

cat > roles/agent_host/templates/hermes-agent.service.j2 << 'EOF'
# {{ ansible_managed }}
# Mission unique : "systemctl start hermes-agent" lance une attaque puis s'arrête.
[Unit]
Description=Agent Hermes Purple Team (mission unique)
After=network-online.target llama-server.service
Wants=llama-server.service

[Service]
Type=oneshot
User={{ ansible_svc_user }}
Group={{ ansible_svc_user }}
WorkingDirectory={{ hermes_dir }}
EnvironmentFile={{ hermes_dir }}/hermes.env
ExecStart=/usr/bin/python3 -u {{ hermes_dir }}/hermes_agent.py
TimeoutStartSec=1200
StandardOutput=journal
StandardError=journal
EOF

cat > roles/agent_host/templates/hermes_agent.py.j2 << 'EOF'
#!/usr/bin/env python3
# {{ ansible_managed }}
"""
Hermes Purple Team Agent (simulation d'attaque autonome via LLM).
Toute la configuration vient de {{ hermes_dir }}/hermes.env, généré par Ansible.
Lancement : sudo systemctl start hermes-agent   (journal : journalctl -u hermes-agent)
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

API_URL = os.environ.get("HERMES_LLM_API_URL", "http://127.0.0.1:{{ llama_port }}/v1").rstrip("/")
MODEL = os.environ.get("HERMES_LLM_MODEL", "local-model")
API_KEY = os.environ.get("HERMES_LLM_API_KEY", "")
TEMPERATURE = float(os.environ.get("HERMES_TEMPERATURE", "0.2"))
MAX_TOKENS = int(os.environ.get("HERMES_MAX_TOKENS", "300"))
LLM_TIMEOUT = int(os.environ.get("HERMES_LLM_TIMEOUT", "600"))
TARGET_HOST = os.environ.get("HERMES_TARGET_HOST", "{{ hermes_target_host }}")
TARGET_PORT = int(os.environ.get("HERMES_TARGET_PORT", "{{ hermes_target_port }}"))
REPORT = os.environ.get("HERMES_REPORT", "{{ hermes_dir }}/attack_report.json")


def headers():
    h = {"Content-Type": "application/json", "User-Agent": "hermes"}
    if API_KEY:
        h["Authorization"] = f"Bearer {API_KEY}"
    return h


def send_syslog(msg):
    subprocess.run(["logger", "-t", "hermes-agent", msg], check=False)


def check_llm_ready(max_wait=300):
    """Attend que l'API réponde (le 7B peut prendre du temps à charger sur CPU)."""
    url = f"{API_URL}/models"
    print(f"[*] Attente du moteur LLM ({url}), {max_wait} s max...")
    fin = time.time() + max_wait
    while time.time() < fin:
        try:
            req = urllib.request.Request(url, headers=headers())
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    print("[+] Moteur LLM prêt.")
                    return True
        except Exception:
            pass
        time.sleep(3)
    return False


def query_llm(prompt):
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "Tu es un agent d'audit de sécurité offensif automatisé dans un laboratoire isolé. Réponds de façon concise et technique."},
            {"role": "user", "content": prompt},
        ],
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
    }
    req = urllib.request.Request(f"{API_URL}/chat/completions",
                                 data=json.dumps(payload).encode("utf-8"), headers=headers())
    with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))["choices"][0]["message"]["content"]


def main():
    send_syslog("[AGENT-INIT] Démarrage de la mission d'audit Hermes")
    print(f"=== Agent Hermes Purple Team — modèle {MODEL}, cible {TARGET_HOST}:{TARGET_PORT} ===")

    if not check_llm_ready():
        print(f"[-] ERREUR : le moteur LLM ne répond pas sur {API_URL}")
        print("    Vérifier : systemctl status llama-server ; journalctl -u llama-server -n 50")
        send_syslog("[AGENT-ERROR] Moteur LLM indisponible")
        sys.exit(1)

    print(f"[*] Phase 1 : scan nmap de {TARGET_HOST}:{TARGET_PORT}...")
    scan = subprocess.run(["nmap", "-p", str(TARGET_PORT), "-sV", "--open", TARGET_HOST],
                          capture_output=True, text=True).stdout
    print(scan)
    send_syslog(f"[RECON] Scan nmap terminé sur {TARGET_HOST}:{TARGET_PORT}")

    prompt = (f"Voici le résultat d'un scan Nmap sur une cible de laboratoire :\n{scan}\n\n"
              "Analyse ce service web. Quel est le service détecté ? Propose une commande curl "
              "pour tester si un listage de répertoire ou une ressource est accessible.")
    print("[*] Phase 2 : analyse tactique par le LLM (peut prendre 1 à 3 min sur CPU)...")
    t0 = time.time()
    analysis = query_llm(prompt)
    print(f"\n--- Réponse du LLM ({time.time() - t0:.0f} s) ---\n{analysis}\n-------------------------------\n")

    url = f"http://{TARGET_HOST}:{TARGET_PORT}/"
    print(f"[*] Phase 3 : requête d'exploitation vers {url}...")
    evidence = subprocess.run(["curl", "-s", "-i", "-m", "10", url], capture_output=True, text=True).stdout
    ok = re.match(r"HTTP/\S+ 200", evidence) is not None
    send_syslog(f"[EXPLOIT] Requête HTTP envoyée à {url} - {'succès' if ok else 'échec'}")

    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": MODEL,
        "target": f"{TARGET_HOST}:{TARGET_PORT}",
        "scan": scan,
        "llm_analysis": analysis,
        "exploit_status": "SUCCESS" if ok else "FAILED",
        "exploit_evidence": evidence[:300],
    }
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"[+] Rapport enregistré dans {REPORT}")
    send_syslog("[AGENT-FINISH] Mission d'audit terminée")


if __name__ == "__main__":
    main()
EOF

# --- 4. Tâches Hermes (remplace la dernière tâche du rôle) -------------------------
python3 - "$TASKS" << 'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
debut = s.index("- name: Déployer le script autonome de l'agent Hermes")
s = s[:debut] + '''- name: Déployer le script de l'agent Hermes
  ansible.builtin.template:
    src: hermes_agent.py.j2
    dest: "{{ hermes_dir }}/hermes_agent.py"
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"
    mode: "0755"

- name: Déployer la configuration de Hermes (peut contenir une clé API, d'où 0600)
  ansible.builtin.template:
    src: hermes.env.j2
    dest: "{{ hermes_dir }}/hermes.env"
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"
    mode: "0600"

- name: Déployer le service systemd hermes-agent (mission unique, lancée à la demande)
  ansible.builtin.template:
    src: hermes-agent.service.j2
    dest: /etc/systemd/system/hermes-agent.service
    owner: root
    group: root
    mode: "0644"
  notify: Recharger systemd

- name: Appliquer tout de suite le rechargement de systemd
  ansible.builtin.meta: flush_handlers

- name: Lancer une mission Hermes (seulement si hermes_run_on_deploy est vrai)
  ansible.builtin.systemd:
    name: hermes-agent
    state: started
  when: hermes_run_on_deploy | bool
'''
open(p, 'w', encoding='utf-8').write(s)
print("tasks/main.yml mis à jour")
PY

# --- Vérifications (rien n'est déployé) ---------------------------------------
echo
echo "=== Variables Hermes vues par l'agent ==="
ansible-inventory --host agent --yaml | grep -E "^hermes_|lab_admin_ssh_pubkeys" || true
echo
echo "=== Syntaxe ==="
for pb in site.yml 06-acces-ssh.yml 05-agent.yml; do ansible-playbook --syntax-check "$pb"; done
echo
echo "=== Fichiers prêts. À lancer toi-même : ==="
echo "  ansible-playbook 06-acces-ssh.yml   # touche /root/.ssh du Proxmox (clé + config), rien d'autre"
echo "  ansible-playbook 05-agent.yml       # déploie hermes.env + service hermes-agent"
echo "  source ~/.bashrc && ssh agent"
