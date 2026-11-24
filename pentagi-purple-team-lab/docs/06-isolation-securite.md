# 06 — Isolation et sécurité

PentAGI exécute des **attaques autonomes** et crée des conteneurs qui lancent de
vrais outils offensifs. Le risque n'est pas la cible (volontairement vulnérable),
c'est qu'un agent **sorte du périmètre** : scanner le LAN maison, atteindre
Internet, ou exposer un service de rappel. Ce labo pose **trois couches**.

## Couche 1 — Réseau `internal` (la garantie forte)

Le champ de tir `pentagi-range` est déclaré **`internal: true`**. Docker ne lui
attribue aucune passerelle : **aucun conteneur dessus ne peut router hors du
réseau**, ni vers le LAN, ni vers Internet. C'est imposé par Docker, pas par une
règle qu'on pourrait oublier.

Comme `DOCKER_NETWORK=pentagi-range`, les bacs à sable de PentAGI héritent de
cette isolation : ils voient les cibles, rien d'autre.

> **Test réel effectué** (voir [08](08-validation-tests.md)) : depuis un conteneur
> sur un réseau `internal` aux réglages identiques, atteindre la cible interne
> **réussit**, atteindre `1.1.1.1` (Internet) **échoue** (« Network unreachable »),
> et joindre un LAN privé simulé `192.168.1.1` **échoue**. L'isolation tient.

## Couche 2 — Chaîne DOCKER-USER (défense en profondeur)

Le réseau **cœur** (`pentagi-network`), lui, a besoin d'Internet (cerveau cloud,
pull d'images). Mais « a besoin d'Internet » ≠ « doit voir ton LAN ». Le rôle
Ansible `firewall_isolation` installe une règle qui, pour **tout** conteneur
Docker, **bloque la sortie vers les réseaux privés** par l'interface de l'hôte :

```
10.0.0.0/8   172.16.0.0/12   192.168.0.0/16   169.254.0.0/16   100.64.0.0/10
```

tout en laissant passer le reste (Internet public). C'est exactement le garde-fou
qui manquait lors de l'incident connu du labo principal (une fenêtre d'ouverture
temporaire qui, faute d'exclure les réseaux privés, laissait un scan voir le
réseau maison). Ici la règle est **permanente** et **réappliquée après chaque
redémarrage de Docker** (unité `pentagi-docker-user.service`, car Docker réécrit
ses chaînes à chaque démarrage).

Pourquoi `DOCKER-USER` et pas nftables « normal » : Docker gère lui-même le
FORWARD de ses conteneurs et contourne la politique nftables standard. La chaîne
`DOCKER-USER` est le point d'insertion officiel ; sur Debian/Ubuntu moderne,
`iptables` y écrit en réalité dans nftables.

## Couche 3 — Ports de rappel liés à la loopback

PentAGI publie, par flow, des **ports de rappel** (reverse shells) dans la fenêtre
`[DOCKER_PORTS_BASE, +2000]` (défaut `28000–29999`) sur `DOCKER_PUBLIC_IP`. Deux
pièges couverts :

- `DOCKER_PUBLIC_IP=127.0.0.1` dans `.env` : ces ports ne se lient qu'à la
  loopback de l'hôte, donc **invisibles depuis le LAN**.
- ⚠️ **Docker contourne `ufw`** et publie ses ports malgré lui. La règle
  DOCKER-USER (couche 2) ferme malgré tout cette fenêtre côté réseaux privés. Si
  un jour tu mets `DOCKER_PUBLIC_IP=0.0.0.0`, c'est cette couche qui te protège.

## Posture « air-gap » complète (optionnelle)

Les couches ci-dessus isolent **les cibles et les agents**. Le **backend** garde
Internet pour un cerveau cloud (Option A). Pour un labo **totalement hors-ligne** :

1. Utilise un cerveau **local** (Option B ou C) — aucune donnée ne sort.
2. Coupe les fonctions externes (déjà par défaut dans `.env` : `DUCKDUCKGO_ENABLED=false`,
   `SPLOITUS_ENABLED=false`, `WEB_SEARCH_INTERNAL_ENABLED=false`, `UPDATE_STRATEGY=disabled`).
3. Une fois les images tirées, tu peux restreindre aussi la sortie du réseau cœur
   au niveau du pare-feu de la VM (le labo n'a plus besoin d'Internet).

Note : `PROXY_URL` route les appels LLM/recherche **du backend**, mais **pas** les
bacs à sable, le scraper, ni Graphiti — d'où l'importance de l'isolation réseau
plutôt que du seul proxy applicatif.

## Hygiène générale

- **Hôte dédié**, séparé du labo Proxmox sensible. Si c'est une VM Proxmox, mets-la
  sur un bridge isolé, pas sur `vmbr0`.
- Change le mot de passe `admin@pentagi.com` à la première connexion.
- Secrets générés aléatoirement (`preflight.sh --gen-secrets`) ; `.env` est dans
  `.gitignore` et n'est **jamais** committé.
- UI sur loopback + tunnel SSH par défaut ; ne l'expose au LAN que vers des postes
  de confiance.
- Ne pointe **jamais** une mission ailleurs que sur le champ de tir.

## Liste de contrôle avant de lancer

- [ ] `make status` affiche `pentagi-range … internal=true`.
- [ ] (Ansible) le rôle `targets` a validé l'isolation sans erreur.
- [ ] `.env` : `DOCKER_NETWORK=pentagi-range`, `DOCKER_PUBLIC_IP=127.0.0.1`.
- [ ] Mot de passe admin changé.
- [ ] La consigne de mission borne l'agent à une seule cible.
