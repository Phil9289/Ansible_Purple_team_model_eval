# PentAGI Purple Team Lab

Un laboratoire **complet, autonome et reproductible** pour tester le cadre d'agent
offensif **[PentAGI](https://github.com/vxcontrol/pentagi)** (vxcontrol) contre des
cibles délibérément vulnérables, dans un environnement **réseau isolé**.

Ce projet est **séparé** du labo Purple Team principal (le labo de cours sur
Proxmox) : base de code neuve, son propre hôte, sa propre isolation. Il réutilise
seulement des *idées* d'architecture éprouvées là-bas (isolation nftables,
inventaire + rôles Ansible, variables en group_vars/host_vars, handlers, templates).

> ⚠️ **Usage autorisé uniquement.** PentAGI lance des attaques autonomes. Ne le
> pointe QUE sur les cibles de ce labo (ou des systèmes que tu possèdes / es
> explicitement autorisé à tester). Voir [docs/06](docs/06-isolation-securite.md).

---

## Ce que fait le labo

1. **Déploie PentAGI** (stack Docker Compose officiel, non modifié) : interface
   web, API GraphQL/REST, base vectorielle PostgreSQL+pgvector, scraper.
2. **Déploie un champ de tir vulnérable** : OWASP **Juice Shop** et **DVWA**, sur
   un réseau Docker **`internal`** (aucune route vers ton LAN ni Internet).
3. **Branche PentAGI sur le champ de tir** : les conteneurs bac-à-sable que
   PentAGI crée pour exécuter ses outils (nmap, sqlmap…) rejoignent ce même
   réseau isolé, voient les cibles, mais **pas ton réseau maison**.
4. **Automatise tout** : scripts `make` pour un hôte existant, **playbook Ansible**
   pour provisionner une VM dédiée de zéro (Docker + pare-feu + stack + cibles).
5. **Documente** le choix du cerveau LLM, comment lancer une mission autonome, et
   comment lire les résultats.

## Architecture en un coup d'œil

```
          Hôte du labo (VM Debian/Ubuntu dédiée)
          ┌──────────────────────────────────────────────────────────┐
          │                                                            │
          │   Réseau "pentagi-network" (bridge, accès Internet)        │
          │   ┌───────────┐  ┌──────────┐  ┌─────────┐                 │
          │   │  pentagi  │  │ pgvector │  │ scraper │   (+ ollama     │
          │   │  (UI/API) │  │  (BD)    │  │         │    optionnel)   │
          │   └─────┬─────┘  └──────────┘  └─────────┘                 │
          │         │ crée/pilote via docker.sock                      │
          │         ▼                                                  │
          │   Réseau "pentagi-range"  (bridge, internal: true)  ⟵ ISOLÉ│
          │   ┌──────────────┐   ┌──────────────┐   ┌───────────────┐  │
          │   │ agent bac-à- │──▶│ juice-shop   │   │ dvwa          │  │
          │   │ sable PentAGI│   │ 172.30.0.10  │   │ 172.30.0.20   │  │
          │   └──────────────┘   └──────────────┘   └───────────────┘  │
          │     pas de route ──X──▶ LAN maison / Internet              │
          └──────────────────────────────────────────────────────────┘
                     ▲                                 │
          cerveau LLM │ (cloud, local, ou Ollama)      │ UI sur 127.0.0.1:8443
                      │                                 ▼  (tunnel SSH)
            API OpenAI/Anthropic/…               ton poste d'admin
```

Détails : [docs/01-architecture.md](docs/01-architecture.md).

## Démarrage rapide (hôte Docker existant)

```bash
cp .env.lab.example .env
./scripts/preflight.sh --gen-secrets      # vérifie Docker + génère les secrets
# edite .env : décommente UN cerveau LLM (section 2), p.ex. ANTHROPIC_API_KEY=...
make up                                    # ou: ./scripts/lab-up.sh
make status                                # conteneurs + test d'isolation + cibles
```

Ouvre l'UI : `https://127.0.0.1:8443` (`admin@pentagi.com` / `admin` — change-le).
Puis crée un jeton API (Settings → API Tokens) et lance une mission autonome :

```bash
export PENTAGI_API_TOKEN=....
./scripts/new-mission.sh --target juice --provider anthropic
./scripts/export-results.sh               # liste les flows et leurs résultats
```

Guide détaillé : [docs/02-installation.md](docs/02-installation.md) ·
[docs/04-lancer-une-mission.md](docs/04-lancer-une-mission.md).

## Démarrage via Ansible (VM dédiée, de zéro)

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml -p ./.collections
# adapte inventory/hosts.ini (IP + user SSH) et host_vars/pentagi-lab.yml
ansible-playbook site.yml
```

Le playbook installe Docker, pose le pare-feu nftables + l'isolation DOCKER-USER,
synchronise le projet, démarre le stack et **valide l'isolation** automatiquement.

## Cerveau LLM : lequel choisir ?

Le labo est **agnostique au modèle**. Trois branchements, du plus simple au plus
isolé — raisonnement complet dans [docs/03-choix-cerveau-llm.md](docs/03-choix-cerveau-llm.md) :

| Option | Pour qui | Isolation des données | Fiabilité appels d'outils |
|---|---|---|---|
| **A. API cloud** (défaut doc) | premier test « ça marche » | données sortent | ★★★ |
| **B. serveur local OpenAI-compatible** (llama.cpp/vLLM) | labo isolé avec GPU | aucune donnée ne sort | ★★☆ (selon modèle) |
| **C. Ollama embarqué** | 100 % hors-ligne | aucune donnée ne sort | ★★☆ |

## Arborescence

```
.
├── compose/              stack PentAGI officiel (vendu) + overlays du labo
│   ├── docker-compose.pentagi.yml     (officiel, non modifié)
│   ├── docker-compose.range.yml       (cibles + réseau isolé)
│   └── docker-compose.ollama.yml      (cerveau hors-ligne optionnel)
├── config/missions/      consignes de mission prêtes à l'emploi
├── scripts/              lab-up / down / status / logs, missions, isolation
├── ansible/              inventaire, roles (common, docker_host,
│                         firewall_isolation, pentagi, targets), site.yml
├── docs/                 documentation (01 à 08)
├── .env.lab.example      modèle de configuration
└── Makefile              raccourcis (make help)
```

## État de validation

Compose, scripts, playbook et **isolation réseau** ont été validés (y compris un
test en conditions réelles prouvant qu'un conteneur du champ de tir ne peut PAS
atteindre Internet ni un LAN privé). Détails et limites :
[docs/08-validation-tests.md](docs/08-validation-tests.md).

## Références

- PentAGI : https://github.com/vxcontrol/pentagi (licence MIT)
- OWASP Juice Shop : https://owasp.org/www-project-juice-shop/
- DVWA : https://github.com/digininja/DVWA
- Comparatif des cadres d'agents (projet) : `notes/comparatif-cadres-agents-et-cerveaux.md`
