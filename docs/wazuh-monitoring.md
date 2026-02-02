# 📊 Wazuh Monitoring - SAE 5.01

## 📋 Vue d'ensemble

Configuration complète du monitoring Wazuh pour l'infrastructure RADIUS sécurisée.

### 🎯 Objectifs

- **Monitoring centralisé** : Surveillance temps-réel de tous les composants
- **Détection d'intrusion** : Alertes automatiques sur activités malveillantes
- **Conformité** : PCI-DSS, GDPR, HIPAA
- **Response automatique** : Blocage IP malveillantes
- **Forensic** : Historique complet des événements

---

## 🏗️ Architecture Wazuh

```
┌─────────────────────────────────────────────────────────────┐
│                    WAZUH MANAGER                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  • Dashboard Web (port 443)                           │  │
│  │  • Indexer (OpenSearch)                               │  │
│  │  │  • Rules Engine                                     │  │
│  │  • Decoder Engine                                     │  │
│  │  • Active Response                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ▲                                   │
│                          │ UDP 1514                          │
│                          │                                   │
└──────────────────────────┼───────────────────────────────────┘
                           │
                           │
┌──────────────────────────▼───────────────────────────────────┐
│              WAZUH AGENT (Serveur RADIUS)                    │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Logs monitorés:                                      │  │
│  │  • /var/log/freeradius/radius.log                     │  │
│  │  • /var/log/auth.log (SSH)                            │  │
│  │  • /var/log/ufw.log (Firewall)                        │  │
│  │  • /var/log/fail2ban.log                              │  │
│  │  • /var/log/apache2/error.log                         │  │
│  │  • /var/log/mysql/error.log                           │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  FIM (File Integrity Monitoring):                     │  │
│  │  • /etc/freeradius/3.0/ (real-time)                   │  │
│  │  • /etc/ssh/sshd_config (real-time)                   │  │
│  │  • /etc/ufw/ (real-time)                              │  │
│  │  • /etc/fail2ban/ (real-time)                         │  │
│  │  • /var/www/html/php-admin/ (real-time)               │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Installation

### 1. Installation automatique

```bash
cd ~/SAE501v2
sudo bash scripts/setup_wazuh.sh
```

### 2. Configuration Manager (sur serveur Wazuh)

```bash
# Copier décodeurs
scp ~/SAE501v2/wazuh/custom_decoders.xml wazuh-manager:/var/ossec/etc/decoders/local_decoder.xml

# Copier règles
scp ~/SAE501v2/wazuh/custom_rules.xml wazuh-manager:/var/ossec/etc/rules/local_rules.xml

# Redémarrer Manager
sudo systemctl restart wazuh-manager
```

### 3. Vérification

```bash
# Status agent
sudo /var/ossec/bin/wazuh-control status

# Logs agent
sudo tail -f /var/ossec/logs/ossec.log

