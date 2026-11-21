# Feature Specification: Lab Ansible Proxmox — VM Jetables & Isolation d'Agent LLM (Purple Team)

**Feature Branch**: `001-ansible-proxmox-llm-lab`  
**Created**: 2026-11-16  
**Status**: Approved  
**Input**: Documentation Notion du projet (« Lab Ansible — Projet complet ») + Énoncé officiel du cours *Auto-initiation à Ansible* (AEC LEA.84, Cégep de Sherbrooke) + État réel du serveur Proxmox VE 9.2 (`192.168.1.116`).

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Isolation Réseau & Provisionnement de 3 VM Jetables (`01-infra` & `90-destroy`) (Priority: P1)

En tant qu'administrateur Purple Team et étudiant AEC LEA.84, je veux qu'Ansible configure de manière idempotente le bridge isolé `vmbr3` (`10.30.0.0/24`) et les tables `nftables` dédiées (`inet lab_filter`, `ip lab_nat`, `bridge lab_l2`) sur l'hôte Proxmox (`192.168.1.116`) sans perturber Proxmox, Ludus ni `vmbr9`, puis clone, redimensionne, configure (cloud-init + GPU P100 optionnel) et démarre les 3 VM Debian 13 (`agent`, `target`, `logging`) depuis le template `9000` (`debian13-cloudinit-tpl`), et permette de les détruire à la demande (`90-destroy.yml`).

**Why this priority**: Aucune configuration des 3 serveurs Linux ne peut avoir lieu sans le réseau isolé, le NAT de provisionnement et la création automatisée des VM via l'API Proxmox.

**Independent Test**: Exécuter `ansible-playbook 01-infra.yml` deux fois de suite (le 2e passage ne recrée rien), vérifier que les 3 VM répondent à `ansible lab -m ping`, puis détruire une VM (`ansible-playbook 90-destroy.yml -e '{"vms_to_destroy": ["target"]}'`) et la recréer automatiquement.

**Acceptance Scenarios**:

1. **Given** l'hôte Proxmox avec `vmbr3` (`10.30.0.1/24`) et `lab_mode: provisioning`, **When** j'exécute `ansible-playbook 01-infra.yml`, **Then** les tables `nftables` du lab sont chargées après validation (`nft -c -f`), les 3 VM (`301`/`agent`, `302`/`target`, `303`/`logging` — ou `9010`/`9020`/`9030` selon `host_vars`) sont clonées, leurs disques agrandis, et elles répondent en SSH avec l'utilisateur de service.
2. **Given** les 3 VM démarrées en mode `provisioning`, **When** une VM exécute `apt-get update`, **Then** l'accès Internet fonctionne via le NAT (`ip lab_nat`), mais tout accès vers le LAN privé (`192.168.1.0/24` ou autres plages RFC1918 hors lab) est rejeté et journalisé (`LAB-REJECT-RFC1918`).

---

### User Story 2 - Configuration des 3 Serveurs : Journalisation (`03-logging`) et Cible Web (`04-target`) (Priority: P1)

En tant qu'étudiant évalué sur le déploiement d'au moins 3 types de serveurs Linux avec rôles, handlers, templates Jinja2 et précédence de variables, je veux déployer :
1. Un socle commun (`02-base.yml` / rôle `common`) durcissant SSH (`sshd_config.j2`), configurant `sudo` sans mot de passe et installant le client `rsyslog` (sauf sur `logging`).
2. Le serveur de journalisation centralisée `logging` (`03-logging.yml`, rôle `log_server`) qui reçoit les logs en TCP/514 et les sépare par IP source réelle (`/var/log/lab/%FROMHOST-IP%.log`).
3. Le serveur web cible `target` (`04-target.yml`, rôle `web_target`) faisant tourner `nginx` sur le port `8080` (démonstration de précédence `host_vars/target.yml` > `defaults/main.yml` qui vaut `80`) avec `autoindex on`.

**Why this priority**: Ces deux serveurs rapides à déployer valident immédiatement la majorité des critères de la grille d'évaluation Ansible (rôles, handlers, templates Jinja2, variables, idempotence `changed=0` au 2e run) et préparent la réception des journaux avant le déploiement de l'agent.

**Independent Test**: Exécuter `03-logging.yml` et `04-target.yml` deux fois de suite (`changed=0` au 2e passage), vérifier `curl http://10.30.0.20:8080` depuis `agent`, et vérifier que `/var/log/lab/10.30.0.10.log` et `/var/log/lab/10.30.0.20.log` se remplissent sur `logging`.

**Acceptance Scenarios**:

1. **Given** les 3 VM accessibles en SSH, **When** j'exécute `03-logging.yml` puis `04-target.yml` une seconde fois, **Then** Ansible affiche `changed=0` et `failed=0`.
2. **Given** une modification de variable `nginx_listen_port` testée avec `--check --diff` puis appliquée, **When** le template change, **Then** le handler `redémarrer nginx` est déclenché une seule fois.

---

