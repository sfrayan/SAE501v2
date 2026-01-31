# Supervision et Détection d'Intrusions — Wazuh

## 1. Contexte et Objectifs

**Wazuh** est un SIEM (Security Information and Event Management) open source qui centralise la collecte, l'analyse et l'alerte sur les événements de sécurité. Dans le contexte du SAE 5.01, Wazuh joue trois rôles critiques :

1. **Agrégation des logs** : Collecte les journaux du serveur Linux, des routeurs TL-MR100 et de FreeRADIUS.
2. **Détection d'anomalies** : Corrélation des événements et détection de patterns suspects (brute force, scan de ports, tentatives accès interdit).
3. **Alerting en temps réel** : Notification des administrateurs en cas d'incident.

---

## 2. Architecture Wazuh

### 2.1 Composants

```
┌────────────────────────────────────────────────────┐
│ WAZUH MANAGER (Serveur Central)                    │
│ IP: 192.168.10.254                                 │
├────────────────────────────────────────────────────┤
│                                                    │
│ ┌─ Wazuh Manager Daemon (ossec-wazuh)            │
│ │  ├─ Alert Sender (1514/TCP)                    │
│ │  ├─ Data Receiver (1515/TCP)                   │
│ │  └─ Syslog Receiver (514/UDP)                  │
│ │                                                 │
│ ┌─ Elasticsearch (Stockage logs)                 │
│ │  └─ Index par jour (wazuh-alerts-*)            │
│ │                                                 │
│ ┌─ Kibana (Interface Web)                        │
│ │  └─ Dashboards + Alertes                       │
│ │  └─ Port: 443/HTTPS                            │
│ │                                                 │
│ ┌─ Règles & Décodeurs Personnalisés             │
│ │  ├─ local_rules.xml                            │
│ │  ├─ local_decoder.xml                          │
│ │  └─ rootkit_hunter (optionnel)                │
│                                                    │
└────────────────────────────────────────────────────┘
           ▲
           │ Syslog (514/UDP)
           │ + RADIUS logs
           │ + FreeRADIUS logs
           │
    ┌──────┴──────┬──────────┐
    │             │          │
┌───┴────┐  ┌────┴────┐  ┌──┴─────┐
│ TL-MR100│ │ Serveur │  │Database│
│192.168.│ │ Linux   │  │ Logs   │
│10.1    │ │(local)  │  │Archive │
└────────┘ └─────────┘  └────────┘
```

### 2.2 Sources de Logs

| Source | Protocole | Port | Fichier/Stream | Contenu |
| :--- | :--- | :--- | :--- | :--- |
| **TP-Link TL-MR100** | Syslog UDP | 514 | Routeur Syslog | Authentifications Wi-Fi, connexions clients |
| **FreeRADIUS** | Fichier local | - | `/var/log/freeradius/radius.log` | Détails authentifications PEAP |
| **MariaDB** | Fichier local | - | `/var/log/mysql/error.log` | Erreurs DB, requêtes SQL (optionnel) |
| **SSH** | Syslog | - | `/var/log/auth.log` | Connexions SSH, tentatives |
| **UFW** | Syslog | - | `/var/log/ufw.log` | Paquets bloqués par pare-feu |
| **Système** | Syslog | - | `/var/log/syslog` | Événements système généraux |

---

## 3. Installation de Wazuh

### 3.1 Prérequis

- Ubuntu 22.04 LTS ou Debian 11+
- RAM : 4 GB minimum (2 GB Wazuh + 2 GB Elasticsearch)
- Disque : 50 GB minimum (logs persistants)
- CPU : 2 cores minimum

### 3.2 Commandes d'Installation

```bash
# 1. Ajouter le dépôt Wazuh
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo apt-key add -
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | \
  sudo tee /etc/apt/sources.list.d/wazuh.list

# 2. Mise à jour et installation
sudo apt update
sudo apt install -y wazuh-manager

# 3. Activation des services
sudo systemctl enable wazuh-manager
sudo systemctl start wazuh-manager

# 4. Vérification du statut
sudo systemctl status wazuh-manager
sudo wazuh-control status
```

---

## 4. Configuration du Wazuh Manager (`ossec.conf`)

