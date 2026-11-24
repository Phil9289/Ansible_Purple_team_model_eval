# 04 — Lancer une mission autonome

Une « mission » = un **flow** PentAGI : tu décris la cible et l'objectif en
langage naturel, PentAGI planifie et exécute en autonomie contre le champ de tir.

## Deux façons : l'UI ou l'API

### Via l'interface web (le plus simple)

1. Connecte-toi (`https://localhost:8443` via le tunnel SSH).
2. **Flows → New Flow**.
3. **Mode** : choisis **Automation** (exécution autonome de bout en bout).
   *Assistant* sert à piloter pas à pas si tu veux garder la main.
4. **Provider LLM** : celui que tu as configuré (`anthropic`, `openai`, `custom`,
   `ollama`…). Voir [03](03-choix-cerveau-llm.md).
5. **Message** : colle une consigne. Exemples prêts :
   - `config/missions/web_juice_shop.md` (Juice Shop)
   - `config/missions/dvwa_sqli.md` (DVWA)

   Une bonne consigne contient : la **cible** (ici `http://juice-shop:3000` ou
   `http://dvwa:80`), le **type d'évaluation**, les **règles d'engagement**
   (reste sur la cible !), et le **livrable** attendu (rapport de failles).
6. Envoie : PentAGI ouvre la page du flow et tu suis l'activité des agents.

> Les cibles sont joignables par **nom** (`juice-shop`, `dvwa`) ou par **IP**
> (`172.30.0.10`, `172.30.0.20`) *depuis les agents*, car ils sont sur le réseau
> isolé. Depuis ton navigateur, elles ne sont pas exposées (c'est voulu) ; pour y
> jeter un oeil, voir `scripts/range-peek.sh` ([07](07-depannage.md)).

### Via l'API (scriptable, reproductible)

1. Crée un jeton : **Settings → API Tokens → Create Token**, copie-le.
2. Lance :

```bash
export PENTAGI_API_TOKEN=<ton-jeton>
# cible prédéfinie :
./scripts/new-mission.sh --target juice --provider anthropic
# ou ta propre consigne :
./scripts/new-mission.sh --prompt-file config/missions/dvwa_sqli.md --provider ollama
```

Le script poste une mutation GraphQL `createFlow(modelProvider, input)` et affiche
l'`id` du flow créé. (`make mission-juice` / `make mission-dvwa` font pareil.)

## Règles d'engagement (important)

Les consignes fournies **bornent explicitement** l'agent à une seule cible. Garde
toujours cette contrainte : un agent offensif autonome fait exactement ce qu'on
lui dit, et parfois au-delà si le périmètre est flou. L'isolation réseau
([06](06-isolation-securite.md)) est le garde-fou technique ; la consigne est le
garde-fou d'intention. Les deux comptent.

## Bonnes premières missions

- **Juice Shop** : « reconnaissance + OWASP Top 10, confirme chaque faille avec
  une preuve reproductible ». Riche en vulnérabilités web variées.
- **DVWA (niveau low)** : « authentifie-toi admin/password, démontre une injection
  SQL puis une injection de commande ». Idéal pour un succès net et pédagogique.

Commence **étroit** (une cible, un objectif clair) : la sortie est plus lisible et
tu affines tes consignes avant de viser plus large.
