# 05 — Lire et interpréter les résultats

## Dans l'interface web

Sur la page d'un flow :

- **Vue principale** : le fil des messages, l'activité des agents, la progression
  des tâches/sous-tâches. Tu vois en direct ce que l'agent décide et pourquoi.
- **Sortie des outils / terminal** : la sortie brute des commandes exécutées dans
  le bac-à-sable (nmap, sqlmap…). C'est la **preuve** de ce qui a réellement tourné.
- **Tâches & sous-tâches** : l'arbre de planification. Utile pour juger si l'agent
  a bien découpé le problème ou s'il a tourné en rond.
- **Menu Report** : ouvre le rapport formaté, le copie, ou le télécharge en
  **Markdown** / **PDF**. C'est le livrable à conserver.
- **Onglet Files** : fichiers propres au flow (uploads, ressources, extractions
  depuis le conteneur). Stockés sous `{dataDir}/flow-{id}-data/` sur l'hôte.

## Via l'API

```bash
export PENTAGI_API_TOKEN=<ton-jeton>
./scripts/export-results.sh                 # liste tous les flows (id, titre, statut)
./scripts/export-results.sh <flow_id>       # détail + tâches, sauvé dans results/
```

Le détail complet est écrit dans `results/flow-<id>-<horodatage>.json`. Le rapport
formaté (Markdown/PDF), lui, se télécharge depuis le menu Report de l'UI.

## Comment juger une mission

Au-delà de « a-t-il trouvé une faille ? », regarde :

| Critère | Où | Ce que ça dit |
|---|---|---|
| **Appels d'outils valides** | vue terminal / tâches | fiabilité du cerveau (JSON correct, pas d'erreurs d'outil) |
| **Mission réussie + nb d'étapes** | tâches + rapport | efficacité (peu d'étapes = mieux) |
| **Hallucinations** | compare sortie d'outil vs. affirmations de l'agent | l'agent invente-t-il des résultats ? |
| **Reproductibilité** | rapport : requête + réponse | une faille sans preuve reproductible ne compte pas |
| **Respect du périmètre** | fil des messages | est-il resté sur la seule cible autorisée ? |
| **Temps / tokens** | durée du flow / facturation | coût réel de la mission |

## Côté « Purple » (bleu)

PentAGI est **offensif seulement** (pas d'agent défenseur). Pour la partie bleue,
tu peux exploiter les traces produites :

- les cibles et les bacs à sable laissent des **logs** (`docker logs lab-juice-shop`,
  `docker logs lab-dvwa`) : sers-t'en comme source pour une analyse de détection ;
- compare : les actions de l'agent (dans le rapport) **ont-elles laissé des traces
  détectables** côté cible ? C'est la base d'un exercice purple team — l'attaque
  est autonome, la détection se discute ensuite.
- pour aller plus loin (SIEM/IDS dans le labo), voir les pistes en
  [08](08-validation-tests.md) § suites.

## Nettoyage des données de flow

Supprimer un flow dans l'UI retire son enregistrement et sa mémoire long-terme,
mais **pas** forcément son dossier `flow-{id}-data/` sur disque. Pour récupérer
l'espace, nettoie ce dossier à la main, ou `make purge` pour tout remettre à zéro.
