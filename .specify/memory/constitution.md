# Lab Ansible Proxmox (Purple Team & Isolation LLM) — Constitution

## Core Principles

### I. Double finalité : Exigences académiques (AEC LEA.84) & Lab Purple Team réel
Chaque composant du projet doit simultanément :
1. **Valider 100 % de la grille d'évaluation du cours** : présentation claire des concepts Ansible (20 %), vidéo de preuve de concept (25 %), installation du nœud de contrôle (5 %), au moins 3 playbooks distincts par type de serveur avec inventaire structuré (10 %), variables `group_vars` / `host_vars` / `vault` (5 %), variété de modules (5 %), handlers (5 %), templates Jinja2 (5 %), rôles (5 %), journal des difficultés et solutions (10 %), qualité du français dans le `.docx` final (5 %).
2. **Servir de véritable banc d'essai Purple Team à domicile** : permettre de déployer des VM jetables sur Proxmox 9, d'exécuter un agent LLM autonome (Hermes + llama.cpp sur GPU Tesla P100) contre une cible vulnérable (`target`), tout en capturant des journaux infalsifiables sur un serveur `rsyslog` centralisé (`logging`), puis de tout détruire proprement (`90-destroy`).

### II. Non-perturbation absolue de l'hôte Proxmox (`192.168.1.116`) (NON-NÉGOCIABLE)
- **Interdiction formelle de `flush ruleset`** dans `nftables` : l'hôte héberge Ludus (`10.<range>.x`), Proxmox VE et Security Onion (`vmbr9`). Seules les tables dédiées au lab (`inet lab_filter`, `ip lab_nat`) peuvent être détruites/recréées via `destroy table` après validation syntaxique (`validate: nft -c -f %s`).
- **Isolation du bridge réseau** : le lab utilise exclusivement `vmbr3` (`10.30.0.0/24`, passerelle `10.30.0.1`) défini dans `/etc/network/interfaces.d/vmbr3-lab` et activé via `ifup vmbr3` (ne jamais modifier `vmbr0`, `vmbr9` ou les bridges Ludus).
- **Contrôle d'accès SSH Antigravity** : toute connexion de l'assistant passe par `antigravity@192.168.1.116` (clé `antigravity_pve`), journalisée dans `/var/log/sudo_antigravity.log`, et toute commande `sudo` requiert la confirmation explicite de l'utilisateur dans le chat.

### III. Idempotence stricte et Validation automatisée
- Tout playbook de configuration (`01-infra`, `03-logging`, `04-target`, `05-agent`) doit être **idempotent** : un second passage consécutif doit afficher `changed=0` et `failed=0` (preuve exigée dans le document `.docx` et la vidéo).
- Toute tâche `apt` utilise `cache_valid_time`, toute tâche `command`/`shell` de build utilise `creates:`, et les templates ne contiennent aucun horodatage dynamique.
- Le playbook `99-verify.yml` valide la posture de sécurité à l'aide du module `assert` en combinant systématiquement un **test positif** (flux autorisé fonctionnel) et un **test négatif** (flux interdit rejeté avec `reject` pour éviter les délais d'expiration).

### IV. Sécurité des secrets et Intégrité des journaux
- Aucun mot de passe ou secret de jeton API Proxmox ne doit apparaître en clair dans le dépôt, le terminal ou la vidéo : utilisation obligatoire d'**Ansible Vault** (`group_vars/all/vault.yml`) et de `no_log: true` sur les tâches manipulant des secrets.
- Le serveur `logging` (`10.30.0.30`) reçoit les journaux sur TCP/514 uniquement, les sépare par adresse IP source réelle (`/var/log/lab/`), et n'exécute pas le client `rsyslog` vers lui-même (prévention des boucles).

### V. Documentation en continu et Traçabilité des difficultés
- Chaque problème technique rencontré (Proxmox 9, cloud-init, SSH, nftables, GPU passthrough, Ansible) est consigné au fil de l'eau dans le **Journal de difficultés** avec sa cause et sa solution reproductible, afin d'alimenter directement la section dédiée du rapport `.docx` (10 % de la note).

## Contraintes techniques et Architecture de référence

- **Hôte de virtualisation** : Proxmox VE 9.2 (`pve`, `192.168.1.116`), Bi-Xeon E5-2620, 128 Go RAM, GPU Tesla P100 (16 Go, dédiée au lab via passthrough PCI) + RTX 3060 Ti (réservée au LXC `llm` existant, hors périmètre).
- **Nœud de contrôle Ansible** : Conteneur LXC `300` (`ansible`, hors du bridge du lab), répertoire `/root/lab-ansible`, utilisant `community.proxmox`, `community.general` et `ansible.posix`.
- **Inventaire des 3 serveurs Linux du lab** (sur `vmbr3` — `10.30.0.0/24`, clonés depuis le template `9000` `debian13-cloudinit-tpl`) :
  1. **`logging`** (groupe `logs`, VMID `303`, `10.30.0.30`) : serveur `rsyslog` centralisé.
  2. **`target`** (groupe `web`, VMID `302`, `10.30.0.20`) : serveur web `nginx` cible + client `rsyslog`.
  3. **`agent`** (groupe `attacker`, VMID `301`, `10.30.0.10`) : serveur d'inférence `llama.cpp` + GPU NVIDIA P100 + agent `Hermes` + client `rsyslog`.
- **Modes réseau du lab** : variable `lab_mode` (`provisioning` avec NAT pour `apt`/téléchargements, puis `isolated` coupant Internet et le LAN lors des tests).

## Livrables et Jalons (Échéance : 24 novembre 2026 à 23 h 59)

1. **Infrastructure & Playbooks fonctionnels sur LXC 300** : `01-infra.yml`, `03-logging.yml`, `04-target.yml`, `05-agent.yml`, `90-destroy.yml`, `99-verify.yml`.
2. **Document `.docx` complet (format tutoriel étape par étape pour LEA)** :
   - Introduction (contexte académique + cas d'usage Purple Team d'isolation LLM sur Proxmox en remplacement de GNS3).
   - Lien YouTube (non répertorié / privé) de la vidéo de démonstration.
   - Présentation des concepts Ansible (20 %).
   - Architecture Proxmox / réseau `vmbr3` (schéma + description des VM et flux).
   - Inventaire (`hosts.yml`, `group_vars`, `host_vars`), configuration SSH et Vault.
   - Playbooks, rôles, handlers et templates Jinja2 détaillés et commentés.
   - Validation, tests d'idempotence et captures d'écran (`99-verify`).
   - Difficultés rencontrées et solutions apportées (10 %).
   - Références et ressources utilisées.
3. **Vidéo de démonstration (25 %)** : preuve de concept filmée montrant le déploiement automatique, l'idempotence, l'isolation et le fonctionnement des 3 serveurs.

## Governance

Cette constitution sert de référence à toutes les étapes Specify (`/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-implement`). Toute modification d'architecture (ex. changement de sous-réseau ou repli CPU si le passthrough GPU bloque) doit être répercutée simultanément dans la spécification locale, les fichiers Ansible du LXC 300 et la documentation Notion.

**Version**: 1.0.0 | **Ratified**: 2026-11-16 | **Last Amended**: 2026-11-16
