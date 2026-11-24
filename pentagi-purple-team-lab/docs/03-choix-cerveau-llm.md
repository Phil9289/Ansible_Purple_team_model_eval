# 03 — Choix du cerveau LLM (et pourquoi)

Un agent = **cadre** (PentAGI : la boucle, les outils, les approbations) +
**cerveau** (le modèle LLM). PentAGI accepte n'importe quel modèle derrière une
API compatible OpenAI, Ollama, ou ses fournisseurs natifs. Ce qui compte pour le
cerveau d'un agent offensif, c'est surtout sa **fiabilité en appels d'outils**
(produire du JSON d'outil correct, ne pas boucler), son **contexte**, et ses
**connaissances** en sécurité.

## Décision pour ce labo

Le labo est livré **agnostique au modèle**. On **ne présume pas** Strata (le MoE
125B perso) comme moteur : sa disponibilité n'est pas garantie et une autre
personne l'utilise déjà. On documente plutôt trois branchements et on recommande
un **défaut réaliste** selon l'objectif.

> **Recommandation par défaut : Option A (API cloud), modèle à fort support
> d'appels d'outils (p.ex. un Claude récent ou un GPT récent).**
> Raison : pour *valider que le labo fonctionne de bout en bout*, la variable la
> plus risquée est la fiabilité des appels d'outils du cerveau. Un modèle cloud
> de premier plan l'élimine, on voit tout de suite si l'infra PentAGI + cibles +
> isolation marche. On bascule ensuite vers un cerveau local (B/C) pour la
> posture isolée, une fois le labo prouvé.

C'est un choix **opérationnel**, pas idéologique : les cibles restent isolées
dans tous les cas ; seule l'Option A laisse sortir les *données de mission*.

## Option A — API cloud (défaut documenté)

```dotenv
# dans .env (décommente UNE ligne)
ANTHROPIC_API_KEY=sk-ant-...
# ou
OPEN_AI_KEY=sk-...
```
Au lancement d'un flow, choisis le provider correspondant (`anthropic`, `openai`).

- ✅ Meilleure fiabilité d'appels d'outils → le meilleur « premier test ».
- ✅ Rien à héberger.
- ⚠️ Les sorties d'outils et le raisonnement **sortent** vers le fournisseur.
  Acceptable ici : cibles factices, volontairement vulnérables. À proscrire si
  la mission manipule des données réelles sensibles.
- 💲 Coût au token.

## Option B — Serveur local compatible OpenAI (llama.cpp / vLLM)

Pour un labo **réellement isolé** avec GPU. Tu héberges un modèle derrière une API
OpenAI et tu pointes PentAGI dessus :

```dotenv
LLM_SERVER_URL=http://host.docker.internal:8000/v1   # ton llama.cpp/vLLM
LLM_SERVER_KEY=sk-no-key-needed
LLM_SERVER_MODEL=qwen2.5-coder-32b-instruct
LLM_SERVER_API_TYPE=openai
```
Provider à sélectionner au lancement : `custom` (ou `llm`).

- ✅ Aucune donnée ne sort.
- ✅ C'est ici que **Strata ou tout autre gros modèle local** se branche, *si*
  tu en disposes : expose-le via une passerelle OpenAI-compatible et mets son URL.
- ⚠️ `LLM_SERVER_*` est **expérimental** côté PentAGI (un seul modèle pour tous
  les agents). Fiabilité d'appels d'outils variable selon le modèle.

## Option C — Ollama embarqué (100 % hors-ligne)

```bash
make up-ollama
```
```dotenv
OLLAMA_SERVER_URL=http://ollama:11434
OLLAMA_SERVER_MODEL=qwen2.5-coder:7b
OLLAMA_SERVER_PULL_MODELS_ENABLED=true
```
Provider à sélectionner : `ollama`.

- ✅ Totalement local et gratuit.
- ⚠️ Sans GPU, c'est lent. Avec GPU, décommente le bloc `deploy` dans
  `compose/docker-compose.ollama.yml` (nécessite `nvidia-container-toolkit`).

## Petits modèles (<32B) : réglages essentiels

PentAGI le dit clairement (tests sur Qwen3.5-27B) : pour un modèle local <32B,
**active la supervision**, sinon l'agent boucle et explore mal. C'est déjà le
défaut du labo (`.env`) :

```dotenv
EXECUTION_MONITOR_ENABLED=true      # x2 de qualité, évite les boucles infinies
AGENT_PLANNING_STEP_ENABLED=true    # planification des étapes
```
Contrepartie : 2–3× plus de tokens et de temps. Sans effet néfaste sur un gros
modèle, donc laissé activé partout.

## Tableau de décision

| Ton objectif | Option | Provider PentAGI |
|---|---|---|
| Prouver que le labo marche, vite et fiable | **A** cloud | `anthropic` / `openai` |
| Labo isolé, gros modèle local dispo (dont Strata) | **B** local | `custom` |
| 100 % hors-ligne, pas d'API | **C** Ollama | `ollama` |
| Comparer des cerveaux sur la même mission | A/B/C | (relance la même mission, change le provider) |

## Si tu veux comparer des modèles

Lance **la même mission** (`config/missions/web_juice_shop.md`) 3–5 fois par
cerveau et compare : taux d'appels d'outils valides, mission réussie ou non,
nombre d'étapes, hallucinations, temps et tokens. Ne juge pas un modèle par
lui-même (il se noterait complaisamment) : garde une grille fixe ou un juge
distinct. (Même méthode que le comparatif du projet,
`notes/comparatif-cadres-agents-et-cerveaux.md`.)
