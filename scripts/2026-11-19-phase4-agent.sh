#!/bin/bash
# ==============================================================================
# Phase 4 du plan (T015 a T017) : role agent_host + playbook 05-agent.yml
# Modèle LLM : Qwen 2.5 7B Instruct (Q4_K_M, 4.36 Go, bartowski/Qwen2.5-7B-Instruct-GGUF)
# Moteur : llama-server (b12549 avec toutes les dépendances dynamiques incluses)
# Agent offensif : hermes_agent.py (interroge llama-server et exploite target:8080)
# A executer DANS le LXC 300 (noeud de controle Ansible).
# ==============================================================================
set -e
cd /root/lab-ansible

# 1. Mise a jour des variables globales pour pointer vers Qwen 2.5 7B GGUF
cat > group_vars/all/vars.yml << 'EOF'
# --- Réseau du lab ---
lab_network: "10.30.0.0/24"
lab_bridge: "vmbr3"
lab_gateway: "10.30.0.1"
lab_dns: "1.1.1.1"
lab_mode: "provisioning"
control_node_ip: "192.168.1.161"
lab_lan_probe_ip: "192.168.1.1"

# --- Proxmox ---
proxmox_node: "pve"
lab_template_name: "debian13-cloudinit-tpl"
lab_template_vmid: 9000
lab_storage: "nvme-vms"
gpu_passthrough: false
gpu_pci_mapping: "p100"

# --- Accès Ansible aux VM ---
ansible_svc_user: "ansible"
lab_ssh_pubkey: "/root/.ssh/id_ed25519.pub"

# --- Modèle LLM & Moteur d'Inférence ---
llm_model_name: "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
llm_model_url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf"
llama_release_url: "https://github.com/ggml-org/llama.cpp/releases/download/b12549/llama-b12549-bin-ubuntu-x64.tar.gz"
llama_install_dir: "/opt/llama"
llama_models_dir: "/opt/models"
llama_port: 8081
llama_ctx_size: 4096
llama_threads: 4

# --- Outils offensifs & Cible ---
offensive_tools:
  - nmap
  - netcat-openbsd
  - curl
  - python3
  - python3-requests
  - python3-pip
  - jq
EOF

# 2. Creation de l'arborescence du role agent_host
mkdir -p roles/agent_host/{tasks,handlers,templates,defaults}

# 3. Defaults du role agent_host
cat > roles/agent_host/defaults/main.yml << 'EOF'
---
llama_install_dir: "{{ llama_install_dir | default('/opt/llama') }}"
llama_models_dir: "{{ llama_models_dir | default('/opt/models') }}"
llm_model_name: "{{ llm_model_name | default('Qwen2.5-7B-Instruct-Q4_K_M.gguf') }}"
llama_port: "{{ llama_port | default(8081) }}"
llama_ctx_size: "{{ llama_ctx_size | default(4096) }}"
llama_threads: "{{ llama_threads | default(4) }}"
EOF

# 4. Handlers du role agent_host
cat > roles/agent_host/handlers/main.yml << 'EOF'
---
- name: Recharger systemd
  ansible.builtin.systemd:
    daemon_reload: true

- name: Redémarrer llama-server
  ansible.builtin.systemd:
    name: llama-server
    state: restarted
EOF

# 5. Templates pour agent_host
# 5a. Service systemd pour llama-server
cat > roles/agent_host/templates/llama-server.service.j2 << 'EOF'
[Unit]
Description=Llama.cpp OpenAI Compatible Server
After=network.target

[Service]
Type=simple
User={{ ansible_svc_user }}
Group={{ ansible_svc_user }}
WorkingDirectory={{ llama_install_dir }}
ExecStart={{ llama_install_dir }}/llama-server -m {{ llama_models_dir }}/{{ llm_model_name }} -c {{ llama_ctx_size }} -t {{ llama_threads }} --host 127.0.0.1 --port {{ llama_port }}
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 5b. Script python autonome de l'agent Hermes
cat > roles/agent_host/templates/hermes_agent.py.j2 << 'EOF'
#!/usr/bin/env python3
"""
Hermes Purple Team Agent (Simulation d'attaque autonome via LLM local).
Interroge llama-server en local sur 127.0.0.1:{{ llama_port }},
analyse la cible 10.30.0.20:8080 et execute l'exploit de collecte d'information.
"""
import json
import subprocess
import sys
import time
import urllib.request
import urllib.error

