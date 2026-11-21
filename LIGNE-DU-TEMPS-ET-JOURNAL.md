# Ligne du Temps & Journal de Progression du Projet
**Projet :** Laboratoire Purple Team & Isolation LLM sur Proxmox VE avec Ansible  
**Cours :** Auto-initiation à Ansible (AEC LEA.84) — Cégep de Sherbrooke  
**Échéance finale :** 24 novembre 2026 à 23 h 59 (Dépôt documentation sur LEA & Vidéo YouTube)

---

## 📅 Vue d'ensemble du Calendrier & Jalons

```
[12 nov. 2026] ──> Cadrage du projet, architecture Purple Team, constitution & spécifications
       │
[14 nov. 2026] ──> Préparation nœud de contrôle LXC 300, API Proxmox & Ansible Vault
       │
[16 nov. 2026] ──> Création du bridge dédié vmbr3 (10.30.0.0/24), template 9000 & tests SSH
       │
[19 nov. 2026] ──> 🚀 DÉPLOIEMENT COMPLET DES 5 PHASES (100 % opérationnel) :
       │           • Phase 1 : IP statique LXC 300 & persistance réseau
       │           • Phase 2 : Clonage automatique des 3 VMs & nftables
       │           • Phase 3 : Cible web vulnérable & serveur de logs rsyslog
       │           • Phase 4 : Agent LLM Qwen 2.5 7B, optimisation CPU & mission Hermes
       │           • Phase 5 : Isolation étanche validée par 99-verify.yml
       │           • Phase 6 : Cache local 4.4 Go, rapport Word .docx & trame vidéo
       │
[20-23 nov.]   ──> Tournage de la vidéo de démonstration (10 min) selon la trame
       │
[24 nov. 2026] ──> Dépôt final sur la plateforme LEA
```

---

## 📝 Chronologie Détaillée des Travaux Réalisés

### 12 Novembre 2026 — Cadrage, Architecture et Spécifications Initiales
- **Contexte & Décision clé :** Décision de ne pas se limiter à une simulation GNS3 basique, mais de bâtir une infrastructure réelle à domicile sur Proxmox VE 9.2 (Bi-Xeon E5-2620, 128 Go RAM).
- **Objectifs définis :**
  1. Respecter 100 % de la grille d'évaluation LEA.84 (Ansible concepts, Vault, inventaire, playbooks, rôles, handlers, idempotence, journal des difficultés).
  2. Créer un environnement Purple Team sécurisé pour tester des modèles LLM potentiellement non fiables contre une cible vulnérable (`target`), avec télémétrie centralisée (`logging`).
- **Initialisation du projet :** Mise en place du GitHub Spec Kit (`.specify/memory/constitution.md`, spécifications `spec.md`, plan technique `plan.md` et liste ordonnée des tâches `tasks.md`).

---

### 14 Novembre 2026 — Nœud de Contrôle, Sécurité de l'API & Ansible Vault
- **Nœud de contrôle LXC 300 :** Déploiement du conteneur d'administration sous Debian 13 (`ansible`).
- **Authentification Proxmox à moindre privilège :**
  - Création de l'utilisateur dédié `ansible@pve` (aucun usage du compte root de l'hyperviseur pour l'API).
  - Création du rôle Proxmox sur mesure `AnsibleProvisioning` avec les privilèges strictement nécessaires.
  - Découverte que `VM.Monitor` n'existe plus dans Proxmox 9 : adaptation des privilèges.
  - Génération du jeton d'API `ansible@pve!automation`.
- **Ansible Vault :**
  - Chiffrement du fichier `group_vars/all/vault.yml` en AES-256 avec mot de passe stocké dans `/root/.vault_pass` (permissions 600).
  - Stockage sécurisé des variables sensibles (`proxmox_api_user`, `proxmox_api_token_id`, `proxmox_api_token_secret`).
- **Arborescence Ansible :** Création de la structure modulaire (`inventory/`, `group_vars/`, `roles/`, `playbooks/`).

---

### 16 Novembre 2026 — Réseau Isolé vmbr3 & Template Cloud-Init
- **Bridge dédié `vmbr3` :**
  - Configuration de `/etc/network/interfaces.d/vmbr3-lab` sur l'hôte avec `bridge-ports none` pour isoler physiquement le laboratoire du réseau LAN (`vmbr0`) et de Security Onion (`vmbr9`).
  - Attribution de l'adresse de passerelle `10.30.0.1/24`.
  - Activation sécurisée par `ifup vmbr3` (sans toucher aux autres bridges actifs).
- **Validation Cloud-Init :**
  - Test d'un clone de validation (VM 999) depuis le template Debian 13 (`9000`).
  - Validation de l'injection automatique de l'utilisateur de service `ansible` et de la clé publique SSH `id_ed25519.pub`.
  - Destruction propre de la VM de test après validation.

