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

Les identifiants Proxmox (jeton API) sont chiffrés avec Ansible Vault dans `group_vars/all/vault.yml` ; seul le fichier chiffré est versionné, jamais le mot de passe du vault.

## Contenu du dépôt

- `lab-ansible/` : le code Ansible du contrôleur (`site.yml`, playbooks `01` à `05`, `90-destroy`, `99-verify`, 6 rôles, inventaire, `group_vars`). `vault.yml` est chiffré (AES-256) ; le mot de passe (`~/.vault_pass`) et le modèle GGUF ne sont pas dans le dépôt.
- `PROJECT-BLUEPRINT-PURPLE-TEAM-LLM-LAB.md` : blueprint et architecture cible.
- `LIGNE-DU-TEMPS-ET-JOURNAL.md` : journal de construction du labo.
- `TRAME-VIDEO-DEMO.md` : trame de la vidéo de démonstration.
- `GUIDE-PROJET-AI-DEFENSE-RAG-MCP.md` : prochain chantier (défense IA : RAG, MCP, AI Firewall, SIEM).
- `Rapport-Projet-Ansible-Proxmox-LEA84.docx` : rapport de remise.
- `scripts/` : scripts de déploiement par phase (playbooks et rôles générés sur le contrôleur) et générateur du rapport.
- `specs/001-ansible-proxmox-llm-lab/` : spécification, plan et tâches (Spec Kit).
- `.specify/`, `.agents/`, `.agent/` : configuration Spec Kit et règles de l'agent.

## Utilisation

```bash
cd lab-ansible
echo 'mot-de-passe-du-vault' > ~/.vault_pass && chmod 600 ~/.vault_pass
ansible-playbook site.yml      # déploie tout (le modèle est téléchargé par 05-agent.yml)
ansible-playbook 99-verify.yml # vérifie l'isolation réseau
```
