# 08 — Validation et tests

Ce que j'ai vérifié en construisant le labo, comment, et les limites honnêtes de
l'environnement de test.

## Ce qui a été validé (réussi)

| Test | Méthode | Résultat |
|---|---|---|
| Fusion des fichiers compose | `docker compose -f pentagi.yml -f range.yml config` | **OK** (395 lignes générées, aucune erreur) |
| Réglages d'isolation présents | lecture du compose fusionné | `pentagi-range … internal: true`, `DOCKER_NETWORK=pentagi-range`, `DOCKER_PUBLIC_IP=127.0.0.1`, `EXECUTION_MONITOR_ENABLED=true`, `AGENT_PLANNING_STEP_ENABLED=true` |
| **Isolation réseau (test réel)** | conteneurs sur un réseau `internal` aux réglages identiques | voir ci-dessous — **l'isolation tient** |
| Syntaxe de tous les scripts | `bash -n scripts/*.sh` + script DOCKER-USER rendu | **OK** (9/9 + le template) |
| Structure du playbook Ansible | `ansible-playbook --syntax-check site.yml` | **OK** (seule une dépréciation `apt_repository`, non bloquante) |
| Template nftables | rendu Jinja2 (2 variantes) + `nft -c -f` | **OK** les deux |
| Lint YAML | `yamllint` (profil relaxed) sur `ansible/` et `compose/` | **OK** (rien de bloquant) |
| Référence d'image Juice Shop | `docker manifest inspect bkimminich/juice-shop:v19.0.0` | **OK** (joignable) |

### Détail du test d'isolation (le plus important)

Sur un réseau bridge `internal: true` au subnet `172.30.0.0/24` (identique à
`docker-compose.range.yml`), avec une « cible » servant du HTTP sur `:3000` :

1. **Agent → cible interne** (`172.30.0.10:3000`) : **RÉUSSIT** (réponse `HELLO-TARGET`).
2. **Agent → Internet** (`http://1.1.1.1/`) : **ÉCHOUE** — « Network unreachable ».
3. **Agent → LAN privé simulé** (`ping 192.168.1.1`) : **ÉCHOUE** — pas de route.

Conclusion : un conteneur du champ de tir atteint la cible mais **ne peut ni
sortir sur Internet ni voir un réseau privé**. C'est la garantie centrale du labo,
et elle est imposée par Docker lui-même (pas seulement par une règle de pare-feu).

## Ce qui n'a PAS pu être exécuté ici (limites de l'environnement)

L'environnement de construction (bac à sable cloud) a un proxy de sortie
restreint. Conséquences :

- **Pull de DVWA (ghcr.io)** bloqué : le CDN de blobs
  `pkg-containers.githubusercontent.com` n'est pas autorisé. Docker Hub, lui,
  fonctionne (Juice Shop vérifié). → Sur une VM à Internet ouvert, les deux cibles
  se tirent normalement. Alternative Docker Hub documentée dans [07](07-depannage.md).
- **Démarrage complet du stack PentAGI + mission réelle** non exécuté ici : cela
  requiert de tirer les images PentAGI (lourdes) **et** une clé LLM, hors cadre de
  ce bac à sable. La configuration est néanmoins validée statiquement (compose
  `config` + câblage des variables) et l'isolation est prouvée en conditions réelles.
- **`ansible-galaxy collection install`** bloqué ici (galaxy.ansible.com non
  autorisé par le proxy) ; la vérification de syntaxe du playbook a été faite avec
  des stubs de collections. Sur une machine à Internet normal, l'installation des
  collections et le `--check` fonctionnent sans adaptation.

## Comment reproduire la validation sur ta VM

```bash
# 1. Prérequis + secrets
cp .env.lab.example .env && ./scripts/preflight.sh --gen-secrets
#    renseigne un cerveau LLM dans .env

# 2. Démarre et valide l'isolation + l'atteignabilité
make up
make status            # doit afficher internal=true et les 2 cibles atteignables

# 3. (Ansible) la validation d'isolation est automatique via le rôle 'targets' :
cd ansible && ansible-playbook site.yml --tags validate

# 4. Mission de bout en bout (après avoir créé un jeton API dans l'UI)
export PENTAGI_API_TOKEN=...
./scripts/new-mission.sh --target juice --provider anthropic
./scripts/export-results.sh
```

## Pistes de suites (après un premier run réussi)

- **Volet bleu** : brancher un collecteur de logs / IDS (p.ex. rsyslog ou une
  petite stack Suricata) sur le champ de tir pour mesurer la détection des
  attaques de l'agent — ça complète le « purple ».
- **Banc de comparaison de cerveaux** : rejouer la même mission avec A/B/C et
  remplir la grille de [03](03-choix-cerveau-llm.md) § comparer.
- **Cibles supplémentaires** : ajouter une API vulnérable (p.ex. VAmPI) ou un
  service réseau au champ de tir — il suffit d'un service de plus dans
  `docker-compose.range.yml` sur le réseau `pentagi-range`.
