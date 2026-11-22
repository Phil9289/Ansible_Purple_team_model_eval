#!/bin/bash
# 2026-11-22 : permettre de redéployer les rôles quand le lab est isolé (pas d'Internet).
# À exécuter dans le LXC 300. Modifie seulement 3 fichiers de tâches (sauvegarde avant).
# Usage ensuite : ansible-playbook 05-agent.yml -e apt_update_cache=false
# Par défaut (sans -e), rien ne change : apt met sa liste à jour comme avant.
set -euo pipefail
cd /root/lab-ansible
BACKUP=/root/lab-ansible-avant-apt-hors-ligne.tgz
[ -e "$BACKUP" ] && { echo "ERREUR : $BACKUP existe déjà. Script déjà exécuté ?"; exit 1; }
tar czf "$BACKUP" --exclude=lab-ansible/models-cache -C /root lab-ansible
for f in roles/common/tasks/main.yml roles/agent_host/tasks/main.yml roles/web_target/tasks/main.yml; do
    if grep -q '^    update_cache: true$' "$f"; then
        sed -i 's/^    update_cache: true$/    update_cache: "{{ apt_update_cache | default(true) | bool }}"/' "$f"
        echo "modifié : $f"
    else
        echo "inchangé (déjà fait ou absent) : $f"
    fi
done
grep -rn "update_cache" roles/
for pb in site.yml 05-agent.yml; do ansible-playbook --syntax-check "$pb"; done