---

### 19 Novembre 2026 — Déploiement Intégral, Résolutions Techniques & Livrables

#### 1. Phase 1 : Stabilisation du Nœud de Contrôle
- Attribution de l'adresse IP statique `192.168.1.161/24` au conteneur LXC 300.
- **Difficulté résolue :** Proxmox écrase `/etc/network/interfaces` dans les LXC au redémarrage. Création d'un script persistant `/etc/network/if-up.d/lab-route` pour garantir la route vers `10.30.0.0/24 via 192.168.1.116`.

#### 2. Phase 2 : Rôles d'Infrastructure Proxmox & Déploiement des 3 VMs
- Déploiement de `roles/proxmox_network` : création des tables nftables dédiées (`inet lab_filter`, `ip lab_nat`, `bridge lab_l2`) et de l'unité systemd de persistance `lab-nftables.service`.
- **Difficulté résolue :** Correction de la table L2 pour insérer `meta ibrname != "vmbr3" accept`, évitant tout impact sur `vmbr0` et `vmbr9`.
- Déploiement de `roles/proxmox_vms` : clonage automatique des 3 VMs :
  - `agent` (VMID 301, `10.30.0.10`, 8 vCPUs, 32 Go RAM)
  - `target` (VMID 302, `10.30.0.20`, 2 vCPUs, 2 Go RAM)
  - `logging` (VMID 303, `10.30.0.30`, 2 vCPUs, 2 Go RAM)
- **Difficulté résolue :** Bug du hot-plug VirtIO causant la perte de l'IP en mémoire vive au 2e run. Résolution par interrogation de l'état avec `proxmox_vm_info` pour contourner la reconfiguration à chaud sur les VMs déjà actives.
- Validation : `01-infra.yml` s'exécute avec `changed=0` au second passage.

#### 3. Phase 3 : Socle Commun, Cible Web & Serveur de Journaux
- Déploiement de `roles/common` : utilisateur `ansible`, sudoers sans mot de passe, durcissement SSH.
- Déploiement de `roles/log_server` : rsyslog configuré en écoute TCP/514 avec ventilation dynamique des fichiers par IP source (`/var/log/lab/%fromhost-ip%.log`).
- Déploiement de `roles/web_target` : Nginx déployé avec un template simulant une vulnérabilité de listage de répertoire (`autoindex on`) sur le port 8080.
- Exécution de `site.yml` : **Idempotence parfaite validée (`changed=0` sur toutes les machines)**.
- Test de validation : `http://10.30.0.20:8080` répond HTTP 200 et les logs Syslog s'enregistrent sur `logging`.

#### 4. Phase 4 : Environnement Offensif, Modèle LLM 7B & Agent Hermes
- **Choix du modèle :** Abandon du modèle 1.5 Go au profit d'un modèle supérieur pour éviter les erreurs d'audit : adoption de **Qwen 2.5 7B Instruct GGUF** (4,36 Go).
- **Difficulté résolue :** Sur le dépôt officiel, le modèle était scindé en 2 fichiers. Sélection du fichier monolithique sur le dépôt `bartowski/Qwen2.5-7B-Instruct-GGUF`.
- **Moteur d'inférence :** Déploiement de `llama-server` (version officielle b12549 intégrant toutes les bibliothèques partagées `libllama.so` et `libggml`).
- **Gestion thermique :**
  - Lors du premier essai avec 8 threads AVX, les processeurs sont montés à 86 °C.
  - Découverte que les ventilateurs du boîtier étaient montés à l'envers (luttant contre le flux d'air chaud). Réinstallation des ventilateurs dans le bon sens d'extraction.
  - Ajustement de `llama-server` à **4 threads** (confiné au socket NUMA 0) et réponse limitée à 150 tokens : temps d'inférence réduit à **~8 secondes** et température stabilisée à **69-71 °C**.
- **Mission Hermes réussie :** Scan Nmap -> Analyse par Qwen 7B -> Détection Nginx -> Exploitation curl de `Index of /` -> Rapport de mission enregistré avec statut `SUCCESS` -> Télémétrie transmise à `logging`.

#### 5. Phase 5 : Preuve de Sécurité & Isolation Étanche
- Bascule en mode étanche : `lab_mode: "isolated"` dans `group_vars/all/vars.yml`.
- Réapplication des règles nftables sur l'hôte Proxmox.
- Exécution du playbook `99-verify.yml` :
  - ✅ **3 tests positifs réussis :** Web cible (HTTP 200), Syslog distant (TCP 514), API LLM locale (status: ok).
  - 🛡️ **4 tests négatifs validés (rejets immédiats) :** Internet (`1.1.1.1`), LAN (`192.168.1.1`), Proxmox UI (`:8006`), SSH inter-VMs.
  - 🎯 **Assertion finale :** `SUCCÈS TOTAL : Tous les flux autorisés sont opérationnels et tous les flux interdits sont strictement bloqués par nftables !`
  - 🔍 **Traces du noyau :** Capture des logs `LAB-REJECT-SORTIE`, `LAB-REJECT-IN` et `LAB-REJECT-LOGS` dans `journalctl` de Proxmox.

