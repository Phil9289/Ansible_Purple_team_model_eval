# Tasks: Lab Ansible Proxmox — VM Jetables & Isolation d'Agent LLM

**Input**: [spec.md](file:///d:/one%20drive/OneDrive%20-%20Cegep%20de%20Sherbrooke/Documents/Ansible%20projet%20linux/specs/001-ansible-proxmox-llm-lab/spec.md), [plan.md](file:///d:/one%20drive/OneDrive%20-%20Cegep%20de%20Sherbrooke/Documents/Ansible%20projet%20linux/specs/001-ansible-proxmox-llm-lab/plan.md)

---

## Phase 1: Préparation & Alignement du Nœud de Contrôle (LXC 300 ↔ Hôte Proxmox)

- [x] T001 Créer le conteneur LXC 300, installer Ansible (`community.proxmox`, `ansible.posix`, `community.general`) et valider le template `9000` (`debian13-cloudinit-tpl`).
- [x] T002 Créer l'utilisateur `ansible@pve`, le rôle `AnsibleProvisioning`, le jeton `ansible@pve!automation` et chiffrer `group_vars/all/vault.yml`.
- [x] T003 Créer et activer le bridge isolé `vmbr3` (`10.30.0.1/24`) dans `/etc/network/interfaces.d/vmbr3-lab` et nettoyer les doublons (`AnsibleLab`, jeton `lab`, VM `999`).
- [x] T004 Configurer le `$PATH` (`/root/.local/bin`) sur le LXC 300, vérifier la route du LXC 300 vers `10.30.0.0/24 via 192.168.1.116`, et autoriser la clé SSH du LXC 300 vers l'hôte Proxmox (`ansible proxmox -m ping` -> `pong`).
- [x] T005 Inspecter les noms exacts des variables dans `group_vars/all/vault.yml` (sans afficher les secrets) et aligner `inventory/hosts.yml`, `group_vars/all/vars.yml` et `host_vars/{pve,agent,target,logging}.yml` sur `vmbr3` (`10.30.0.0/24`).

---

## Phase 2: Réseau Isolé, Pare-feu `nftables` & Provisionnement des VM (`01-infra` & `90-destroy`) (Priority: P1)

- [x] T006 Écrire le rôle `roles/proxmox_network` (`tasks/main.yml`, `handlers/main.yml`, `templates/vmbr3-lab.j2`, `templates/nftables.conf.j2`, `templates/lab-nftables.service.j2`) avec `ifup vmbr3` (au lieu de `ifreload -a`) et `validate: nft -c -f %s`.
- [x] T007 Tester `01-infra.yml --tags firewall` en mode `provisioning` sur l'hôte Proxmox et vérifier que `nft list table inet lab_filter`, `nft list table ip lab_nat` et `nft list table bridge lab_l2` sont actives sans impacter Proxmox ni Ludus.
- [x] T008 Vérifier les paramètres exacts de `community.proxmox.proxmox_kvm` et `proxmox_disk` installés sur le LXC 300 (`ansible-doc`), puis écrire le rôle `roles/proxmox_vms/tasks/main.yml` et le playbook `01-infra.yml`.
- [x] T009 Écrire le playbook `90-destroy.yml` (export des journaux + suppression des VM via l'API + nettoyage `known_hosts`).
- [x] T010 Tester le cycle complet `01-infra.yml` (création des 3 VM + attente SSH + `ansible lab -m ping` -> `pong` + test `apt update` via NAT) et vérifier l'idempotence d'un 2e passage.

---

## Phase 3: Socle Commun, Serveur de Journaux & Cible Web (`02-base`, `03-logging`, `04-target`) (Priority: P1)

- [x] T011 Écrire le rôle `roles/common` (`tasks/main.yml`, `handlers/main.yml`, `templates/sshd_config.j2`, `templates/rsyslog-client.conf.j2`) et le playbook `02-base.yml`.
- [x] T012 Écrire le rôle `roles/log_server` (`tasks/main.yml`, `handlers/main.yml`, `templates/rsyslog-server.conf.j2`) et le playbook `03-logging.yml`.
- [x] T013 Écrire le rôle `roles/web_target` (`defaults/main.yml`, `tasks/main.yml`, `handlers/main.yml`, `templates/nginx-site.conf.j2`) et le playbook `04-target.yml`.
- [x] T014 Exécuter `02-base.yml`, `03-logging.yml` et `04-target.yml` deux fois de suite pour valider `changed=0` au 2e run, vérifier `http://10.30.0.20:8080` et la création des journaux par IP dans `/var/log/lab/` sur `logging`.

---

## Phase 4: Serveur d'Exécution de l'Agent LLM & GPU P100 (`05-agent`) (Priority: P2)

- [x] T015 Vérifier sur l'hôte Proxmox l'état IOMMU / `vfio-pci` de la Tesla P100, créer le mappage PCI `p100` et ajouter `Mapping.Use` au rôle `AnsibleProvisioning` (ou activer le repli `gpu_passthrough: false` si souhaité pour un premier test rapide).
- [x] T016 Écrire le rôle `roles/agent_host` (`defaults/main.yml`, `tasks/{main,tools,nvidia,llama,model,hermes}.yml`, `handlers/main.yml`, templates systemd/config) et le playbook `05-agent.yml` + `site.yml`.
- [x] T017 Exécuter `05-agent.yml` deux fois de suite pour valider le fonctionnement de `llama-server` (`127.0.0.1:8081/health`), d'Hermes et l'idempotence (`changed=0` au 2e run).

---

## Phase 5: Bascule `isolated` & Preuve de Sécurité (`99-verify`) (Priority: P1)

- [x] T018 Écrire le playbook `99-verify.yml` (4 tests négatifs avec `ignore_errors: true` + 3 tests positifs + `assert` final + lecture de `journalctl -k --grep=LAB-` sur l'hôte).
- [x] T019 Basculer `lab_mode: isolated`, exécuter `ansible-playbook 01-infra.yml --tags firewall` puis `ansible-playbook 99-verify.yml` et valider le succès de l'assertion finale.

---

## Phase 6: Documentation `.docx` finale & Préparation de la Vidéo (Priority: P1)

- [x] T020 Mettre à jour les pages Notion (remplacer `vmbr9`/`10.90.0.0/24` par `vmbr3`/`10.30.0.0/24` et compléter le *Journal de difficultés*).
- [x] T021 Générer le document `.docx` final formaté étape par étape pour le dépôt sur LEA (incluant concepts Ansible, architecture, code commenté des playbooks/rôles/templates, preuves de validation et journal des difficultés).
- [ ] T022 Préparer l'état initial de tournage de la vidéo (mode `provisioning`, `target` détruite seule avec `90-destroy.yml -e '{"vms_to_destroy": ["target"]}'`).
