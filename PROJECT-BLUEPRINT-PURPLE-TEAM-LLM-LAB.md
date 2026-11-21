# Blueprint & Architecture : Laboratoire Purple Team & Évaluation d'Agents LLM Autonomes sur Proxmox VE

> **Document de transfert technique pour IA avancée**  
> **Auteur du projet :** Phil (Étudiant AEC LEA.84 & Administrateur Homelab Cybersécurité)  
> **Objet :** Synthèse complète de l'infrastructure existante, des contraintes matérielles, et feuille de route pour faire évoluer le projet d'un banc d'essai scolaire vers une plateforme professionnelle d'évaluation et de confinement d'agents LLM offensifs (*Automated Red Teaming & LLM Confinement Testbed*).

---

## 1. Contexte & Vision Réelle du Projet

### 1.1 Ce qui vient d'être achevé (Le socle académique LEA.84)
Un projet d'automatisation complet sous **Ansible Core** a été construit et validé sur un hyperviseur **Proxmox VE 9.2**. Il automatise la création, la configuration, la vérification de sécurité et la destruction de machines virtuelles jetables connectées à un pont réseau strictement isolé (`vmbr3`, `10.30.0.0/24`).
- **Idempotence stricte :** Tous les playbooks tournent avec `changed=0` au second passage.
- **Preuve d'isolation mathématique :** Un playbook `99-verify.yml` valide que le pare-feu `nftables` bloque les sorties Internet, le LAN domestique, l'interface Proxmox (`:8006`) et le SSH latéral, tout en autorisant le trafic applicatif légitime (HTTP 8080 et Syslog TCP/514).
- **Inférence LLM locale :** Un modèle **Qwen 2.5 7B Instruct GGUF** (4,36 Go) tourne sur `llama-server` (CPU avec 4 threads AVX) et répond à un agent offensif Python (`hermes_agent.py`) qui audite et exploite une cible Nginx vulnérable.
- **Cache local :** Le modèle GGUF est stocké sur le contrôleur Ansible (`/root/lab-ansible/models-cache/`) pour un déploiement hors-ligne instantané.

### 1.2 Le But Réel : Sortir du cadre scolaire
L'objectif ultime est d'utiliser ce laboratoire pour **tester, auditer et évaluer des modèles LLM open-source téléchargés depuis Hugging Face** (potentiellement non censurés, altérés ou contaminés par des *jailbreaks* / portes dérobées), en leur donnant un accès à des outils offensifs (`nmap`, `curl`, `sqlmap`, `metasploit`, scripts Python) contre des cibles variées, **sans aucun risque d'évasion réseau ou de compromission de l'hyperviseur**.

Nous voulons transformer ce PoC en un **banc d'essai Purple Team automatisé et reproductible** capable de :
1. Mesurer les compétences réelles d'un LLM en test d'intrusion (*Autonomous Agent Evaluation*).
2. Analyser les traces défensives générées par l'agent IA (SIEM, EDR, détection d'anomalies).
3. Exploiter l'accélération matérielle GPU (Tesla P100 16 Go) pour exécuter des modèles de 7B, 14B ou 32B à haute vitesse.

---

## 2. Inventaire Matériel & Environnement Existant