#### 6. Phase 6 : Optimisation Cache Local & Livrables Finaux
- **Cache local permanent du modèle LLM :**
  - Agrandissement du disque du LXC 300 à 23 Go.
  - Stockage du modèle Qwen 7B (4,4 Go) dans `/root/lab-ansible/models-cache/`.
  - Mise à jour du rôle `agent_host` : copie locale en ~15 secondes lors des redéploiements futurs, sans jamais avoir à retélécharger sur Internet.
- **Trame de la vidéo de 10 min :** Rédaction de `TRAME-VIDEO-DEMO.md` avec timing à la seconde, disposition d'écran et script vocal complet vulgarisant les concepts Ansible.
- **Rapport officiel Word (.docx) :**
  - Rédaction et compilation de `Rapport-Projet-Ansible-Proxmox-LEA84.docx`.
  - Correction du double encodage UTF-8/ANSI pour des accents parfaits (`é`, `è`, `à`, puces).
  - Format concis et dense respectant 100 % de la grille d'évaluation du Cégep de Sherbrooke.
- **Notion :** Synchronisation complète du Hub de projet et du Journal de difficultés.

---

## 📊 Matrice Récapitulative des Difficultés & Solutions

| # | Défi technique rencontré | Cause identifiée | Solution reproductible appliquée |
| :-: | :--- | :--- | :--- |
| **1** | Échec SSL API Proxmox (`CERTIFICATE_VERIFY_FAILED`) | Certificat auto-signé par défaut sur Proxmox port 8006 | Paramètre `validate_certs: false` ajouté aux modules `proxmox_kvm` et `proxmox_disk` |
| **2** | Perte d'IP VirtIO lors du 2e run (Hot-plug) | Reconfiguration de `net0` sur VM allumée réinitialisant le lien | Vérification préalable avec `proxmox_vm_info` pour ignorer les VMs déjà en statut `running` |
| **3** | Perte de route statique après reboot du LXC 300 | Régénération automatique de `/etc/network/interfaces` par Proxmox | Création d'un script persistant exécutable dans `/etc/network/if-up.d/lab-route` |
| **4** | Risque d'interception L2 sur les ponts existants | Table bridge globale inspectant tous les ponts de l'hyperviseur | Règle `meta ibrname != "vmbr3" accept` placée en tête de chaîne forward |
| **5** | Modèle LLM 7B scindé sur HuggingFace (Erreur 404) | Fichiers scindés par tranches de 2 Go sur le dépôt officiel | Utilisation du dépôt unifié de *bartowski* et création d'un cache local persistant |
| **6** | Montée thermique CPU (86 °C) sous charge AVX | 8 threads traversant les sockets NUMA + ventilateurs inversés | Ventilateurs remis dans le bon sens, `llama-server` réglé à 4 threads et max 150 tokens (température stabilisée à 69-71 °C) |
| **7** | Accents corrompus (*mojibake*) dans le document .docx | Ré-encodage ANSI par défaut de PowerShell lors du pipe SSH | Téléversement direct du script via SCP en mode binaire pur et régénération native en UTF-8 |

---

## 🏁 Prochaines Étapes pour l'Étudiant (20 au 24 novembre)

1. **Tournage de la vidéo (10 min) :**
   - Suivre la trame [TRAME-VIDEO-DEMO.md](file:///d:/one%20drive/OneDrive%20-%20Cegep%20de%20Sherbrooke/Documents/Ansible%20projet%20linux/TRAME-VIDEO-DEMO.md).
   - Enregistrer l'écran (terminal LXC 300 à gauche, console Proxmox à droite).
   - Téléverser la vidéo sur YouTube en mode **Non répertorié** (*Unlisted*).
2. **Finalisation du document Word :**
   - Ouvrir [Rapport-Projet-Ansible-Proxmox-LEA84.docx](file:///d:/one%20drive/OneDrive%20-%20Cegep%20de%20Sherbrooke/Documents/Ansible%20projet%20linux/Rapport-Projet-Ansible-Proxmox-LEA84.docx).
   - Insérer votre nom et le lien YouTube de la vidéo sur la première page.
3. **Dépôt officiel :**
   - Déposer le fichier `.docx` sur la plateforme LEA avant le **24 novembre 2026 à 23 h 59**.