# Connexion Manager
sudo /var/ossec/bin/wazuh-control info
```

---

## 🔍 Règles de détection

### FreeRADIUS (100800-100899)

| Rule ID | Niveau | Description |
|---------|--------|-------------|
| **100802** | 3 | Authentification RADIUS réussie |
| **100803** | 5 | Authentification RADIUS échouée |
| **100804** | 8 | 5 échecs auth en 2 min (brute-force) |
| **100805** | 10 | 10 échecs en 5 min (attaque sévère) → **Active Response** |
| **100806** | 7 | Erreur SQL FreeRADIUS |
| **100807** | 8 | Client RADIUS inconnu (rogue AP) |
| **100808** | 6 | Tentative auth utilisateur inexistant |

### Fail2Ban (100900-100999)

| Rule ID | Niveau | Description |
|---------|--------|-------------|
| **100901** | 6 | IP bannie par Fail2Ban |
| **100902** | 3 | IP débannie |
| **100903** | 4 | IP détectée (pré-ban) |
| **100904** | 10 | Même IP bannie 3× en 1h (attaquant persistant) |

### UFW Firewall (101000-101099)

| Rule ID | Niveau | Description |
|---------|--------|-------------|
| **101001** | 3 | Connexion bloquée par UFW |
| **101003** | 8 | Port scan détecté (10 tentatives/min) |
| **101004** | 9 | Tentative accès MySQL externe (3306) |
| **101005** | 8 | Tentative accès RADIUS non-LAN (1812) |
| **101006** | 7 | Modification règles firewall |

### SSH Avancé (101100-101199)

| Rule ID | Niveau | Description |
|---------|--------|-------------|
| **101100** | 8 | Tentative connexion root SSH |
| **101101** | 6 | Scan SSH détecté |
| **101102** | 5 | Connexion SSH depuis IP externe |

### File Integrity Monitoring (101200-101299)

| Rule ID | Niveau | Description |
|---------|--------|-------------|
| **101200** | 8 | Fichier config FreeRADIUS modifié |
| **101201** | 9 | `sshd_config` modifié |
| **101202** | 8 | Règles UFW modifiées |
| **101203** | 7 | Config Fail2Ban modifiée |
| **101204** | 7 | Fichier PHP-Admin modifié (web shell?) |
| **101205** | 10 | Fichier système critique supprimé |

---

## ⚡ Active Response

Blocage automatique d'IP malveillantes.

### Règles déclenchant Active Response

| Rule ID | Déclencheur | Timeout | Action |
|---------|-------------|---------|--------|
| **5763** | 5 échecs SSH en 2 min | 10 min | `firewall-drop` |
| **100805** | 10 échecs RADIUS en 5 min | 30 min | `firewall-drop` |

### Commande exécutée

```bash
# Blocage IP avec iptables
iptables -I INPUT -s <IP_MALVEILLANTE> -j DROP

# Déblocage automatique après timeout
```

### Vérification Active Response

```bash
# Logs Active Response
sudo tail -f /var/ossec/logs/active-responses.log

# IP actuellement bloquées
sudo iptables -L INPUT -v -n | grep DROP
```

---

## 📊 Dashboard Wazuh

### Accès

```
https://<wazuh-manager-ip>:443
```

### Dashboards recommandés

#### 1. Security Events

```
Security events → Filters:
- rule.groups: "authentication_failed"
- rule.level: >=8
- Time range: Last 24h
```

#### 2. FreeRADIUS Monitoring

```
Discover → Filters:
- rule.id: 100802,100803,100804,100805
- Visualization: Bar chart
- X-axis: @timestamp
- Split series: rule.description
```

#### 3. Firewall Activity

```
Discover → Filters:
- rule.id: 101001,101003,101004,101005
- Visualization: Pie chart
- Split slices: data.dstport
```

#### 4. File Integrity Monitoring

```
Security events → Filters:
- rule.groups: "syscheck"
- rule.level: >=7
```

---

## 🧪 Tests de détection

### Test 1: Brute-force RADIUS

```bash
# Générer 10 tentatives auth échouées
for i in {1..10}; do
  radtest fake@gym.fr WrongPass 127.0.0.1 1812 testing123
  sleep 1
done

# Vérifier alerte Wazuh
# Dashboard → Rule ID: 100805
# Active Response doit bloquer IP
```

### Test 2: Scan de ports

```bash
# Depuis machine externe
nmap -p 1-1000 192.168.10.100

# Vérifier alerte Wazuh
# Dashboard → Rule ID: 101003
```

### Test 3: Modification fichier

```bash
# Modifier config SSH
sudo nano /etc/ssh/sshd_config
# (ajouter un commentaire)

# Vérifier alerte Wazuh
# Dashboard → Rule ID: 101201
```

### Test 4: Tentative connexion root SSH

```bash
# Depuis machine externe
ssh root@192.168.10.100
# (mot de passe quelconque)

# Vérifier alerte Wazuh
# Dashboard → Rule ID: 101100
```

---

## 📧 Configuration alertes email

### Sur Wazuh Manager

```xml
<!-- /var/ossec/etc/ossec.conf -->
<ossec_config>
  <global>
    <email_notification>yes</email_notification>
    <smtp_server>smtp.gmail.com</smtp_server>
    <email_from>wazuh@sae501.local</email_from>
    <email_to>admin@sae501.local</email_to>
  </global>

  <!-- Alertes niveau >= 10 -->
  <email_alerts>
    <email_to>security@sae501.local</email_to>
    <level>10</level>
    <do_not_delay />
  </email_alerts>

  <!-- Alertes brute-force RADIUS -->
  <email_alerts>
    <email_to>radius-admin@sae501.local</email_to>
    <rule_id>100805</rule_id>
    <do_not_delay />
  </email_alerts>
