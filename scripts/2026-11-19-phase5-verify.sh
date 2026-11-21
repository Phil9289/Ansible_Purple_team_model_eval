#!/bin/bash
# ==============================================================================
# Phase 5 du plan (T018 et T019) : Bascule en mode isolated & Preuve de Sécurité
# 1. Met a jour group_vars/all/vars.yml avec lab_mode: "isolated"
# 2. Reapplique les regles de pare-feu nftables sur l'hote (01-infra.yml --tags firewall)
# 3. Genere et execute 99-verify.yml (tests positifs + tests negatifs + assert)
# 4. Affiche les traces de rejets reellement enregistrees par le noyau Linux de l'hote
# ==============================================================================
set -e
cd /root/lab-ansible

# 1. Bascule de lab_mode a "isolated"
sed -i 's/lab_mode: "provisioning"/lab_mode: "isolated"/' group_vars/all/vars.yml
grep "lab_mode:" group_vars/all/vars.yml

# 2. Reapplication des regles de pare-feu nftables
echo "=== Reapplication des regles de pare-feu en mode isole ==="
ansible-playbook 01-infra.yml --tags firewall

# 3. Generation de 99-verify.yml
cat > 99-verify.yml << 'EOF'
---
- name: Validation et Preuve de Sécurité de l'Isolation du Lab Purple Team
  hosts: attacker
  gather_facts: false
  tasks:
    # --- Tests Positifs (Flux autorisés indispensables au fonctionnement) ---
    - name: "[POSITIF] 1. Vérifier l'accès HTTP à la cible vulnérable (10.30.0.20:8080)"
      ansible.builtin.uri:
        url: "http://10.30.0.20:8080/"
        method: GET
        status_code: 200
        timeout: 5
      register: test_web

    - name: "[POSITIF] 2. Vérifier la connectivité Syslog TCP/514 vers le serveur de logs (10.30.0.30)"
      ansible.builtin.command:
        cmd: "nc -z -w 3 10.30.0.30 514"
      register: test_logs

    - name: "[POSITIF] 3. Vérifier la santé du moteur d'inférence LLM local (127.0.0.1:8081)"
      ansible.builtin.uri:
        url: "http://127.0.0.1:8081/health"
        method: GET
        status_code: 200
        timeout: 5
      register: test_llm

    # --- Tests Négatifs (Flux interdits qui DOIVENT échouer en mode isolé) ---
    - name: "[NÉGATIF] 4. Tester l'accès à Internet (1.1.1.1) — DOIT ÊTRE REJETÉ"
      ansible.builtin.command:
        cmd: "curl -s -m 3 http://1.1.1.1"
      register: test_internet
      ignore_errors: true

    - name: "[NÉGATIF] 5. Tester l'accès au réseau local domestique (192.168.1.1) — DOIT ÊTRE REJETÉ"
      ansible.builtin.command:
        cmd: "curl -s -m 3 http://192.168.1.1"
      register: test_lan
      ignore_errors: true

    - name: "[NÉGATIF] 6. Tester l'accès à l'interface d'administration Proxmox (:8006) — DOIT ÊTRE REJETÉ"
      ansible.builtin.command:
        cmd: "curl -k -s -m 3 https://192.168.1.116:8006"
      register: test_pve
      ignore_errors: true

    - name: "[NÉGATIF] 7. Tester une connexion SSH clandestine vers le serveur de logs (10.30.0.30:22) — DOIT ÊTRE BLOQUÉE"
      ansible.builtin.command:
        cmd: "nc -z -w 3 10.30.0.30 22"
      register: test_ssh_logs
      ignore_errors: true

    # --- Assertion Finale et Preuve Académique ---
    - name: "Vérifier la conformité stricte de l'isolation du laboratoire"
      ansible.builtin.assert:
        that:
          - test_web.status == 200
          - test_logs.rc == 0
          - test_llm.status == 200
          - test_internet.rc != 0
          - test_lan.rc != 0
          - test_pve.rc != 0
          - test_ssh_logs.rc != 0
        success_msg: "SUCCÈS TOTAL : Tous les flux autorisés sont opérationnels et tous les flux interdits sont strictement bloqués par nftables !"
        fail_msg: "ALERTE SÉCURITÉ : Un flux interdit n'a pas été rejeté comme prévu."
EOF

# 4. Execution du playbook 99-verify.yml
echo "=== Execution de la suite de tests de securite 99-verify.yml ==="
ansible-playbook 99-verify.yml

# 5. Affichage des preuves de rejets dans les journaux du noyau de l'hote
echo "=== Traces reelles de rejets nftables capturees par le noyau ==="
ansible proxmox_host -b -m command -a "journalctl -k --grep=LAB-REJECT -n 15 --no-pager"

echo "=== Phase 5 terminee avec succes ! Preuve d'isolation absolue validee. ==="
