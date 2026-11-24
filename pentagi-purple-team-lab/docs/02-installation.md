# 02 — Installation

Deux chemins. Choisis-en **un**. Les deux donnent le même labo.

## Prérequis (hôte du labo)

- Une VM/serveur **dédié**, Debian 12+ ou Ubuntu 22.04+, **séparé** du labo
  Proxmox sensible.
- Minimum PentAGI : **2 vCPU, 4 Go RAM, 20 Go disque**. Confortable : 4 vCPU,
  8 Go. Avec un cerveau local (Option B/C) sur CPU, prévois beaucoup plus de RAM.
- Accès Internet **pour tirer les images** (le champ de tir, lui, restera isolé
  une fois lancé).
- Un cerveau LLM : une clé API cloud, ou un serveur local OpenAI-compatible, ou
  l'option Ollama embarquée. Voir [03](03-choix-cerveau-llm.md).

---

## Chemin A — Scripts (hôte Docker déjà prêt)

```bash
# 1. Récupère le projet sur l'hôte, place-toi à sa racine
cp .env.lab.example .env

# 2. Vérifie Docker + génère les secrets (COOKIE_SIGNING_SALT, mot de passe PG)
./scripts/preflight.sh --gen-secrets

# 3. Édite .env → section 2 : décommente UN cerveau LLM, p.ex. :
#      ANTHROPIC_API_KEY=sk-ant-...
#    (ou OPEN_AI_KEY=..., ou l'option B/C)

# 4. Démarre
make up                 # = ./scripts/lab-up.sh
#   cerveau hors-ligne Ollama :  make up-ollama

# 5. Vérifie l'état + l'isolation
make status
```

Installe Docker d'abord si besoin :
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER" && newgrp docker
```

---

## Chemin B — Ansible (VM dédiée, de zéro)

Depuis ton poste (nœud de contrôle) :

```bash
# 0. Prépare .env comme ci-dessus (étapes 1–3) à la racine du projet
cp .env.lab.example .env
./scripts/preflight.sh --gen-secrets
#   puis renseigne un cerveau LLM dans .env

cd ansible

# 1. Collections requises
ansible-galaxy collection install -r requirements.yml -p ./.collections

# 2. Inventaire : mets l'IP et l'utilisateur SSH de ta VM
nano inventory/hosts.ini               # ansible_host=..., ansible_user=...
nano inventory/host_vars/pentagi-lab.yml   # clé SSH, interface réseau, expose_ui_on_lan

# 3. (optionnel) simulation sans rien changer
ansible-playbook site.yml --check

# 4. Déploiement complet
ansible-playbook site.yml
```

Le playbook enchaîne les rôles : `common` (paquets, nftables) →
`docker_host` (Docker CE) → `firewall_isolation` (nftables + DOCKER-USER) →
`pentagi` (copie du projet + `docker compose up`) → `targets` (validation de
l'isolation et de l'atteignabilité des cibles). Lancer une étape seule :
`ansible-playbook site.yml --tags firewall`.

---

## Accéder à l'interface web

Par défaut, l'UI écoute sur **`127.0.0.1:8443`** de l'hôte (non exposée au LAN).
Ouvre un **tunnel SSH** depuis ton poste :

```bash
ssh -L 8443:127.0.0.1:8443 labadmin@<IP-de-la-VM>
# puis dans ton navigateur : https://localhost:8443
```

Identifiants initiaux : **`admin@pentagi.com` / `admin`** → **change le mot de
passe dès la première connexion** (Settings).

Pour exposer l'UI directement sur le LAN (déconseillé) : mets `PENTAGI_LISTEN_IP`
à l'IP de la VM dans `.env`, ou `expose_ui_on_lan: true` côté Ansible, et ouvre
le port 8443 à tes seuls postes de confiance.

## Arrêt / nettoyage

```bash
make down          # stoppe, garde les données (BD, modèles)
make purge         # stoppe ET supprime les volumes — IRRÉVERSIBLE
```
