# Profils de cerveau LLM (`profils/`)

Un **profil** décrit *quel cerveau* l'agent utilise et *comment le joindre*.
Les playbooks disent *quoi* installer (quel moteur d'agent) ; les profils disent
*comment* le configurer. On combine les deux au lancement :

```bash
# Hermes avec OpenRouter (cerveau distant, clé sur la passerelle)
ansible-playbook agent-hermes.yml -e @profils/openrouter-offense.yml

# Hermes avec le modèle local (llama.cpp + P100, aucune clé, mode isolé)
ansible-playbook agent-hermes.yml -e @profils/local.yml

# PentAGI avec un GPU loué
ansible-playbook agent-pentagi.yml -e @profils/gpu-loue.yml
```

## Idée de sécurité

L'agent **ne reçoit jamais de clé API**. Il parle à la passerelle LiteLLM
(`llm_gateway_url`), qui est la seule à détenir les clés et la seule autorisée à
sortir vers Internet. Un moteur d'agent non fiable, même s'il s'échappe, ne
trouve aucune clé dans sa VM.

| Profil | Cerveau | Clé requise | Sortie Internet |
|---|---|---|---|
| `local` | llama.cpp dans la VM agent (P100) | aucune | aucune |
| `openrouter-offense` | OpenRouter via la passerelle | `vault_openrouter_api_key` | passerelle → openrouter.ai |
| `gpu-loue` | vLLM sur un GPU loué, via la passerelle | `vault_gpu_rental_api_key` | passerelle → fournisseur GPU |

## Variables d'un profil

- `llm_profile` : nom du profil (sert aux messages et aux assertions).
- `llm_route` : clé de routage lue par la passerelle (voir `roles/litellm_gateway`).
- `hermes_agent_model` / `agent_model` : nom du modèle présenté à l'agent.
- `agent_context` : taille de contexte annoncée (Hermes exige ≥ 64000).
- `llm_egress` : `none` | `openrouter` | `gpu` — ce que le pare-feu ouvre pour la passerelle.

Les clés elles-mêmes ne sont **jamais** dans ces fichiers : elles vivent dans
`inventory/group_vars/all/vault.yml` (chiffré), ajoutées avec
`ansible-vault edit inventory/group_vars/all/vault.yml`.
