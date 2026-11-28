# Fork v2 — offensive, passerelle LLM, profils (branche `dev`)

Ce fork ajoute, **sans toucher à la version déposée (`main`)**, de quoi tester
différents cerveaux LLM et différents moteurs d'agent sur le labo isolé.

## L'idée en une phrase

L'agent ne parle qu'à **une passerelle** (LiteLLM, VM 310). La passerelle détient
les clés et choisit le cerveau selon le **profil**. Un moteur d'agent non fiable
ne trouve aucune clé dans sa VM, et ne voit jamais Internet.

## Ce qui est nouveau

| Élément | Fichier |
|---|---|
| Profils de cerveau | `profils/local.yml`, `profils/openrouter-offense.yml`, `profils/gpu-loue.yml` |
| Passerelle LiteLLM | `roles/litellm_gateway/`, playbook `07-gateway.yml`, VM `gateway` 10.30.0.50 |
| GPU loué + autodestruction | `roles/gpu_rental/`, `90-destroy-gpu.yml`, minuteur systemd 1 h |
| Playbooks par agent | `agent-hermes.yml` (manuel), `agent-hermes-autonome.yml` (smart) |
| Sortie réseau de la passerelle | règles ajoutées dans `nftables.conf.j2` (gated) |

## Avant de lancer (3 choses à faire, elles touchent Proxmox → ton accord)

1. **Ajouter les clés au vault** (sur le LXC 300) :
   ```bash
   ansible-vault edit inventory/group_vars/all/vault.yml
   # ajouter :
   #   vault_openrouter_api_key: "sk-or-..."
   #   vault_gpu_rental_api_key: "..."   # seulement pour le profil gpu-loue
   ```
2. **Créer la VM passerelle** : `01-infra.yml` clone maintenant 4 VM (la gateway
   310 en plus). Comme toute commande Proxmox, à lancer par toi.
3. **Choisir le fournisseur de GPU** (runpod / vastai / modal) : les appels d'API
   dans `roles/gpu_rental/tasks/` sont des `TODO` à compléter une fois choisi.

## Lancer des tests

```bash
# 1) Infra (crée les VM, dont la passerelle)
ansible-playbook 01-infra.yml

# 2) Cibles + journaux (comme d'habitude)
ansible-playbook 04-target.yml 03-logging.yml

# 3) Agent Hermes avec OpenRouter (cerveau distant, clé sur la passerelle)
ansible-playbook agent-hermes.yml -e @profils/openrouter-offense.yml

# Variante plus autonome, mêmes cerveaux :
ansible-playbook agent-hermes-autonome.yml -e @profils/openrouter-offense.yml

# Retour au tout-local (version déposée, aucune clé, aucun Internet) :
ansible-playbook agent-hermes.yml -e @profils/local.yml

# GPU loué (facturé : refuse de louer sans confirmation explicite) :
ansible-playbook agent-hermes.yml -e @profils/gpu-loue.yml -e gpu_rental_confirmed=true
```

## Le mélange de modèles (profil openrouter-offense)

| Rôle | Alias passerelle | Modèle | Prix /M (in/out) |
|---|---|---|---|
| Exécutant (le + de tokens) | `offense-main` | DeepSeek V4 Flash | 0,05 / 0,20 $ |
| Planificateur | `offense-planner` | DeepSeek V4 Pro | 1,32 / 3,96 $ |
| Codeur | `offense-coder` | Kimi K2.6 | 0,65 / 3,41 $ |
| Juge | `offense-judge` | GLM 5.2 | 0,62 / 2,42 $ |

Coût estimé ≈ 1-2 $/mission. Prix à revérifier sur openrouter.ai avant de figer.

## Lien avec le LLM Downloader (CT 241)

Pas encore branché (demande Proxmox). Piste : partage **virtiofs en lecture
seule** de `/mnt/llm-models` vers la VM agent, et un catalogue `llm_models` choisi
par variable, pour le profil `local`. À faire quand tu veux, séparément.

## Sécurité : ce qui tient, ce qui reste à valider

- ✅ La clé n'est **jamais** dans la VM agent (seulement sur la passerelle).
- ✅ Seule la passerelle sort vers Internet (TCP 443 + DNS), réseaux privés
  rejetés d'abord. Vérifié par rendu du pare-feu dans les 3 modes.
- ✅ Le GPU loué s'autodétruit (minuteur systemd) même PC éteint.
- ⚠️ À tester sur le vrai Proxmox : rien de ce fork n'a tourné sur l'infra.
- ⚠️ Le prompt de cadrage « pentest autorisé » et le mélange de modèles sont des
  points de départ, à ajuster selon tes premiers résultats.

> Remplace la PR #9 (profils dans la VM agent) : ici la clé est sur la passerelle,
> approche plus sûre pour tester des moteurs non fiables.