### User Story 3 - Déploiement du Serveur d'Exécution de l'Agent LLM (`05-agent`) (Priority: P2)

En tant qu'opérateur du lab Purple Team, je veux qu'Ansible déploie sur la VM `agent` (`10.30.0.10`) les outils offensifs (`nmap`, `netcat-openbsd`, `curl`), le pilote NVIDIA + CUDA pour la Tesla P100 (si `gpu_passthrough: true`, avec repli CPU automatique si `false`), compile `llama.cpp`, télécharge le modèle GGUF vérifié par SHA256 et configure le service local `llama-server` (`127.0.0.1:8081`) ainsi que l'agent autonome Hermes.

**Why this priority**: C'est le3e type de serveur exigé par l'énoncé et le cœur métier du lab d'isolation de modèles LLM. Il comporte un mécanisme de repli (`gpu_passthrough: false`) pour garantir le succès de la démonstration vidéo même en cas de caprice matériel PCI/IOMMU.

**Independent Test**: Exécuter `05-agent.yml`, vérifier `http://127.0.0.1:8081/health` (et `nvidia-smi` si `gpu_passthrough: true`), puis relancer `05-agent.yml` pour constater `changed=0` grâce à `creates:`.

**Acceptance Scenarios**:

1. **Given** `agent` en mode `provisioning`, **When** `05-agent.yml` s'exécute, **Then** `llama-server` répond `200 OK` sur `http://127.0.0.1:8081/health` et les outils offensifs sont installés.

---

### User Story 4 - Bascule en Mode `isolated` et Preuve Automatisée (`99-verify`) (Priority: P1)

En tant qu'auditeur de sécurité et évaluateur du cours, je veux pouvoir basculer `lab_mode` à `isolated`, appliquer uniquement le pare-feu via `ansible-playbook 01-infra.yml --tags firewall`, et exécuter `99-verify.yml` qui prouve par `assert` que les 4 accès interdits échouent (LAN, interface web Proxmox `:8006`, Internet, SSH vers `logging`) tandis que les 3 accès autorisés réussissent (`target:8080`, `llama-server:8081/health`, `logging:514`).

**Why this priority**: C'est le point d'orgue de la démonstration vidéo (7:15) et la garantie que l'agent LLM ne peut ni s'échapper vers le LAN/Internet ni altérer les journaux sur `logging`.

**Independent Test**: Passer `lab_mode: isolated`, lancer `01-infra.yml --tags firewall`, puis `99-verify.yml` et constater le message `Isolation confirmée : 4 refus attendus, 3 accès autorisés` ainsi que les entrées `LAB-REJECT-*` dans `journalctl -k` sur l'hôte Proxmox.

---

### User Story 5 - Livrable Documentaire `.docx` et Scénario Vidéo (Priority: P1)

En tant qu'étudiant remettant le projet sur LEA le 24 novembre 2026 à 23 h 59, je veux un document `.docx` structuré comme un laboratoire de cours étape par étape (couvrant 100 % des critères de notation) ainsi qu'un script de vidéo chronométré de 10 minutes.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Le dépôt Ansible sur le LXC 300 (`/root/lab-ansible`) DOIT utiliser le sous-réseau `10.30.0.0/24` sur le bridge `vmbr3` (hôte en `10.30.0.1`) et ne jamais modifier `vmbr0`, `vmbr9` ni les interfaces Ludus.
- **FR-002**: Le fichier `nftables.conf.j2` DOIT utiliser exclusivement `destroy table inet lab_filter`, `destroy table ip lab_nat` et `destroy table bridge lab_l2` (jamais `flush ruleset`) et être validé par `validate: nft -c -f %s`.
- **FR-003**: Le playbook `90-destroy.yml` DOIT exporter les journaux `/var/log/lab/*.log` vers `./exports/` avant de supprimer les VM ciblées (`vms_to_destroy` ou tout le groupe `lab`) et nettoyer leurs clés SSH dans `known_hosts`.
- **FR-004**: Les secrets Proxmox (`vault_proxmox_*`) DOIVENT être stockés dans `group_vars/all/vault.yml` (chiffré par Ansible Vault) et chaque tâche les utilisant DOIT avoir `no_log: true`.
- **FR-005**: Tous les playbooks de configuration (`01-infra`, `02-base`, `03-logging`, `04-target`, `05-agent`) DOIVENT être idempotents (`changed=0` au second passage).

## Success Criteria *(mandatory)*

- **SC-001**: `ansible proxmox -m ping` et `ansible lab -m ping` retournent `SUCCESS => pong`.
- **SC-002**: Un second passage de `ansible-playbook site.yml` en mode `provisioning` se termine avec `changed=0` et `failed=0`.
- **SC-003**: En mode `isolated`, `ansible-playbook 99-verify.yml` passe l'`assert` final avec succès (4 refus attendus + 3 accès positifs + logs noyau `LAB-REJECT-*` visibles sur l'hôte).
- **SC-004**: Le document `.docx` final contient toutes les sections exigées par l'énoncé du cours AEC LEA.84 et le journal des difficultés mis à jour.
