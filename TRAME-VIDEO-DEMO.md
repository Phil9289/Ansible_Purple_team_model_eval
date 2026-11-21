# Trame et Scénario de la Vidéo de Démonstration (10 minutes)
**Projet : Auto-initiation à Ansible — Laboratoire Purple Team & Isolation LLM sur Proxmox VE**  
**Cours :** AEC LEA.84 — Cégep de Sherbrooke  
**Format :** Vidéo de 10 minutes maximum (YouTube non répertorié / privé)  
**Objectif de notation :** Couvrir 100 % de la grille (Concepts Ansible 20 %, Démonstration PoC 25 %, Idempotence, Rôles, Handlers, Vault, Isolation réseau).

---

## ⏱️ Vue d'ensemble du minutage (10:00 max)

| Segment | Durée | Sujet abordé | Ce que l'on montre à l'écran |
| :--- | :--- | :--- | :--- |
| **1. Intro & Concepts** | 0:00 - 2:00 | Contexte, objectifs et fondamentaux d'Ansible | Schéma d'architecture & diapositives / terminal |
| **2. Structure & Code** | 2:00 - 3:30 | Inventaire, group_vars, Vault et rôles | VS Code / Arborescence du projet `/root/lab-ansible` |
| **3. Déploiement IaC** | 3:30 - 5:30 | Création VMs Proxmox et configuration en direct | Exécution de `site.yml` + Interface Web Proxmox |
| **4. Idempotence** | 5:30 - 6:30 | Preuve d'idempotence stricte (`changed=0`) | Second passage immédiat de `site.yml` |
| **5. Mission Purple Team** | 6:30 - 8:00 | Démonstration offensive Hermes & LLM Qwen 7B | Terminal VM `agent` (Nmap -> IA -> curl -> exploit) |
| **6. Sécurité & Preuve** | 8:00 - 9:30 | Isolation nftables et centralisation Syslog | Exécution de `99-verify.yml` et logs `/var/log/lab/` |
| **7. Conclusion** | 9:30 - 10:00 | Synthèse des compétences acquises et fin | Rapport final / Terminal propre |

---

## 🎬 Déroulé pas-à-pas : ce qu'il faut dire et montrer

### Segment 1 : Introduction & Concepts fondamentaux d'Ansible (0:00 - 2:00)
- **À l'écran :** Votre schéma d'architecture réseau (`vmbr3`, LXC 300, les 3 VMs) ou votre écran d'accueil.
- **Ce qu'il faut dire (Script) :**
  > « Bonjour à tous. Dans le cadre du cours d'auto-initiation à Linux et Ansible (AEC LEA.84 au Cégep de Sherbrooke), je vous présente mon projet final d'Infrastructure as Code.
  > Plutôt qu'un simple exercice théorique, j'ai conçu un banc d'essai réel de cybersécurité Purple Team à domicile : automatiser le déploiement de machines virtuelles jetables sur un hyperviseur Proxmox VE 9, y orchestrer un agent autonome d'attaque assisté par un modèle de langage (LLM local Qwen 2.5 7B), tout en garantissant une isolation réseau étanche et une journalisation infalsifiable sur un serveur Syslog centralisé.
  > Avant de voir le code, rappelons les concepts clés d'Ansible :
  > 1. **Architecture sans agent (Agentless)** : Ansible fonctionne uniquement via SSH et Python. Aucun agent lourd n'est installé sur les cibles.
  > 2. **Nœud de contrôle vs Nœuds gérés** : Mon nœud de contrôle est le conteneur LXC 300 (`ansible`), qui orchestre l'hyperviseur Proxmox et les VMs du lab.
  > 3. **Idempotence** : C'est le principe cardinal d'Ansible : appliquer un playbook une fois ou dix fois doit produire exactement le même état, sans reconfigurer inutilement ce qui est déjà conforme. »

---

### Segment 2 : Structure de l'Inventaire, Variables et Vault (2:00 - 3:30)
- **À l'écran :** Le terminal ou VS Code ouvert sur `/root/lab-ansible`.
- **Commandes à montrer :**
  ```bash
  tree -L 2 roles/
  cat inventory/hosts.yml
  cat group_vars/all/vars.yml
  ansible-vault view group_vars/all/vault.yml
  ```
