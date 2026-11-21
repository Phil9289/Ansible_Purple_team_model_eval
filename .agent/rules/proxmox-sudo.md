---
description: Toujours demander la confirmation de l'utilisateur avant d'exécuter une commande sudo sur le serveur Proxmox
---

# Règle d'utilisation de `sudo` sur Proxmox (`192.168.1.116`)

1. **Compte SSH dédié** : Toujours se connecter avec l'utilisateur `antigravity@192.168.1.116` et la clé `C:\Users\phil\.ssh\antigravity_pve`. Ne jamais utiliser `root` ni les clés `hermes_pve` / `phil_pve`.
2. **Confirmation obligatoire avant tout `sudo`** :
   - Avant d'exécuter **toute** commande contenant `sudo` sur le serveur Proxmox, tu DOIS d'abord présenter la commande exacte à l'utilisateur dans le chat et expliquer brièvement ce qu'elle fait.
   - Tu DOIS attendre le « oui » / la confirmation explicite de l'utilisateur dans le chat avant d'appeler `run_command` avec `sudo`.
   - Les commandes qui ne nécessitent pas `sudo` (lecture simple permise à l'utilisateur standard `antigravity`) peuvent être exécutées normalement.