Le fichier `/var/ossec/etc/ossec.conf` centralise la configuration de Wazuh.

### 4.1 Section de Réception Syslog

```xml
<!-- /var/ossec/etc/ossec.conf -->

<ossec_config>
  
  <!-- ============================================ -->
  <!-- Réception Syslog depuis routeurs distants   -->
  <!-- ============================================ -->
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>192.168.10.0/24</allowed-ips>
    <allowed-ips>192.168.20.0/24</allowed-ips>
    <!-- Optionnel: autres sites -->
    <!-- <allowed-ips>192.168.11.0/24</allowed-ips> -->
  </remote>

  <!-- ============================================ -->
  <!-- Monitorer les fichiers logs locaux          -->
  <!-- ============================================ -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
    <log_alert_level>3</log_alert_level>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/syslog</location>
  </localfile>

  <!-- FreeRADIUS (Logs d'authentification) -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/freeradius/radius.log</location>
    <log_alert_level>3</log_alert_level>
  </localfile>

  <!-- UFW Firewall -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/ufw.log</location>
    <log_alert_level>5</log_alert_level>
  </localfile>

  <!-- MySQL/MariaDB (Erreurs) -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/mysql/error.log</location>
    <log_alert_level>4</log_alert_level>
  </localfile>

</ossec_config>
```

---

## 5. Décodeurs Personnalisés

Les décodeurs extraient les informations structurées des logs bruts. Pour les logs du TL-MR100, il peut être nécessaire de créer un décodeur personnalisé.

### 5.1 Fichier `local_decoder.xml`

```xml
<!-- /var/ossec/etc/decoders/local_decoder.xml -->

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE decoder_config SYSTEM "decoder_config.xsd">

<decoder_config version="1.0">

  <!-- ============================================ -->
  <!-- Décodeur pour TP-Link TL-MR100 Logs       -->
  <!-- ============================================ -->
  <decoder name="tlmr100">
    <type>firewall</type>
    <prematch>^<\d+>.*TL-MR100</prematch>
    <plugin_decoder>true</plugin_decoder>
    <order>10</order>
  </decoder>

  <decoder name="tlmr100_wifi_connect">
    <parent>tlmr100</parent>
    <regex offset="after_parent">(\w+) connected to SSID</regex>
    <order>20</order>
    <plugin_decoder>true</plugin_decoder>
    <fields>
      <field name="srcMac">1</field>
    </fields>
  </decoder>

  <decoder name="tlmr100_wifi_disconnect">
    <parent>tlmr100</parent>
    <regex offset="after_parent">(\w+) disconnected from SSID</regex>
    <order>20</order>
    <plugin_decoder>true</plugin_decoder>
    <fields>
      <field name="srcMac">1</field>
    </fields>
  </decoder>

  <!-- ============================================ -->
  <!-- Décodeur pour FreeRADIUS                   -->
  <!-- ============================================ -->
  <decoder name="freeradius">
    <type>authentication_failed</type>
    <prematch>FreeRADIUS|Auth failed|Authentication</prematch>
    <plugin_decoder>true</plugin_decoder>
  </decoder>

  <decoder name="freeradius_auth_success">
    <parent>freeradius</parent>
    <regex offset="after_parent">User (\S+) authenticated successfully</regex>
    <order>20</order>
    <fields>
      <field name="user">1</field>
    </fields>
  </decoder>

  <decoder name="freeradius_auth_failed">
    <parent>freeradius</parent>
    <regex offset="after_parent">Authentication failure for user (\S+)</regex>
    <order>20</order>
    <fields>
      <field name="user">1</field>
    </fields>
  </decoder>

</decoder_config>
```

---

## 6. Règles Personnalisées

Les règles définissent comment détecter et alerter sur les événements suspects.

### 6.1 Fichier `local_rules.xml`