- **Ce qu'il faut dire (Script) :**
  > « Voyons la structure de mon projet.
  > - **Inventaire (`hosts.yml`)** : Il est structuré par groupes logiques : `proxmox_host` pour l'hyperviseur, `attacker` pour l'agent IA (`10.30.0.10`), `web` pour la cible vulnérable (`10.30.0.20`), et `logs` pour le serveur centralisé (`10.30.0.30`).
  > - **Gestion des variables** : J'utilise la hiérarchie recommandée par Ansible : `group_vars/all/vars.yml` pour les paramètres généraux (réseau `10.30.0.0/24`, modèle LLM Qwen 7B, taille de contexte), et `host_vars/` pour les caractéristiques matérielles spécifiques à chaque machine (vCPU, RAM, VMID).
  > - **Ansible Vault** : Les identifiants sensibles (le jeton API Proxmox) sont chiffrés avec AES-256 dans `vault.yml`. Aucun mot de passe n'apparaît en clair dans mes fichiers ou sur GitHub.
  > - **Rôles modulaires** : Le code est découpé en rôles réutilisables : `proxmox_network` pour le pare-feu nftables, `proxmox_vms` pour le clonage cloud-init, `common` pour le durcissement SSH et rsyslog, `web_target` pour Nginx, `log_server` pour le rsyslog distant, et `agent_host` pour l'environnement offensif. »

---

### Segment 3 : Déploiement complet en direct (`site.yml`) (3:30 - 5:30)
- **À l'écran :** Terminal dans LXC 300 à gauche, console Web Proxmox VE à droite (sur le bridge `vmbr3` et la liste des VMs).
- **Commande à exécuter :**
  ```bash
  ansible-playbook site.yml
  ```
- **Ce qu'il faut dire (Script) :**
  > « Je lance maintenant le playbook maître `site.yml`. Il importe successivement tous nos playbooks :
  > 1. `01-infra.yml` configure le bridge `vmbr3` sur Proxmox, configure les tables nftables, clone le template Debian 13 via l'API REST de Proxmox avec `community.general.proxmox_kvm`, injecte les clés SSH via Cloud-Init et démarre les VMs. Regardez dans l'interface Proxmox à droite : les 3 VMs s'initialisent automatiquement !
  > 2. `02-base.yml` applique le socle commun (création du compte ansible, sudoers sans mot de passe, durcissement SSH).
  > 3. `03-logging.yml` configure le serveur rsyslog sur le port 514 avec un handler de redémarrage.
  > 4. `04-target.yml` déploie le serveur Nginx avec un template Jinja2 simulant un listage de répertoire exposé.
  > 5. `05-agent.yml` installe les outils d'audit, déploie le binaire `llama-server`, configure le service systemd et prépare notre modèle Qwen 7B.
  > Vous constatez que pour le modèle LLM, j'ai configuré un cache local sur le contrôleur : le modèle de 4.4 Go est poussé en réseau local en quelques secondes, sans dépendre d'Internet ! »

---

### Segment 4 : Démonstration de l'Idempotence stricte (5:30 - 6:30)
- **À l'écran :** Même terminal dans LXC 300.
- **Commande à ré-exécuter immédiatement :**
  ```bash
  ansible-playbook site.yml
  ```
- **Ce qu'il faut dire (Script) :**
  > « Une exigence majeure de la grille d'évaluation est l'**idempotence**. Je relance immédiatement le même playbook `site.yml` sans rien modifier.
  > Observez le résultat du récapitulatif final (`PLAY RECAP`) :
  > Toutes les tâches sont en vert (`ok`), aucune n'est en jaune (`changed=0`), et aucune n'a échoué (`failed=0`).
  > Ansible a vérifié chaque fichier, chaque paquet et chaque service. Comme le système était déjà dans l'état désiré, aucune action superflue n'a été exécutée. L'idempotence est démontrée à 100 %. »

---