LLM_API_URL = "http://127.0.0.1:{{ llama_port }}/v1/chat/completions"
TARGET_HOST = "10.30.0.20"
TARGET_PORT = 8080

def send_syslog(msg):
    try:
        subprocess.run(["logger", "-t", "hermes-agent", msg], check=False)
    except Exception:
        pass

def check_llm_ready(max_retries=15):
    health_url = "http://127.0.0.1:{{ llama_port }}/health"
    print(f"[*] Attente de la disponibilite de llama-server ({health_url})...")
    for i in range(max_retries):
        try:
            req = urllib.request.Request(health_url, headers={"User-Agent": "hermes"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    print("[+] llama-server est pret !")
                    return True
        except Exception:
            time.sleep(2)
    return False

def query_llm(prompt):
    payload = {
        "model": "qwen2.5-7b",
        "messages": [
            {"role": "system", "content": "Tu es un agent d'audit de sécurité offensif automatisé. Réponds de façon concise et technique."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.2,
        "max_tokens": 150
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(LLM_API_URL, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read().decode("utf-8"))
        return result["choices"][0]["message"]["content"]

def main():
    send_syslog("[AGENT-INIT] Demarrage de la mission d'audit Hermes")
    print("=== Agent Hermes Purple Team ===")
    
    # 1. Verification du moteur LLM
    if not check_llm_ready():
        print("[-] ERREUR: llama-server ne repond pas sur le port {{ llama_port }}")
        sys.exit(1)
        
    # 2. Reconnaissance reseau
    print(f"[*] Phase 1: Scan de reconnaissance Nmap sur {TARGET_HOST}:{TARGET_PORT}...")
    nmap_cmd = ["nmap", "-p", str(TARGET_PORT), "-sV", "--open", TARGET_HOST]
    res = subprocess.run(nmap_cmd, capture_output=True, text=True)
    scan_output = res.stdout
    print(scan_output)
    send_syslog(f"[RECON] Scan nmap termine sur {TARGET_HOST}:{TARGET_PORT}")
    
    # 3. Interrogation du LLM pour formuler le diagnostic et l'exploit
    prompt = f"""Voici le résultat d'un scan Nmap sur une cible de laboratoire :
{scan_output}

Analyse ce service web. Quel est le service détecté ? Propose une commande curl pour tester si un listage de répertoire ou une ressource est accessible."""
    print("[*] Phase 2: Consultation du LLM Qwen 2.5 7B pour analyse tactique...")
    llm_analysis = query_llm(prompt)
    print("\n--- Reponse de l'Agent LLM ---")
    print(llm_analysis)
    print("-------------------------------\n")
    
    # 4. Execution de l'exploit (collecte web de la cible)
    target_url = f"http://{TARGET_HOST}:{TARGET_PORT}/"
    print(f"[*] Phase 3: Execution de la requete d'exploitation vers {target_url}...")
    curl_res = subprocess.run(["curl", "-s", "-i", target_url], capture_output=True, text=True)
    exploit_output = curl_res.stdout
    send_syslog(f"[EXPLOIT] Requete HTTP envoyee a {target_url} - Reponse recue")
    
    # 5. Rapport d'attaque
    report = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "target": f"{TARGET_HOST}:{TARGET_PORT}",
        "scan": scan_output,
        "llm_analysis": llm_analysis,
        "exploit_status": "SUCCESS" if "HTTP/1.1 200 OK" in exploit_output else "FAILED",
        "exploit_evidence": exploit_output[:300]
    }
    with open("/opt/hermes/attack_report.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("[+] Rapport de mission enregistre dans /opt/hermes/attack_report.json")
    send_syslog("[AGENT-FINISH] Mission d'audit terminee avec succes")

if __name__ == "__main__":
    main()
EOF

# 6. Tasks du role agent_host
cat > roles/agent_host/tasks/main.yml << 'EOF'
---
- name: Installer les outils offensifs et utilitaires Python
  ansible.builtin.apt:
    name: "{{ offensive_tools }}"
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Créer les répertoires nécessaires pour llama et hermes
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"
    mode: "0755"
  loop:
    - "{{ llama_install_dir }}"
    - "{{ llama_models_dir }}"
    - /opt/hermes

- name: Télécharger et extraire la version complète de llama.cpp (binaire + libs)
  ansible.builtin.unarchive:
    src: "{{ llama_release_url }}"
    dest: "{{ llama_install_dir }}"
    remote_src: true
    extra_opts:
      - --strip-components=1
    creates: "{{ llama_install_dir }}/llama-server"
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"

- name: Télécharger le modèle intelligent Qwen 2.5 7B Instruct GGUF (4.36 Go)
  ansible.builtin.get_url:
    url: "{{ llm_model_url }}"
    dest: "{{ llama_models_dir }}/{{ llm_model_name }}"
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"
    mode: "0644"
    timeout: 600
    tmp_dest: "/var/tmp"

- name: Déployer le service systemd pour llama-server
  ansible.builtin.template:
    src: llama-server.service.j2
    dest: /etc/systemd/system/llama-server.service
    owner: root
    group: root
    mode: "0644"
  notify:
    - Recharger systemd
    - Redémarrer llama-server

- name: S'assurer que llama-server est démarré et actif au boot
  ansible.builtin.systemd:
    name: llama-server
    state: started
    enabled: true

- name: Déployer le script autonome de l'agent Hermes
  ansible.builtin.template:
    src: hermes_agent.py.j2
    dest: /opt/hermes/hermes_agent.py
    owner: "{{ ansible_svc_user }}"
    group: "{{ ansible_svc_user }}"
    mode: "0755"
EOF

# 7. Playbook 05-agent.yml
cat > 05-agent.yml << 'EOF'
---
- name: Déployer l'environnement de l'agent LLM et outils offensifs
  hosts: attacker
  become: true
  roles:
    - common
    - agent_host
EOF

# 8. Mise a jour de site.yml pour inclure 05-agent.yml
cat > site.yml << 'EOF'
---
# Déploiement global de l'infrastructure et de tous les rôles du laboratoire

- import_playbook: 01-infra.yml
- import_playbook: 02-base.yml
- import_playbook: 03-logging.yml
- import_playbook: 04-target.yml
- import_playbook: 05-agent.yml
EOF

echo "=== Rôle agent_host et playbooks générés avec succès ==="

# 9. Execution du playbook 05-agent.yml (1er passage)
echo "=== 1er passage de 05-agent.yml ==="
ansible-playbook 05-agent.yml

# 10. Execution du playbook 05-agent.yml (2e passage pour valider l'idempotence)
echo "=== 2e passage de 05-agent.yml : doit afficher changed=0 ==="
ansible-playbook 05-agent.yml

# 11. Verification de la disponibilite de llama-server sur 10.30.0.10:8081
echo "=== Test : sante de llama-server (port 8081) ==="
ansible attacker -m uri -a "url=http://127.0.0.1:8081/health method=GET"

# 12. Execution de la mission autonome de l'agent Hermes
echo "=== Lancement de l'agent offensif Hermes sur la VM attacker ==="
ansible attacker -m command -a "python3 /opt/hermes/hermes_agent.py"

# 13. Verification du rapport d'attaque genere
echo "=== Rapport d'attaque genere par Hermes ==="
ansible attacker -m command -a "cat /opt/hermes/attack_report.json"

# 14. Verification des journaux d'attaque centralises sur logging (10.30.0.30)
echo "=== Journaux de securite de l'attaque recus sur logging ==="
ansible logs -m command -a "grep hermes-agent /var/log/lab/10.30.0.10.log"

echo "=== Phase 4 terminee avec succes ! ==="