```xml
<!-- /var/ossec/etc/rules/local_rules.xml -->

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE rules SYSTEM "rules_config.xsd">

<rules>

  <!-- ============================================ -->
  <!-- Groupe: RADIUS Authentification           -->
  <!-- ============================================ -->
  <group name="radius_authentication">

    <!-- Authentification réussie -->
    <rule id="100001" level="3">
      <match>User.*authenticated successfully</match>
      <description>FreeRADIUS: Authentification réussie</description>
      <group>authentication_success</group>
    </rule>

    <!-- Authentification échouée (1 tentative) -->
    <rule id="100002" level="5">
      <match>Authentication failure for user</match>
      <description>FreeRADIUS: Tentative d'authentification échouée</description>
      <group>authentication_failed</group>
    </rule>

    <!-- Brute Force: Plusieurs échecs (Frequency) -->
    <rule id="100003" level="7">
      <if_matched_group>authentication_failed</if_matched_group>
      <frequency>5</frequency>
      <timeframe>60</timeframe>
      <description>FreeRADIUS: Brute Force détecté (5+ échecs en 60s)</description>
      <group>brute_force</group>
    </rule>

  </group>

  <!-- ============================================ -->
  <!-- Groupe: Segmentation Réseau (VLAN)        -->
  <!-- ============================================ -->
  <group name="network_isolation">

    <!-- Tentative accès invité vers réseau entreprise -->
    <rule id="100010" level="8">
      <srcip>192.168.20.0/24</srcip>
      <dstip>192.168.10.0/24</dstip>
      <description>ALERTE: Tentative de break isolation VLAN invité!</description>
      <group>security_violation</group>
    </rule>

  </group>

  <!-- ============================================ -->
  <!-- Groupe: SSH & Accès Administrateur        -->
  <!-- ============================================ -->
  <group name="ssh_security">

    <!-- Connexion SSH réussie -->
    <rule id="100020" level="3">
      <match>Accepted publickey for</match>
      <description>SSH: Connexion réussie par clé publique</description>
      <group>ssh_access</group>
    </rule>

    <!-- Tentative connexion SSH échouée -->
    <rule id="100021" level="4">
      <match>Failed password|Invalid user</match>
      <description>SSH: Tentative de connexion échouée</description>
      <group>ssh_failed</group>
    </rule>

    <!-- Brute Force SSH -->
    <rule id="100022" level="8">
      <if_matched_group>ssh_failed</if_matched_group>
      <frequency>10</frequency>
      <timeframe>60</timeframe>
      <description>SSH: Brute Force détecté (10+ échecs en 60s)</description>
      <group>brute_force</group>
    </rule>

    <!-- Tentative connexion en tant que root (bloquée) -->
    <rule id="100023" level="6">
      <match>Invalid user root|Received disconnect from.*root</match>
      <description>SSH: Tentative connexion directe root (BLOQUÉE)</description>
      <group>ssh_access_denied</group>
    </rule>

  </group>

  <!-- ============================================ -->
  <!-- Groupe: Pare-feu UFW                      -->
  <!-- ============================================ -->
  <group name="firewall_activity">

    <!-- Paquet bloqué (WARNING) -->
    <rule id="100030" level="4">
      <match>UFW BLOCK</match>
      <description>UFW: Paquet entrant bloqué</description>
      <group>firewall_denied</group>
    </rule>

    <!-- Port scanning (Nombreux paquets bloqués rapidement) -->
    <rule id="100031" level="7">
      <if_matched_group>firewall_denied</if_matched_group>
      <frequency>20</frequency>
      <timeframe>30</timeframe>
      <srcip>192.168.20.0/24</srcip>
      <description>ALERTE: Possible port scan depuis VLAN invité!</description>
      <group>reconnaissance</group>
    </rule>

  </group>

  <!-- ============================================ -->
  <!-- Groupe: Base de Données MariaDB           -->
  <!-- ============================================ -->
  <group name="database_security">

    <!-- Erreur connexion SQL -->
    <rule id="100040" level="4">
      <match>Access denied for user</match>
      <description>MariaDB: Accès refusé (credentials invalides)</description>
      <group>database_failed</group>
    </rule>

    <!-- Tentative requête suspecte (optionnel) -->
    <rule id="100041" level="6">
      <match>SQL injection|syntax error|malformed query</match>
      <description>MariaDB: Possible tentative d'injection SQL</description>
      <group>sql_injection</group>
    </rule>

  </group>

  <!-- ============================================ -->
  <!-- Groupe: Événements Système Critiques     -->
  <!-- ============================================ -->
  <group name="system_events">

    <!-- Redémarrage non planifié -->
    <rule id="100050" level="6">
      <match>Kernel panic|System reboot|Emergency reboot</match>
      <description>ALERTE: Redémarrage système anormal</description>
      <group>system_critical</group>
    </rule>

    <!-- Espace disque critique -->
    <rule id="100051" level="7">
      <match>No space left on device</match>
      <description>ALERTE: Disque plein</description>
      <group>system_critical</group>
    </rule>

  </group>

</rules>
```

