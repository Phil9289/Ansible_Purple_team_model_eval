# -*- coding: utf-8 -*-
"""
Générateur du rapport Word officiel (.docx) pour le cours d'Auto-initiation à Ansible
(AEC LEA.84 - Cégep de Sherbrooke).
Concis, structuré, professionnel et couvrant 100% de la grille d'évaluation.
"""
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

def set_cell_background(cell, hex_color):
    tcPr = cell._element.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), hex_color)
    tcPr.append(shd)

def create_report(output_path):
    doc = docx.Document()

    # Définir les marges (normales 2.5 cm = 1 inch)
    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.8)
        section.right_margin = Inches(0.8)

    # Couleurs du thème
    PRIMARY = RGBColor(24, 76, 120)    # Bleu marine académique
    SECONDARY = RGBColor(40, 116, 166) # Bleu intermédiaire
    DARK = RGBColor(33, 33, 33)        # Texte foncé
    GRAY = RGBColor(100, 100, 100)     # Gris annotations
    CODE_BG = "F4F6F7"
    HEADER_BG = "1B4F72"

    # Style par défaut
    style_normal = doc.styles['Normal']
    style_normal.font.name = 'Calibri'
    style_normal.font.size = Pt(10.5)
    style_normal.font.color.rgb = DARK

    # ==================== PAGE DE TITRE / EN-TÊTE ====================
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(10)
    title_p.paragraph_format.space_after = Pt(4)
    run_sub = title_p.add_run("CÉGEP DE SHERBROOKE — DÉPARTEMENT D'INFORMATIQUE\nPROGRAMME AEC LEA.84 — INFRASTRUCTURE, SÉCURITÉ ET AUTOMATISATION LINUX")
    run_sub.font.size = Pt(9.5)
    run_sub.font.bold = True
    run_sub.font.color.rgb = GRAY

    h1_p = doc.add_paragraph()
    h1_p.paragraph_format.space_before = Pt(12)
    h1_p.paragraph_format.space_after = Pt(6)
    run_title = h1_p.add_run("Rapport de Projet : Auto-Initiation à Ansible\nLaboratoire Purple Team & Isolation LLM sur Proxmox VE")
    run_title.font.size = Pt(20)
    run_title.font.bold = True
    run_title.font.color.rgb = PRIMARY

    meta_p = doc.add_paragraph()
    meta_p.paragraph_format.space_after = Pt(16)
    meta_run = meta_p.add_run("Auteur : Étudiant LEA.84 | Date : 19 Novembre 2026 | Dépôt : LEA / GitHub\nVidéo de démonstration (10 min) : ")
    meta_run.font.size = Pt(10)
    meta_run.font.italic = True
    link_run = meta_p.add_run("Lien YouTube (Privé / Non répertorié — Voir TRAME-VIDEO-DEMO.md)")
    link_run.font.size = Pt(10)
    link_run.font.bold = True
    link_run.font.color.rgb = SECONDARY

    # Ligne de séparation
    doc.add_paragraph().paragraph_format.space_after = Pt(2)

    # ==================== 1. INTRODUCTION & OBJECTIFS ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("1. Contexte, Problématique et Objectifs")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph(
        "Ce projet s'inscrit dans le cadre de l'évaluation finale du cours d'Auto-initiation à Ansible. "
        "Plutôt que d'utiliser des émulateurs réseau conventionnels comme GNS3, ce projet déploie une infrastructure "
        "as Code (IaC) réelle à domicile sur un hyperviseur Proxmox VE 9.2 (Bi-Xeon E5-2620, 128 Go RAM). "
        "L'objectif est double : valider l'ensemble des compétences de la grille académique tout en bâtissant un véritable "
        "banc d'essai de cybersécurité Purple Team. Un nœud de contrôle Ansible (LXC 300) y orchestre trois machines "
        "virtuelles jetables sur un bridge strictement isolé (vmbr3), fait exécuter un agent d'attaque autonome assisté "
        "par un modèle LLM local (Qwen 2.5 7B Instruct sur llama-server) contre une cible vulnérable, capture les journaux "
        "d'audit sur un serveur centralisé rsyslog, et prouve l'étanchéité absolue du réseau grâce à des règles nftables sur mesure."
    )

    # ==================== 2. CONCEPTS FONDAMENTAUX D'ANSIBLE ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("2. Présentation des Concepts Fondamentaux d'Ansible (20 % de la grille)")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    concepts = [
        ("Architecture sans agent (Agentless)", "Ansible ne nécessite aucun démon client installé sur les machines cibles. La communication s'effectue via le protocole standard SSH et Python, réduisant la surface d'attaque et la surcharge système."),
        ("Nœud de contrôle vs Nœuds gérés", "Le nœud de contrôle (LXC 300 sous Debian 13) héberge les playbooks, l'inventaire et les rôles. Les nœuds gérés (pve, agent, target, logging) reçoivent les modules exécutés par le contrôleur."),
        ("Idempotence stricte", "Propriété fondamentale garantissant qu'exécuter un playbook une ou plusieurs fois produit exactement le même état système sans effets secondaires. Tout run subséquent sans modification doit afficher 'changed=0'."),
        ("Inventaire structuré & Groupes", "Fichier inventory/hosts.yml organisant les machines par rôles fonctionnels (proxmox_host, attacker, web, logs, lab), permettant de cibler des ensembles cohérents de serveurs."),
        ("Précédence des variables", "Gestion modulaire où group_vars/all/vars.yml définit les paramètres généraux du lab, surchargés au besoin par host_vars/<hôte>.yml pour les spécificités matérielles (vCPU, RAM, VMID)."),
        ("Ansible Vault", "Mécanisme de chiffrement symétrique (AES-256) protégeant les secrets (jeton API Proxmox, mots de passe) dans group_vars/all/vault.yml, empêchant toute fuite de secret dans les dépôts de code."),
        ("Rôles & Modularité", "Organisation en composants réutilisables selon la convention Ansible (tasks, handlers, templates, defaults), évitant la duplication de code entre les playbooks."),
        ("Handlers & Déclencheurs", "Tâches conditionnelles exécutées en fin de play uniquement lorsqu'une tâche précédente a signalé un changement ('changed=true'), idéales pour redémarrer un service après modification de configuration."),
        ("Templates Jinja2", "Fichiers de configuration dynamiques (.j2) injectant les variables d'inventaire (adresses IP, ports, utilisateurs) de façon sécuritaire lors du déploiement.")
    ]

    for title, desc in concepts:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(3)
        run_bullet = p.add_run(f"• {title} : ")
        run_bullet.bold = True
        run_bullet.font.color.rgb = SECONDARY
        p.add_run(desc)

    # ==================== 3. ARCHITECTURE DU LABORATOIRE ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("3. Architecture Technique & Topologie Réseau")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph(
        "Le laboratoire repose sur un pont Linux virtuel dédié vmbr3 (10.30.0.0/24) configuré avec 'bridge-ports none', "
        "garantissant une déconnexion physique totale des interfaces du réseau local (vmbr0) et des autres VMs existantes. "
        "Le filtrage s'exécute à deux niveaux : en couche 3/4 via nftables sur l'hôte (table inet lab_filter), et en couche 2 "
        "sur le bridge (table bridge lab_l2) pour empêcher l'usurpation d'adresses IP/MAC et isoler les communications inter-VMs."
    )

    # Tableau d'inventaire
    table = doc.add_table(rows=1, cols=5)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    hdr_cells = table.rows[0].cells
    headers = ["Machine", "Type / VMID", "Adresse IP", "Rôle / Service", "Spécifications"]
    for i, h in enumerate(headers):
        hdr_cells[i].text = h
        hdr_cells[i].paragraphs[0].runs[0].font.bold = True
        hdr_cells[i].paragraphs[0].runs[0].font.color.rgb = RGBColor(255, 255, 255)
        set_cell_background(hdr_cells[i], HEADER_BG)

    inv_data = [
        ("ansible", "LXC 300", "192.168.1.161", "Nœud de contrôle Ansible & Cache LLM", "2 Cores, 2 Go RAM, 23 Go NVMe"),
        ("pve", "Hyperviseur", "192.168.1.116", "Hôte Proxmox VE 9.2 (Gateway 10.30.0.1)", "24 vCPUs, 128 Go RAM, nftables"),
        ("agent", "VM 301 (KVM)", "10.30.0.10", "Attaquant : Hermes + llama-server (Qwen 7B)", "8 vCPUs, 32 Go RAM, 80 Go NVMe"),
        ("target", "VM 302 (KVM)", "10.30.0.20", "Cible web vulnérable : Nginx (port 8080)", "2 vCPUs, 2 Go RAM, 20 Go NVMe"),
        ("logging", "VM 303 (KVM)", "10.30.0.30", "Serveur centralisé : rsyslog (TCP/514)", "2 vCPUs, 2 Go RAM, 20 Go NVMe")
    ]

    for row_idx, data in enumerate(inv_data):
        row_cells = table.add_row().cells
        bg_col = "F8F9F9" if row_idx % 2 == 1 else "FFFFFF"
        for i, val in enumerate(data):
            row_cells[i].text = val
            row_cells[i].paragraphs[0].runs[0].font.size = Pt(9)
            set_cell_background(row_cells[i], bg_col)

    doc.add_paragraph().paragraph_format.space_after = Pt(4)

    # ==================== 4. PLAYBOOKS, RÔLES & TEMPLATES ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("4. Implémentation des Playbooks et des Rôles")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph("Le projet s'articule autour de 6 playbooks spécialisés orchestrés par un playbook maître (site.yml) :")

    plays = [
        ("01-infra.yml", "Rôles proxmox_network et proxmox_vms", "Configure l'interface vmbr3 et nftables sur l'hôte, puis clone le template Debian 13 (9000) via l'API Proxmox, configure le matériel (CPU, RAM, disque) et cloud-init."),
        ("02-base.yml", "Rôle common", "Crée l'utilisateur de service 'ansible', injecte la clé ED25519, configure sudo sans mot de passe, durcit sshd (/etc/ssh/sshd_config.d/lab.conf) et déploie le client rsyslog vers 10.30.0.30."),
        ("03-logging.yml", "Rôle log_server", "Déploie la configuration rsyslog serveur avec séparation des journaux par adresse IP réelle du client (/var/log/lab/%fromhost-ip%.log) et notification du handler de service."),
        ("04-target.yml", "Rôle web_target", "Installe Nginx et déploie un site web volontairement vulnérable avec listage de répertoire actif (autoindex on) sur le port non conventionnel 8080."),
        ("05-agent.yml", "Rôle agent_host", "Installe les outils offensifs (nmap, curl, requests), déploie llama-server, installe le modèle Qwen 2.5 7B Instruct (4.4 Go) via cache local contrôleur, configure le service systemd et l'agent Hermes."),
        ("site.yml", "Playbook Maître", "Importe séquentiellement 01-infra, 02-base, 03-logging, 04-target et 05-agent pour permettre un déploiement 100 % automatisé en une seule commande."),
        ("99-verify.yml", "Playbook de Preuve", "Exécute 3 tests positifs et 4 tests négatifs pour valider mathématiquement la conformité de l'isolation du laboratoire."),
        ("90-destroy.yml", "Playbook de Nettoyage", "Arrête et détruit proprement les 3 VMs par l'API Proxmox pour restaurer l'état initial sans laisser de traces résiduelles.")
    ]

    for name, roles, desc in plays:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(2)
        r = p.add_run(f"• {name} ({roles}) : ")
        r.bold = True
        r.font.color.rgb = PRIMARY
        p.add_run(desc)

    # ==================== 5. VALIDATION, IDEMPOTENCE & PREUVES ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("5. Validation des Résultats, Idempotence & Preuve de Sécurité")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph(
        "Chaque playbook a été testé selon la règle d'idempotence stricte : un second passage consécutif n'apporte "
        "aucune modification (changed=0, failed=0). En mode isolé (lab_mode: isolated), les règles nftables ont été "
        "validées par 99-verify.yml :"
    )

    # Tableau des flux
    t_sec = doc.add_table(rows=1, cols=5)
    t_sec.alignment = WD_TABLE_ALIGNMENT.CENTER
    s_cells = t_sec.rows[0].cells
    s_headers = ["Flux testé", "Source / Dest.", "Port / Protocole", "Résultat attendu", "Statut constaté"]
    for i, h in enumerate(s_headers):
        s_cells[i].text = h
        s_cells[i].paragraphs[0].runs[0].font.bold = True
        s_cells[i].paragraphs[0].runs[0].font.color.rgb = RGBColor(255, 255, 255)
        set_cell_background(s_cells[i], HEADER_BG)

    sec_data = [
        ("Exploitation Web", "agent -> target", "TCP/8080 (HTTP)", "Succès (HTTP 200)", "VALIDÉ (Index of / compromis)"),
        ("Télémétrie Syslog", "agent/target -> logging", "TCP/514 (Syslog)", "Succès (Logs reçus)", "VALIDÉ (/var/log/lab/*.log)"),
        ("Moteur IA Local", "agent (localhost)", "TCP/8081 (API LLM)", "Succès (status: ok)", "VALIDÉ (Qwen 7B prêt)"),
        ("Évasion Internet", "agent -> 1.1.1.1", "TCP/80 (Web public)", "REJET (Bloqué)", "VALIDÉ (LAB-REJECT-SORTIE, rc=7)"),
        ("Rebond LAN", "agent -> 192.168.1.1", "TCP/80 (Passerelle LAN)", "REJET (Bloqué)", "VALIDÉ (LAB-REJECT-SORTIE, rc=7)"),
        ("Attaque Hyperviseur", "agent -> 192.168.1.116", "TCP/8006 (Proxmox UI)", "REJET (Bloqué)", "VALIDÉ (LAB-REJECT-IN, rc=7)"),
        ("Piratage Serveur Logs", "agent -> logging", "TCP/22 (SSH inter-VM)", "REJET (Bloqué L2)", "VALIDÉ (LAB-REJECT-LOGS, rc=1)")
    ]

    for row_idx, data in enumerate(sec_data):
        row_cells = t_sec.add_row().cells
        bg_col = "F8F9F9" if row_idx % 2 == 1 else "FFFFFF"
        for i, val in enumerate(data):
            row_cells[i].text = val
            row_cells[i].paragraphs[0].runs[0].font.size = Pt(9)
            set_cell_background(row_cells[i], bg_col)

    doc.add_paragraph().paragraph_format.space_after = Pt(4)

    # ==================== 6. JOURNAL DES DIFFICULTÉS ET SOLUTIONS ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("6. Journal des Difficultés Rencontrées et Solutions Apportées (10 % de la grille)")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph(
        "Conformément à la grille de correction, voici l'analyse des cinq défis techniques majeurs "
        "surmontés durant la réalisation de ce laboratoire :"
    )

    diffs = [
        ("1. Certificat auto-signé Proxmox API 9.2", 
         "Lors du clonage des VMs par community.general.proxmox_kvm, le module échouait avec 'SSL: CERTIFICATE_VERIFY_FAILED' en contactant l'API sur le port 8006.",
         "Ajout explicite de 'validate_certs: false' dans les paramètres des modules proxmox_kvm et proxmox_disk."),
        
        ("2. Perte d'IP VirtIO lors du clonage Cloud-Init (Hot-Plug)", 
         "Au second run du playbook d'infrastructure, le module proxmox_kvm tentait de reconfigurer net0 sans connaître l'adresse MAC générée, provoquant une réinitialisation du lien VirtIO et la perte de l'IP en mémoire vive de la VM.",
         "Conditionnement du déploiement : interrogation préalable de l'état de la machine via proxmox_vm_info. Si la machine est déjà 'running', la reconfiguration matérielle à chaud est évitée, garantissant une idempotence parfaite."),
        
        ("3. Écrasement des routes statiques au redémarrage du LXC 300", 
         "Le conteneur de contrôle LXC perdait sa route statique vers 10.30.0.0/24 à chaque reboot car Proxmox régénère dynamiquement /etc/network/interfaces dans les conteneurs.",
         "Création d'un script exécutable persistant dans /etc/network/if-up.d/lab-route qui réapplique automatiquement la route à chaque montée de l'interface eth0."),
        
        ("4. Filtrage L2 sans impacter le trafic existant de l'hyperviseur", 
         "La table 'bridge lab_l2' de nftables inspectait tous les ponts réseau de l'hôte, risquant de perturber le réseau local (vmbr0) ou Security Onion (vmbr9).",
         "Ajout d'une règle de dérivation en tête de chaîne : 'meta ibrname != \"vmbr3\" accept', confinant le filtrage L2 exclusivement au pont virtuel du laboratoire."),
         
        ("5. Optimisation thermique et mise en cache locale du LLM", 
         "L'inférence CPU avec 8 threads vectoriels AVX saturait les processeurs Xeon E5-2620, élevant les températures à 86 °C, tandis que retélécharger 4.4 Go depuis Internet à chaque test était sous-optimal.",
         "Ajustement de llama-server à 4 threads (limité à un seul socket NUMA) et 150 tokens max, faisant chuter les températures à 69-71 °C. Stockage persistant du modèle GGUF dans /root/lab-ansible/models-cache/ sur le contrôleur avec bascule conditionnelle locale/distante.")
    ]

    for title, pb, sol in diffs:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(2)
        r = p.add_run(f"• {title}\n")
        r.bold = True
        r.font.color.rgb = PRIMARY
        p_desc = p.add_run(f"   - Problème : {pb}\n   - Solution apportée : {sol}")
        p_desc.font.size = Pt(9.5)

    # ==================== 7. CONCLUSION ====================
    h1 = doc.add_heading(level=1)
    h1.add_run("7. Conclusion et Perspectives")
    h1.paragraph_format.space_before = Pt(12)
    h1.paragraph_format.space_after = Pt(4)

    p = doc.add_paragraph(
        "Ce projet valide avec succès l'ensemble des compétences de l'AEC LEA.84 relatives à Ansible et Linux. "
        "Il prouve qu'Ansible n'est pas seulement un outil de déploiement de serveurs basiques, mais un moteur d'orchestration "
        "complet capable de gérer le cycle de vie d'hyperviseurs modernes, de sécuriser des réseaux isolés et d'intégrer des technologies "
        "d'intelligence artificielle émergentes (agents LLM locaux) dans des scénarios réalistes de cybersécurité défensive et offensive."
    )

    doc.save(output_path)
    print(f"Rapport généré avec succès dans : {output_path}")

if __name__ == '__main__':
    create_report("/root/lab-ansible/Rapport-Projet-Ansible-Proxmox-LEA84.docx")