</ossec_config>
```

---

## 🔧 Commandes utiles

### Agent

```bash
# Status
sudo /var/ossec/bin/wazuh-control status

# Redémarrer
sudo systemctl restart wazuh-agent

# Logs
sudo tail -f /var/ossec/logs/ossec.log

# Info agent
sudo /var/ossec/bin/wazuh-control info

# Version
sudo /var/ossec/bin/wazuh-control -V
```

### Manager (sur serveur Wazuh)

```bash
# Test règles
sudo /var/ossec/bin/wazuh-logtest

# Lister agents
sudo /var/ossec/bin/wazuh-control list

# Voir règle spécifique
sudo grep -A 10 "id=\"100805\"" /var/ossec/etc/rules/local_rules.xml

# Recharger règles
sudo /var/ossec/bin/wazuh-control reload

# Statistiques
sudo /var/ossec/bin/wazuh-control status
```

---

## 📈 Métriques de sécurité

### KPIs à surveiller

| Métrique | Seuil normal | Alerte |
|----------|--------------|--------|
| Authentifications RADIUS échouées | < 10/jour | > 50/jour |
| Connexions SSH échouées | < 5/jour | > 20/jour |
| Ports bloqués UFW | < 100/jour | > 500/jour |
| Modifications fichiers critiques | 0/jour | > 0 |
| IP bannies Fail2Ban | < 3/jour | > 10/jour |
| Erreurs SQL RADIUS | 0/jour | > 5/jour |

---

## 🛡️ Conformité

### PCI-DSS

- **10.2.4** : Échecs authentification ✅
- **10.2.5** : Authentifications réussies ✅
- **10.6.1** : Monitoring logs sécurité ✅
- **11.4** : Détection intrusion ✅
- **11.5** : File integrity monitoring ✅

### GDPR

- **Article 32** : Sécurité traitement données ✅
- **Article 35.7.d** : Monitoring violations ✅

---

## 🐛 Troubleshooting

### Agent ne se connecte pas

```bash
# Vérifier connectivité
telnet <wazuh-manager-ip> 1514

# Vérifier clés
sudo cat /var/ossec/etc/client.keys

# Logs détaillés
sudo /var/ossec/bin/wazuh-control start -d
```

### Logs non collectés

```bash
# Vérifier permissions
ls -la /var/log/freeradius/radius.log
sudo usermod -aG freerad wazuh

# Tester lecture
sudo -u wazuh cat /var/log/freeradius/radius.log
```

### Règles ne déclenchent pas

```bash
# Test manuel règle
sudo /var/ossec/bin/wazuh-logtest
# Coller ligne de log

# Vérifier syntaxe règles
sudo /var/ossec/bin/verify-agent-conf
```

---

## 📚 Ressources

- [Documentation officielle Wazuh](https://documentation.wazuh.com/current/)
- [FreeRADIUS decoder tutorial](https://www.zerozone.it/cybersecurity/how-to-add-freeradius-logs-in-wazuh-siem/23460)
- [Fail2Ban integration](https://www.infopercept.com/blogs/wazuh-integration-with-fail2ban)
- [Custom rules documentation](https://documentation.wazuh.com/current/user-manual/ruleset/rules/custom.html)
- [Active Response guide](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/)

---

## ✅ Checklist déploiement

- [ ] Wazuh agent installé et connecté
- [ ] Logs RADIUS, SSH, UFW, Fail2Ban collectés
- [ ] Décodeurs personnalisés chargés
- [ ] Règles personnalisées actives
- [ ] FIM configuré (temps-réel)
- [ ] Active Response fonctionnel
- [ ] Dashboard accessible
- [ ] Tests détection réussis
- [ ] Alertes email configurées
- [ ] Documentation accessible équipe

---

**🔒 Monitoring centralisé actif - Infrastructure sécurisée SAE 5.01**
