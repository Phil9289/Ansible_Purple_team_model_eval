#!/usr/bin/env python3
"""
Adapte le pare-feu RENDU du labo au noyau du conteneur de simulation.

Le noyau de la simulation n'a pas deux fonctions que le Proxmox a :
  - « meta ibrname » (nom du bridge d'entrée, module nft_meta_bridge)
  - « ct state » dans la famille bridge (module nf_conntrack_bridge)
On les remplace mécaniquement par des équivalents, et RIEN d'autre ne change :
  - meta ibrname "vmbrX"   ->  iifname { ports de vmbrX }
  - meta ibrname != "vmbrX" -> iifname != { ports de vmbrX }
  - ct state established,related (bridge) -> tcp flags & (syn | ack) != syn (réponse TCP)
Usage : adapt_nft.py lab.nft lab-sim.nft
"""
import re
import sys

PORTS = {
    "vmbr3": ["tap301i0", "tap302i0", "tap303i0", "tap304i0"],
    "vmbr4": ["tap304i1", "veth242i1"],
}

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
bridge_start = text.index("table bridge lab_l2 {")
head, bridge = text[:bridge_start], text[bridge_start:]


def ports(br):
    return "{ " + ", ".join(PORTS[br]) + " }"


bridge = re.sub(r'meta ibrname != "(vmbr\d)"', lambda m: f"iifname != {ports(m.group(1))}", bridge)
bridge = re.sub(r'meta ibrname "(vmbr\d)"', lambda m: f"iifname {ports(m.group(1))}", bridge)
bridge = bridge.replace("ct state established,related accept", "tcp flags & (syn | ack) != syn accept")
open(dst, "w", encoding="utf-8").write(head + bridge)
print(f"{dst} : {len(re.findall('iifname', bridge))} règles bridge adaptées au noyau de simulation")
