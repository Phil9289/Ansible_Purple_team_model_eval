# Laboratoire Purple Team & évaluation d'agents LLM (Proxmox VE + Ansible)

Projet du cours LEA.84 : un labo isolé sur Proxmox VE 9.2, provisionné entièrement avec Ansible, pour tester un agent LLM offensif local contre une cible, avec journalisation centralisée.

## Architecture

| Composant | Rôle | Adresse |
|---|---|---|
| LXC 300 | Contrôleur Ansible (`/root/lab-ansible`) | — |
| `vmbr3` | Bridge isolé, filtré par nftables | `10.30.0.0/24` |
| VM `agent` | Qwen 2.5 7B (llama.cpp, CPU) + outils offensifs | `10.30.0.10` |
| VM `target` | Nginx (cible) | `10.30.0.20` |
| VM `logging` | Serveur rsyslog central | `10.30.0.30` |

Les identifiants Proxmox (jeton API) sont chiffrés avec Ansible Vault dans `group_vars/all/vault.yml` et ne sont pas dans ce dépôt.

## Contenu du dépôt

- `PROJECT-BLUEPRINT-PURPLE-TEAM-LLM-LAB.md` : blueprint et architecture cible.
- `LIGNE-DU-TEMPS-ET-JOURNAL.md` : journal de construction du labo.
- `TRAME-VIDEO-DEMO.md` : trame de la vidéo de démonstration.
- `GUIDE-PROJET-AI-DEFENSE-RAG-MCP.md` : prochain chantier (défense IA : RAG, MCP, AI Firewall, SIEM).
- `Rapport-Projet-Ansible-Proxmox-LEA84.docx` : rapport de remise.
- `scripts/` : scripts de déploiement par phase (playbooks et rôles générés sur le contrôleur) et générateur du rapport.
- `specs/001-ansible-proxmox-llm-lab/` : spécification, plan et tâches (Spec Kit).
- `.specify/`, `.agents/`, `.agent/` : configuration Spec Kit et règles de l'agent.
