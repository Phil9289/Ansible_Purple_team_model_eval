# 07 — Dépannage

## Le stack ne démarre pas

- **`docker compose` introuvable / v1** : il faut Compose **v2** (`docker compose
  version`). Installe le plugin `docker-compose-plugin`.
- **Erreur réseau `pentagi-network`/`observability-network` manquant** : lance
  d'abord le fichier principal. Nos scripts le font déjà (ordre des `-f`).
- **pgvector pas `healthy`** : `make logs SVC=pgvector`. Souvent un volume Postgres
  corrompu après un arrêt brutal → `make purge` puis `make up` (⚠️ efface les données).

## Je ne peux pas lancer de mission

- **Aucun cerveau LLM** : `preflight.sh` l'avertit. Renseigne une option dans
  `.env` section 2 et redémarre (`make down && make up`).
- **`createFlow` échoue via l'API** : vérifie le jeton (`PENTAGI_API_TOKEN`), que
  le `--provider` correspond bien à ce que tu as configuré dans `.env`, et que
  l'URL de base est la bonne (`--base-url`, défaut `https://127.0.0.1:8443`).
- **Certificat auto-signé** : l'UI et l'API sont en HTTPS auto-signé. Accepte
  l'avertissement dans le navigateur ; les scripts utilisent `curl -k`.

## L'agent n'atteint pas la cible

- Vérifie l'atteignabilité : `make status` (teste `juice-shop:3000` et `dvwa:80`
  depuis l'intérieur du réseau isolé).
- Confirme `DOCKER_NETWORK=pentagi-range` dans `.env` (sinon les bacs à sable ne
  sont pas sur le bon réseau). Après changement : `make down && make up`.
- Dans la consigne, utilise le **nom** (`juice-shop`, `dvwa`) ou l'**IP**
  (`172.30.0.10`, `172.30.0.20`), pas `localhost` (localhost = le conteneur agent).

## Je veux voir une cible moi-même

Le champ de tir est `internal`, donc non exposé à l'hôte (c'est voulu). Ouvre un
tunnel temporaire via un conteneur jetable :

```bash
./scripts/range-peek.sh juice    # http://127.0.0.1:13000
./scripts/range-peek.sh dvwa     # http://127.0.0.1:13080
```
Ctrl-C ferme le tunnel ; rien n'est laissé ouvert, l'isolation n'est pas rompue.

## DVWA ne se tire pas (ghcr.io)

Sur certains réseaux restreints, le CDN de blobs de ghcr.io
(`pkg-containers.githubusercontent.com`) est bloqué. Sur une VM à Internet ouvert,
aucun souci. Sinon, bascule sur une image DVWA de Docker Hub dans `.env` :
```dotenv
DVWA_IMAGE=vulnerables/web-dvwa:latest
```
(plus ancienne, mais sur Docker Hub ; ajuste l'IP/port si besoin — elle écoute sur 80).

## nftables / isolation

- Vérifier la règle d'isolation : `sudo iptables -S DOCKER-USER` doit montrer un
  saut vers `PENTAGI-ISOLATION`, et `sudo iptables -S PENTAGI-ISOLATION` les DROP
  vers les réseaux privés.
- Réappliquer manuellement : `sudo /usr/local/sbin/pentagi-docker-user.sh`.
- Après un redémarrage de Docker, l'unité `pentagi-docker-user.service` réapplique
  tout automatiquement (`systemctl status pentagi-docker-user`).

## Performances

- Cerveau local lent : normal sur CPU. Active le GPU (voir
  `compose/docker-compose.ollama.yml`, bloc `deploy`) ou passe à l'Option A le
  temps de valider.
- Beaucoup de tokens/temps par mission : c'est l'effet de `EXECUTION_MONITOR` +
  `AGENT_PLANNING` (voulu pour les petits modèles). Tu peux les passer à `false`
  avec un gros modèle fiable si tu veux accélérer.

## Logs utiles

```bash
make logs                 # backend pentagi
make logs SVC=pgvector    # base
docker logs lab-juice-shop
docker logs lab-dvwa
```