---

## 7. Configuration de la Réception Syslog sur le TL-MR100

### 7.1 Configuration Web du Routeur

1. Accéder à `http://192.168.10.1`
2. Aller à **System Tools** → **System Log Settings**
3. Configurer :
   - **Syslog Server Address :** `192.168.10.254`
   - **Syslog Server Port :** `514`
   - **Log Level :** Info (ou Debug pour plus de détail)
   - **Enable Remote Syslog :** ✓ Activé

### 7.2 Vérification de la Réception

```bash
# Sur le serveur Wazuh, vérifier la réception UDP:514
sudo tcpdump -i eth0 -n 'udp port 514' -c 10

# Vérifier que les logs TL-MR100 apparaissent dans /var/ossec/logs/alerts/alerts.log
sudo tail -f /var/ossec/logs/alerts/alerts.log | grep "TL-MR100\|routeur"

# Redémarrer Wazuh si aucun log n'arrive
sudo systemctl restart wazuh-manager
```

---

## 8. Dashboards Kibana (Interface Web)

Wazuh est accessible via **Kibana** sur `https://192.168.10.254:443`.

### 8.1 Dashboards à Créer

| Dashboard | Description | Métrique Clé |
| :--- | :--- | :--- |
| **Authentifications** | Graphique du nombre d'authentifications réussies/échouées par jour | Trend + Heatmap par heure |
| **Brute Force** | Tentatives échouées en time-series | Alertes en temps réel |
| **Isolation VLAN** | Tentatives accès invité vers entreprise | Heatmap sources/destinations |
| **Accès SSH** | Connexions réussies + tentatives | Historique + géolocalisation IP |
| **Pare-feu UFW** | Paquets bloqués par port/source | Top 10 sources bloquées |
| **Événements Critiques** | Alertes level ≥ 7 | Chronologie + statistiques |

---

## 9. Procédure d'Alerting

### 9.1 Email (Optionnel mais Recommandé)

Pour envoyer une alerte mail lors d'un événement critique (brute force, violation isolation):

```xml
<!-- Ajouter dans ossec.conf -->
<email_notification>
  <email_to>admin@gym.fr</email_to>
  <smtp_server>localhost</smtp_server>
  <from_address>wazuh@192.168.10.254</from_address>
  <format>full</format>
</email_notification>
```

### 9.2 Conditions d'Alerte

```xml
<!-- Envoyer alerte email pour règles level ≥ 7 -->
<alert_level>7</alert_level>
```

---

## 10. Checklist de Validation

- [ ] Wazuh Manager déployé et actif
- [ ] Section `<remote>` configurée pour recevoir Syslog UDP 514
- [ ] TL-MR100 envoie des logs vers 192.168.10.254
- [ ] Décodeurs personnalisés chargés
- [ ] Règles personnalisées compilées
- [ ] Au moins 1 alerte reçue du routeur
- [ ] Kibana accessible et affichant les logs
- [ ] Dashboard "Authentifications" créé
- [ ] Test brute force : alertes niveau 7+ générées

---

## 11. Troubleshooting

| Problème | Cause Probable | Solution |
| :--- | :--- | :--- |
| **Aucun log du TL-MR100** | Routeur ne communique pas | Vérifier: 1) Config Syslog routeur, 2) Firewall UFW (514/UDP allow) |
| **Logs reçus mais non parsés** | Décodeur invalide | Vérifier syntaxe XML, redémarrer Wazuh |
| **Kibana très lent** | Elasticsearch surcharge | Augmenter RAM, vérifier espace disque |
| **Alertes ne s'envoient pas** | Configuration email incorrecte | Tester SMTP, vérifier adresse destinataire |

---

**Document rédigé par :** GroupeNani  
**Date :** 4 janvier 2026  
**Version :** 1.0