### 2.1 Hyperviseur Hôte (`pve`)
- **Processeur :** Bi-Intel Xeon E5-2620 v0 @ 2.00 GHz (12 cœurs physiques / 24 threads, architecture Sandy Bridge-EP avec support vectoriel AVX).
- **Mémoire vive :** 128 Go RAM ECC DDR3.
- **Stockage :** 
  - `nvme-vms` (Pool LVM-Thin NVMe rapide pour les VMs et CTs).
  - `/mnt/iso-nvme` (Stockage NVMe avec plus de 230 Go d'espace libre).
  - Stockage ZFS `data` pour les disques et sauvegardes.
- **Système d'exploitation :** Proxmox VE 9.2 (Noyau Linux 6.12/Debian 13, IP `192.168.1.116`).
- **Cartes Graphiques (GPU) :**
  1. **NVIDIA Tesla P100 PCIe 16 Go (GP100GL, sm_60 Pascal) :**
     - Adresse PCI : `0000:04:00.0`.
     - **Groupe IOMMU dédié : Groupe 37** (parfaitement isolé, aucun autre périphérique dans le groupe).
     - Rôle visé : Dédiée à 100 % à la VM `agent` pour l'inférence LLM accélérée.
  2. **NVIDIA GeForce RTX 3060 Ti 8 Go (GA104, sm_86 Ampere) :**
     - Adresse PCI : `0000:82:00.0` (Groupe IOMMU 11 avec contrôleur audio HDMI).
     - Actuellement partagée avec un conteneur LXC existant (`240` nommé `llm`) via passthrough de périphériques `/dev/nvidia*`.

### 2.2 Machines et Conteneurs Existants Hors Périmètre (À NE JAMAIS CASSER)
- `LXC 103` : `pihole` (DNS du réseau local).
- `LXC 220` : `cloudflared` (Tunnels Cloudflare).
- `LXC 240` : `llm` (Conteneur arrêté, utilisant `/dev/nvidia0`, `/dev/nvidia1` et point de montage `/mnt/llm-models`).
- `LXC 241` : `llm-downloader`.
- `VM 111` : `securityonion` (Sonde IDS/NSM connectée sur `vmbr9`).
- `Réseau Ludus` : Plages `10.<range>.x` présentes sur l'hôte Proxmox (ne jamais utiliser `flush ruleset` dans nftables pour ne pas effacer leurs règles).

---

## 3. Topologie Actuelle du Laboratoire Ansible

### 3.1 Nœud de Contrôle Ansible (`ansible`)
- **Type :** Conteneur Proxmox LXC 300 (Debian 13 minimal).
- **IP :** `192.168.1.161/24` (sur le pont LAN `vmbr0`).
- **Disque :** 23 Go (16+ Go libres).
- **Dépôt :** `/root/lab-ansible`.
- **Routage :** Script `/etc/network/if-up.d/lab-route` maintenant la route persistante : `10.30.0.0/24 via 192.168.1.116 dev eth0`.
- **Cache local :** `/root/lab-ansible/models-cache/Qwen2.5-7B-Instruct-Q4_K_M.gguf` (4,36 Go).

### 3.2 Le Réseau Isolé du Lab (`vmbr3`)
- **Pont Linux :** `vmbr3` (`10.30.0.1/24`, `bridge-ports none`).
- **Filtrage Pare-feu (nftables) :**
  - **Couche 3/4 (`table inet lab_filter`) :**
    - En mode `provisioning` : NAT sortant actif pour `apt update` et téléchargements, blocage strict des plages RFC1918 vers le LAN domestique.
    - En mode `isolated` : NAT coupé, tout paquet sortant du pont est immédiatement rejeté (`reject`) avec journalisation `LAB-REJECT-SORTIE`. Tout accès vers l'hyperviseur (`:8006`) est rejeté (`LAB-REJECT-IN`).
    - Entrée dans le lab : Strictement limitée au port SSH TCP/22 provenant du contrôleur `192.168.1.161`.
  - **Couche 2 (`table bridge lab_l2`) :**
    - Confiné à `vmbr3` via `meta ibrname != "vmbr3" accept`.
    - Règles anti-usurpation IP/ARP (`LAB-SPOOF drop`) basées sur les adresses MAC et IPs assignées.
    - Le serveur de logs n'accepte **que** le port TCP/514 (Syslog). Tout SSH ou HTTP latéral vers le serveur de logs est bloqué (`LAB-REJECT-LOGS drop`).
  - **NAT (`table ip lab_nat`) :** Masquerade sur l'interface sortante actif uniquement en mode `provisioning`.

### 3.3 Les Trois VMs Jetables (Clonées depuis le Template Cloud-Init 9000)
1. **VM 301 (`agent`) — Attaquant IA :**
   - IP : `10.30.0.10/24`.
   - Specs : 8 vCPUs, 32 Go RAM, 80 Go NVMe.
   - Logiciels : `llama-server` (b12549, port 8081), modèle Qwen 2.5 7B Instruct GGUF, `nmap`, `curl`, `netcat`, `python3-requests`, agent `hermes_agent.py`.
2. **VM 302 (`target`) — Cible Vulnérable :**
   - IP : `10.30.0.20/24`.
   - Specs : 2 vCPUs, 2 Go RAM, 20 Go NVMe.
   - Logiciels : Nginx configuré avec `autoindex on` (listage de répertoire exposé) sur le port `8080`.
3. **VM 303 (`logging`) — Serveur de Journaux Immuables :**
   - IP : `10.30.0.30/24`.
   - Specs : 2 vCPUs, 2 Go RAM, 20 Go NVMe.
   - Logiciels : `rsyslog` serveur écoutant sur TCP/514, séparant les logs par fichier client : `/var/log/lab/10.30.0.10.log` et `/var/log/lab/10.30.0.20.log`.

---

## 4. Limites Actuelles & Points de Blocage à Résoudre

| Domaine | État Actuel | Limite Constatée | Objectif Souhaité |
| :--- | :--- | :--- | :--- |
| **Inférence LLM** | Inférence CPU (4 threads AVX) | ~5 à 8 tokens/sec. Fait chauffer les Xeon E5-2620 à 70 °C. Limité à un modèle 7B quantifié. | **Passthrough PCIe de la Tesla P100 (16 Go)** pour tourner à 50-80 tokens/sec et faire tourner du 14B ou 32B. |
| **Pilotes Hôte vs VM** | Le pilote propriétaire `nvidia` (580.178) est chargé sur l'hôte Proxmox pour LXC 240. | `0000:04:00.0` n'est pas lié à `vfio-pci`. Lier la P100 à VFIO sans corrompre le pilote hôte pour la RTX 3060 Ti. | Configurer Proxmox pour délier dynamiquement la P100 vers `vfio-pci` pour la VM 301 sans casser le LXC 240. |
| **Intelligence de l'Agent** | Script guidé en 3 étapes (`nmap` -> LLM -> `curl`) | Déterministe et rigide, conçu pour garantir une note d'école, mais ce n'est pas un agent autonome complet. | **Vraie boucle agentique autonome (ReAct / Tool Calling)** où le LLM reçoit des outils et prend 100 % des décisions tactiques. |
| **Complexité de la Cible** | Un seul Nginx vulnérable sur le port 8080 | Trop simple : n'importe quel LLM trouve la faille en un coup. | Cibles complexes multi-services : Web apps (DVWA, JuiceShop), APIs REST avec failles OWASP Top 10, faux Active Directory, etc. |
| **Télémétrie & Détection** | Syslog texte brut (`/var/log/lab/*.log`) | Les logs sont stockés mais pas analysés automatiquement. | Intégration d'un mini EDR / SIEM (Wazuh, Falco ou Suricata) pour scorer l'agent sur sa furtivité et la détection d'anomalies. |
| **Benchmarking Automatisé** | Playbook Ansible exécutant un scénario unique | Pas de métriques standardisées pour comparer plusieurs modèles LLM (Qwen vs Mistral vs Llama 3 vs DeepSeek). | Matrice de scoring automatisée : Temps de résolution, nombre de requêtes, taux d'hallucination, respect des règles d'engagement. |

---

## 5. Questions Précises & Défis Soumis au Prochain LLM

Si tu analyses ce document pour m'aider à faire évoluer cette infrastructure, voici les 5 chantiers prioritaires sur lesquels j'attends tes recommandations concrètes et ton expertise :

### Question 1 : Passthrough PCIe Propre de la Tesla P100 (16 Go)
- **Le problème :** L'hôte Proxmox VE 9.2 charge actuellement le module `nvidia` pour la P100 (`04:00.0`) et la 3060 Ti (`82:00.0`). La P100 est isolée dans l'IOMMU group 37.
- **La question :** Comment configurer Proxmox (via `/etc/modprobe.d/vfio.conf`, `driverctl` ou la gestion PCI mapping `/cluster/mapping/pci`) pour assigner exclusivement la P100 à `vfio-pci` lors du démarrage de la VM 301, tout en laissant la RTX 3060 Ti utilisable par l'hôte ou par LXC 240 ? Quelle est la démarche pour installer CUDA proprement dans la VM invitée Debian 13 (noyau 6.12) sachant que la P100 est en architecture Pascal (sm_60) ?

### Question 2 : Implémentation d'un Agent Autonome (Tool Calling / ReAct Loop)
- **Le problème :** Le script actuel impose les étapes d'audit.
- **La question :** Quelle architecture recommandes-tu pour créer un véritable agent autonome tournant localement sur la VM `agent` ?
  - Faut-il utiliser le protocole natif de Tool Calling d'Hermes / Qwen (OpenAI function calling format avec `tools=[...]`) via `llama-server` ?
  - Faut-il déployer un framework léger comme **LangGraph**, **Smolagents** (Hugging Face) ou une boucle Python ReAct sur mesure sans dépendances lourdes ?
  - Comment borner l'agent (timeout, budget de tokens, règles de sécurité) pour éviter les boucles infinies ?

### Question 3 : Enrichissement de la Cible & Scénarios Purple Team Réalistes
- **Le problème :** Un simple répertoire ouvert sur Nginx est insuffisant pour tester la réflexion d'un LLM.
- **La question :** Quels conteneurs ou VMs cibles devrions-nous intégrer dans notre topologie Ansible ?
  - Comment orchestrer des scénarios progressifs (Flag 1 : reconnaissance réseau, Flag 2 : exploitation web / injection SQL / SSRF, Flag 3 : escalade de privilèges locale sur la cible) ?
  - Comment Ansible peut-il réinitialiser automatiquement la cible entre deux tests de modèles différents ?

### Question 4 : Mesure de la Furtivité et Détection (Purple Team Analytics)
- **Le problème :** Le serveur `logging` accumule des lignes rsyslog brutes.
- **La question :** Comment transformer cette journalisation en un véritable moteur d'évaluation défensive ?
  - Peux-tu proposer une intégration légère de règles Sigma, Suricata ou auditd sur `logging` ou sur l'hôte Proxmox pour attribuer un score de furtivité à l'agent (ex: a-t-il lancé un scan Nmap bruyant `-p-` détecté immédiatement, ou a-t-il ciblé précisément les ports) ?

### Question 5 : Pipeline Automatisé de Benchmarking de Modèles LLM
- **Le problème :** Actuellement, le test est manuel et utilise un seul modèle.
- **La question :** Comment structurer un playbook Ansible ou un script orchestrateur pour tester successivement 5 modèles open-source différents (ex: Qwen 2.5 Coder 7B, Mistral 7B Instruct v0.3, Llama 3.1 8B, DeepSeek-Coder, Starcoder) :
  1. Charger le modèle dans `llama-server`.
  2. Lancer la même mission d'audit.
  3. Enregistrer les métriques (Succès/Échec, durée, consommation mémoire, nombre de tokens générés, pertinence des commandes).
  4. Générer un tableau comparatif au format Markdown/JSON.

---

## 6. Structure Actuelle des Fichiers du Projet (Répertoire `/root/lab-ansible`)

```text
/root/lab-ansible/
├── ansible.cfg                          # Configuration Core 2.21 (stdout_callback = default, result_format = yaml)
├── inventory/
│   └── hosts.yml                        # Inventaire (groupes proxmox_host, attacker, web, logs, lab)
├── group_vars/
│   └── all/
│       ├── vars.yml                     # Variables réseau, templates, modèle GGUF, ports
│       └── vault.yml                    # Identifiants Proxmox chiffrés AES-256
├── host_vars/
│   ├── pve.yml                          # Paramètres de l'hyperviseur Proxmox
│   ├── agent.yml                        # vCPU: 8, RAM: 32768, Disk: 80, VMID: 301
│   ├── target.yml                       # vCPU: 2, RAM: 2048, Disk: 20, VMID: 302
│   └── logging.yml                      # vCPU: 2, RAM: 2048, Disk: 20, VMID: 303
├── roles/
│   ├── proxmox_network/                 # vmbr3, interfaces.d, tables nftables et persistance
│   ├── proxmox_vms/                     # Clonage Cloud-Init API Proxmox, resize scsi0, démarrage
│   ├── common/                          # User ansible, sudo NOPASSWD, sshd durci, client rsyslog
│   ├── log_server/                      # Serveur rsyslog TCP/514, ventilation /var/log/lab/%fromhost-ip%.log
│   ├── web_target/                      # Nginx vulnérable port 8080 (autoindex on)
│   └── agent_host/                      # Outils offensifs, llama-server systemd, cache local, hermes_agent.py
├── playbooks/ (et racine)
│   ├── 01-infra.yml                     # Déploiement réseau, pare-feu et VMs
│   ├── 02-base.yml                      # Socle commun sur les VMs
│   ├── 03-logging.yml                   # Déploiement du serveur de logs
│   ├── 04-target.yml                    # Déploiement de la cible Nginx
│   ├── 05-agent.yml                     # Déploiement de l'environnement LLM et Hermes
│   ├── site.yml                         # Playbook maître orchestrant 01 à 05
│   ├── 99-verify.yml                    # Suite d'assertion de sécurité (3 positifs + 4 négatifs)
│   └── 90-destroy.yml                   # Arrêt et destruction sélective ou totale des VMs
└── models-cache/
    └── Qwen2.5-7B-Instruct-Q4_K_M.gguf  # Cache local de 4.36 Go pour déploiement hors-ligne instantané
```

---

*Ce document résume l'intégralité du projet. Tu as maintenant tous les éléments d'architecture, les contraintes matérielles et les configurations réseau pour concevoir les améliorations de niveau professionnel.*
