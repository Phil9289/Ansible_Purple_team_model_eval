# Implementation Plan: Lab Ansible Proxmox — VM Jetables & Isolation d'Agent LLM

**Branch**: `001-ansible-proxmox-llm-lab` | **Date**: 2026-11-16 | **Spec**: [spec.md](file:///d:/one%20drive/OneDrive%20-%20Cegep%20de%20Sherbrooke/Documents/Ansible%20projet%20linux/specs/001-ansible-proxmox-llm-lab/spec.md)

---

## Summary

Déployer depuis le conteneur de contrôle LXC 300 (`/root/lab-ansible`) une infrastructure complète de 3 machines virtuelles Debian 13 jetables sur Proxmox VE 9.2 (`192.168.1.116`) isolées sur `vmbr3` (`10.30.0.0/24`) et filtrées par 3 tables `nftables` dédiées (`inet lab_filter`, `ip lab_nat`, `bridge lab_l2`). Produire en parallèle le document `.docx` de laboratoire étape par étape et préparer la démonstration vidéo de 10 minutes pour le cours AEC LEA.84.

---

## Technical Context & Décisions d'Alignement (Notion ↔ Proxmox Réel)

1. **Réseau et Bridge du Lab** :
   - **Choix retenu** : Bridge **`vmbr3`** (`/etc/network/interfaces.d/vmbr3-lab`), sous-réseau **`10.30.0.0/24`**, passerelle hôte **`10.30.0.1`**.
   - *Raison* : `vmbr9` est déjà utilisé sur l'hôte Proxmox par Security Onion, et `vmbr3` a été créé et activé avec succès le 16 nov. 2026.
   - **Adresses IP des 3 VM** :
     - `agent` (groupe `attacker`) : `10.30.0.10`
     - `target` (groupe `web`) : `10.30.0.20`
     - `logging` (groupe `logs`) : `10.30.0.30`
2. **Template Proxmox & Utilisateur Cloud-Init** :
   - Template existant sur l'hôte : VMID **`9000`** (`debian13-cloudinit-tpl`).
   - Utilisateur validé lors du test de la tranche verticale du 14/16 nov. : `ansible` (ou `ansible_svc` via `ciuser` dans `proxmox_kvm`).
3. **Jeton API Proxmox & Vault** :
   - Jeton actif et validé : `ansible@pve!automation` avec le rôle `AnsibleProvisioning` sur `/`.
   - *À ajouter au rôle `AnsibleProvisioning` si `gpu_passthrough: true`* : privilège `Mapping.Use` (et création du mappage PCI `p100`).
4. **Exécutable Ansible sur LXC 300** :
   - Installé dans `/root/.local/bin/ansible` (ajouter `/root/.local/bin` au `PATH` de `/root/.bashrc` et `/root/.profile` dans le LXC 300 pour que `ansible` et `ansible-playbook` soient directement accessibles).

---

## Project Structure (dans `/root/lab-ansible` sur LXC 300 + miroir local pour le `.docx`)

```text
/root/lab-ansible/
├── ansible.cfg
├── requirements.yml
├── .gitignore
├── site.yml
├── 01-infra.yml
├── 02-base.yml
├── 03-logging.yml
├── 04-target.yml
├── 05-agent.yml
├── 90-destroy.yml
├── 99-verify.yml
├── exports/
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   └── all/
│   │       ├── vars.yml
│   │       └── vault.yml
│   └── host_vars/
│       ├── pve.yml
│       ├── agent.yml
│       ├── target.yml
│       └── logging.yml
└── roles/
    ├── proxmox_network/
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── vmbr3-lab.j2
    │       ├── nftables.conf.j2
    │       └── lab-nftables.service.j2
    ├── proxmox_vms/
    │   └── tasks/main.yml
    ├── common/
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── sshd_config.j2
    │       └── rsyslog-client.conf.j2
    ├── log_server/
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       └── rsyslog-server.conf.j2
    ├── web_target/
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       └── nginx-site.conf.j2
    └── agent_host/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── tools.yml
        │   ├── nvidia.yml
        │   ├── llama.yml
        │   ├── model.yml
        │   └── hermes.yml
        └── templates/
            ├── llama-server.service.j2
            ├── hermes-config.yaml.j2
            └── hermes-agent.service.j2
```