### Segment 5 : Simulation de l'Attaque Purple Team autonome (6:30 - 8:00)
- **À l'écran :** Terminal montrant le lancement de la mission Hermes sur la VM `agent`.
- **Commandes à exécuter :**
  ```bash
  ansible attacker -m uri -a "url=http://127.0.0.1:8081/health method=GET"
  ansible attacker -m command -a "python3 /opt/hermes/hermes_agent.py"
  ansible attacker -m command -a "cat /opt/hermes/attack_report.json"
  ```
- **Ce qu'il faut dire (Script) :**
  > « Passons au banc d'essai offensif. Sur la VM `agent`, notre moteur local `llama-server` répond bien sur le port 8081.
  > Je déclenche l'agent autonome Hermes.
  > Voici ce qui se passe :
  > 1. Hermes lance un scan Nmap sur la cible `10.30.0.20:8080`.
  > 2. Il transmet le résultat brut au modèle local Qwen 2.5 7B via l'API OpenAI compatible.
  > 3. Le LLM analyse le service HTTP Nginx et prescrit la commande d'exploitation pour auditer le listage de répertoire.
  > 4. Hermes exécute la requête, récupère le contenu confidentiel (`Index of /`) et consigne son rapport avec le statut `SUCCESS`.
  > Pendant toute cette opération, chaque étape a émis des messages Syslog vers le réseau. »

---

### Segment 6 : Preuve de Sécurité & Validation de l'Isolation (8:00 - 9:30)
- **À l'écran :** Exécution du playbook `99-verify.yml` et lecture des journaux.
- **Commandes à exécuter :**
  ```bash
  ansible-playbook 99-verify.yml
  ansible logs -m command -a "tail -n 10 /var/log/lab/10.30.0.10.log"
  ansible proxmox_host -b -m command -a "journalctl -k --grep=LAB-REJECT -n 6 --no-pager"
  ```
- **Ce qu'il faut dire (Script) :**
  > « Enfin, voici la preuve de sécurité et d'isolation réseau du laboratoire.
  > En mode `isolated`, le pare-feu nftables bloque toute évasion.
  > Notre playbook `99-verify.yml` teste automatiquement :
  > - Les 3 flux autorisés (Web cible, Syslog distant, API LLM locale) : tous réussissent.
  > - Les 4 flux interdits : la VM attaquante tente de joindre Internet (`1.1.1.1`), le LAN de la maison (`192.168.1.1`), l'interface d'administration de Proxmox (`:8006`), et tente une connexion SSH clandestine vers le serveur de logs.
  > Comme vous le voyez, l'assertion finale valide que tous les flux interdits ont été rejetés !
  > Sur le serveur `logging`, nous retrouvons les traces complètes de l'attaque classées par adresse IP source.
  > Et sur l'hôte Proxmox, les logs du noyau confirment les rejets nftables avec les préfixes `LAB-REJECT-SORTIE`, `LAB-REJECT-IN` et `LAB-REJECT-LOGS`. L'isolation est absolue. »

---

### Segment 7 : Conclusion & Nettoyage (9:30 - 10:00)
- **À l'écran :** Commande de destruction propre `90-destroy.yml` ou écran de fin.
- **Ce qu'il faut dire (Script) :**
  > « Pour terminer le cycle de vie de notre infrastructure, le playbook `90-destroy.yml` permet de détruire proprement les machines virtuelles en fin de TP, sans laisser de traces.
  > Ce projet démontre la puissance d'Ansible pour allier automatisation DevOps, rigueur d'idempotence, sécurité du code avec Vault, et scénarios réels de cybersécurité Purple Team.
  > Merci pour votre écoute, et je vous invite à consulter le rapport écrit d'accompagnement ! »

---

## 💡 Conseils pratiques pour le tournage
1. **Résolution d'écran :** Enregistrez en 1080p (1920x1080), avec une taille de police de terminal agréable (16 ou 18 pt).
2. **Double fenêtre :** Placez le terminal à gauche (65 % de l'écran) et le navigateur Proxmox à droite (35 % de l'écran).
3. **Préparation :** Testez une fois la séquence à blanc avant d'enregistrer pour être à l'aise avec le chronomètre.
4. **Voix :** Parlez à un rythme posé et naturel ; la trame ci-dessus dure exactement entre 8 min 30 et 9 min 30.
