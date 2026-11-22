# Commandes à se rappeler pour Proxmox

## Redonner la Tesla P100 aux conteneurs après la VM agent (301)

La P100 (`0000:04:00.0`, ID `10de:15f8`, `/dev/nvidia0`) est partagée **à tour de rôle** :

- **VM agent 301** (passthrough par le mapping `p100`) : au démarrage de la VM, Proxmox retire lui-même la carte au pilote `nvidia` et la donne à `vfio-pci`. Il faut d'abord éteindre les conteneurs qui l'utilisent (240, 242, 245).
- **Conteneurs 240, 242, 245** : ils utilisent `/dev/nvidia0` et `/dev/nvidia1`. Quand la VM 301 s'arrête, la carte reste sur `vfio-pci`. Il faut la redonner au pilote `nvidia`, **sans redémarrer le Proxmox**.

### Commande courte (sur le Proxmox, en root)

```
p100-retour-conteneurs
```

### Création de la commande (une seule fois)

```
cat > /usr/local/sbin/p100-retour-conteneurs << 'EOS'
#!/bin/sh
# Redonne la Tesla P100 (04:00.0) au pilote nvidia après la VM agent 301.
if qm status 301 | grep -q running; then echo "Éteins d'abord la VM 301 : qm shutdown 301"; exit 1; fi
[ -e /sys/bus/pci/drivers/vfio-pci/0000:04:00.0 ] && echo 0000:04:00.0 > /sys/bus/pci/drivers/vfio-pci/unbind
[ -e /sys/bus/pci/drivers/nvidia/0000:04:00.0 ] || echo 0000:04:00.0 > /sys/bus/pci/drivers/nvidia/bind
nvidia-smi -L
EOS
chmod +x /usr/local/sbin/p100-retour-conteneurs
```

### Les deux commandes de base (si le script n'existe pas)

```
echo 0000:04:00.0 > /sys/bus/pci/drivers/vfio-pci/unbind
echo 0000:04:00.0 > /sys/bus/pci/drivers/nvidia/bind
nvidia-smi -L
```

### Vérifications utiles

| Question | Commande | Résultat attendu |
|---|---|---|
| Quel pilote tient la P100 ? | `lspci -nnk -s 04:00.0 \| grep -i driver` | `nvidia` (conteneurs) ou `vfio-pci` (VM 301) |
| La P100 est-elle utilisée ? | `nvidia-smi --query-compute-apps=pid,process_name,gpu_bus_id --format=csv` | aucune ligne sur `04:00.0` avant de démarrer la VM 301 |
| Le mapping existe-t-il ? | `pvesh get /cluster/mapping/pci` | une entrée `p100` |

**À ne pas faire :** réserver la P100 en permanence à `vfio-pci` (`driverctl`, `options vfio-pci ids=...`). Les conteneurs 240, 242 et 245 perdraient la carte.
