# 01 — Architecture

## Vue d'ensemble

Le labo tient sur **un seul hôte Docker** (une VM Debian/Ubuntu dédiée, distincte
du labo Proxmox sensible). Tout est conteneurisé. Deux réseaux Docker séparent
clairement les rôles.

### Réseau `pentagi-network` (cœur, avec Internet)

C'est le réseau du stack officiel PentAGI. Ses services ont besoin de sortir
(tirer les images, joindre le cerveau LLM cloud, mises à jour) :

| Service | Rôle | Port |
|---|---|---|
| `pentagi` | backend Go : UI web, API GraphQL+REST, orchestration multi-agent | 8443 (HTTPS) |
| `pgvector` | PostgreSQL + pgvector : mémoire vectorielle, état des flows | 5432 (interne) |
| `scraper` | navigateur isolé pour la lecture web de l'agent | interne |
| `pgexporter` | métriques Postgres (Prometheus) | interne |
| `ollama` *(optionnel)* | cerveau LLM local hors-ligne | interne |

Par défaut, **seul 127.0.0.1 de l'hôte** est lié aux ports publiés (accès par
tunnel SSH). Voir [02-installation](02-installation.md).

### Réseau `pentagi-range` (champ de tir, ISOLÉ)

Déclaré avec **`internal: true`** : Docker ne lui pose aucune passerelle, donc
**aucun conteneur dessus ne peut router vers le LAN de l'hôte ni vers Internet.**
C'est la garantie d'isolation centrale, imposée par Docker lui-même.

| Cible | Image | IP interne | Port |
|---|---|---|---|
| OWASP Juice Shop | `bkimminich/juice-shop` | 172.30.0.10 | 3000 |
| DVWA | `ghcr.io/digininja/dvwa` | 172.30.0.20 | 80 |

## Comment PentAGI atteint les cibles

PentAGI est **multi-agent** : un orchestrateur délègue à des agents spécialisés
(chercheur, développeur, « pentester », etc.). Pour exécuter des commandes, le
backend crée des **conteneurs bac-à-sable** éphémères via `docker.sock`, outillés
(nmap, sqlmap, nikto…).

La variable **`DOCKER_NETWORK=pentagi-range`** (dans `.env`) dit à PentAGI
d'attacher ces bacs à sable au réseau isolé. Conséquence :

- l'agent **voit** `juice-shop` et `dvwa` (par nom ou par IP) ;
- l'agent **ne voit pas** ton réseau maison : pas de route, point.

Le backend, lui, ne parle pas aux bacs à sable par le réseau mais par
`docker exec` (via le socket), donc il n'a pas besoin d'être sur le réseau isolé.

## Flux d'une mission

```
Toi ──(UI ou API GraphQL)──▶ pentagi (orchestrateur)
                               │  planifie, puis pour chaque étape :
                               ├─▶ cerveau LLM (cloud/local) : "quelle commande ?"
                               └─▶ crée un bac-à-sable sur pentagi-range
                                      └─▶ exécute l'outil CONTRE la cible isolée
                                      ◀─ renvoie la sortie
                               │  boucle (ReAct), résume, consigne en base
                               ▼
                            Rapport (UI : menu Report / API)
```

## Le cerveau LLM

Branchement au choix via `.env`, sans toucher au reste :

- **A — cloud** : `OPEN_AI_KEY` ou `ANTHROPIC_API_KEY`. Le backend (réseau cœur,
  avec Internet) appelle l'API. Les cibles restent isolées ; seules les
  **données de mission** (sorties d'outils, raisonnement) transitent vers le
  fournisseur.
- **B — serveur local OpenAI-compatible** : `LLM_SERVER_URL` pointant vers un
  llama.cpp/vLLM (sur l'hôte ou une autre machine). Aucune donnée ne sort.
- **C — Ollama embarqué** : service `ollama` ajouté au réseau cœur.

Détails et recommandation : [03-choix-cerveau-llm](03-choix-cerveau-llm.md).

## Pourquoi deux chemins d'installation

- **Scripts `make` / `scripts/`** : rapides sur un hôte Docker déjà prêt.
- **Ansible (`ansible/`)** : provisionne une VM **de zéro** (Docker, pare-feu,
  isolation, stack, validation) de façon reproductible — l'approche « infra as
  code » du labo principal. Les deux chemins produisent exactement le même
  résultat (même réseau `pentagi-range`, mêmes IP de cibles).
