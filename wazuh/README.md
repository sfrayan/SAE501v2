# Wazuh Docker - SAE 5.01

Configuration et intégration de Wazuh pour la surveillance sécurité du projet SAE 5.01 (FreeRADIUS + Monitoring).

## 📊 Vue d'ensemble

Wazuh surveille en temps réel :
- ✅ Authentifications RADIUS (succès/échecs)
- ✅ Tentatives de bruteforce
- ✅ Logs routeur TP-Link TL-MR100 (via syslog)
- ✅ Modifications fichiers critiques
- ✅ Activité SSH
- ✅ Escalade de privilèges
- ✅ Arrêt services critiques

## 🚀 Installation rapide

### Prérequis

- Ubuntu 22.04 LTS
- 8GB RAM minimum (recommandé)
- 50GB espace disque
- Docker installé (le script l'installe automatiquement)

### Installation

```bash
# Cloner le projet
git clone https://github.com/sfrayan/SAE501v2.git
cd SAE501v2

# Lancer l'installation
sudo bash scripts/install_wazuh.sh
```

**Durée:** 5-10 minutes

### Accès Dashboard

Après installation :

```
URL:      https://192.168.10.100:443
Username: admin
Password: SecretPassword (voir /root/wazuh-docker-info.txt)
```

⚠️ **Acceptez le certificat auto-signé dans votre navigateur**

## 🛠️ Configuration

### Fichiers de configuration

```
wazuh/
├── local_rules.xml              # Règles de détection personnalisées
├── manager.conf                 # Configuration Wazuh Manager
├── docker-compose.override.yml # Configuration Docker personnalisée
└── syslog-tlmr100.conf          # Configuration rsyslog routeur
```

### Appliquer les configurations personnalisées

```bash
# Copier la configuration Docker override
sudo cp wazuh/docker-compose.override.yml /opt/wazuh-docker/single-node/

# Redémarrer Wazuh
cd /opt/wazuh-docker/single-node
sudo docker compose down
sudo docker compose up -d
```

### Configuration rsyslog (logs routeur)

```bash
# Copier la configuration rsyslog
sudo cp wazuh/syslog-tlmr100.conf /etc/rsyslog.d/20-wazuh-router.conf

# Redémarrer rsyslog
sudo systemctl restart rsyslog

# Configurer le routeur TP-Link pour envoyer les logs
# Interface routeur > System Tools > Log Settings
# Remote Syslog Server: 192.168.10.100:514
```

## 📊 Monitoring

### Commandes essentielles

```bash
# État des conteneurs
cd /opt/wazuh-docker/single-node
docker compose ps

# Logs en temps réel
docker compose logs -f wazuh.manager

# Utilisation ressources
docker stats

# Alertes Wazuh
docker compose exec wazuh.manager tail -f /var/ossec/logs/alerts/alerts.log

# Alertes JSON (format structuré)
docker compose exec wazuh.manager tail -f /var/ossec/logs/alerts/alerts.json | jq
```

### Dashboards Wazuh

Accédez au Dashboard Wazuh et explorez :

1. **Security Events** : Vue d'ensemble des alertes
2. **Integrity Monitoring** : Modifications fichiers
3. **Vulnerability Detection** : Vulnérabilités détectées
4. **Regulatory Compliance** : Conformité PCI-DSS, GDPR
5. **MITRE ATT&CK** : Techniques d'attaque détectées

### Alertes personnalisées SAE501

Les règles dans `local_rules.xml` détectent :

| Rule ID | Événement | Niveau | Description |
|---------|----------|--------|-------------|
| 5001 | RADIUS Auth OK | 3 | Authentification réussie |
| 5010 | RADIUS Auth KO | 5 | Authentification échouée |
| 5020 | TLS Error | 7 | Erreur certificat |
| 5030 | Service stopped | 8 | FreeRADIUS arrêté |
| 5040 | Config modifiée | 7 | Fichier critique modifié |
| 5051 | SSH root attempt | 5 | Tentative connexion root |
| 5060 | Sudo command | 6 | Escalade de privilèges |
| 5070 | UFW blocked | 4 | Paquet bloqué par firewall |

## 🔍 Intégration RADIUS

### Configuration FreeRADIUS

Wazuh surveille automatiquement :

```bash
/var/log/freeradius/radius.log      # Logs FreeRADIUS principaux
/var/log/radius-auth.log            # Authentifications filtrées
/var/log/remote-syslog.log          # Logs routeur distant
```

### Tester la détection

```bash
# Générer une alerte test
logger -t radiusd "Received Access-Accept for user alice@gym.fr"

# Vérifier l'alerte (2-3 secondes)
docker compose exec wazuh.manager grep "5001" /var/ossec/logs/alerts/alerts.log
```

### Tableau de bord authentifications

Dans le Dashboard Wazuh :
1. Aller dans **Modules** > **Security Events**
2. Filtrer : `rule.groups: radius_auth_success`
3. Visualiser les authentifications réussies en temps réel

## 🛡️ Sécurité

### Bonnes pratiques

1. **Changer les mots de passe par défaut**
```bash
cd /opt/wazuh-docker/single-node
# Éditer docker-compose.yml
nano docker-compose.yml
# Modifier INDEXER_PASSWORD
docker compose down
docker compose up -d
```

2. **Activer HTTPS avec certificats valides**
```bash
# Générer certificats Let's Encrypt
sudo apt install certbot
sudo certbot certonly --standalone -d wazuh.votredomaine.fr

# Copier dans config Wazuh
sudo cp /etc/letsencrypt/live/wazuh.votredomaine.fr/fullchain.pem \
  /opt/wazuh-docker/single-node/config/wazuh_indexer_ssl_certs/
```

3. **Restreindre accès Dashboard**
```bash
# Autoriser uniquement réseau local
sudo ufw allow from 192.168.10.0/24 to any port 443
sudo ufw deny 443/tcp
```

### Surveillance des accès

Wazuh enregistre automatiquement :
- Connexions au Dashboard
- Modifications de règles
- Changements de configuration
- Accès API

## 💾 Sauvegarde & Restauration

### Sauvegarde manuelle

```bash
# Créer sauvegarde complète
cd /opt/wazuh-docker/single-node
sudo docker compose exec wazuh.manager tar czf /tmp/wazuh-backup.tar.gz \
  /var/ossec/etc /var/ossec/logs /var/ossec/rules

# Extraire la sauvegarde
sudo docker compose cp wazuh.manager:/tmp/wazuh-backup.tar.gz ~/wazuh-backup-$(date +%Y%m%d).tar.gz
```

### Sauvegarde automatique

```bash
# Créer script de sauvegarde
sudo nano /usr/local/bin/backup-wazuh.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/backups/wazuh"
mkdir -p "$BACKUP_DIR"
cd /opt/wazuh-docker/single-node
docker compose exec -T wazuh.manager tar czf - \
  /var/ossec/etc /var/ossec/logs > "$BACKUP_DIR/wazuh-$(date +%Y%m%d-%H%M).tar.gz"
find "$BACKUP_DIR" -name "wazuh-*.tar.gz" -mtime +7 -delete
```

```bash
# Rendre exécutable
sudo chmod +x /usr/local/bin/backup-wazuh.sh

# Ajouter au cron (quotidien 2h du matin)
sudo crontab -e
0 2 * * * /usr/local/bin/backup-wazuh.sh
```

### Restauration

```bash
# Copier sauvegarde dans conteneur
sudo docker compose cp ~/wazuh-backup-20260202.tar.gz wazuh.manager:/tmp/

# Restaurer
sudo docker compose exec wazuh.manager tar xzf /tmp/wazuh-backup-20260202.tar.gz -C /

# Redémarrer
sudo docker compose restart wazuh.manager
```

## 🔧 Maintenance

### Mise à jour Wazuh

```bash
# Arrêter Wazuh
cd /opt/wazuh-docker/single-node
sudo docker compose down

# Cloner nouvelle version
cd /opt
sudo git clone https://github.com/wazuh/wazuh-docker.git -b v4.15.0 wazuh-docker-new

# Copier configurations
sudo cp -r wazuh-docker/single-node/config wazuh-docker-new/single-node/
sudo cp wazuh-docker/single-node/docker-compose.override.yml wazuh-docker-new/single-node/

# Redémarrer avec nouvelle version
cd wazuh-docker-new/single-node
sudo docker compose up -d

# Vérifier
sudo docker compose ps
sudo docker compose logs -f
```

### Nettoyage logs

```bash
# Nettoyer anciens logs (> 30 jours)
sudo docker compose exec wazuh.manager find /var/ossec/logs/archives -name "*.gz" -mtime +30 -delete

# Rotation manuelle
sudo docker compose exec wazuh.manager /var/ossec/bin/wazuh-logrotate
```

### Optimisation performances

```bash
# Ajuster mémoire Indexer si VM < 8GB RAM
cd /opt/wazuh-docker/single-node
nano docker-compose.override.yml

# Modifier:
environment:
  - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"  # Au lieu de 1g

# Redémarrer
docker compose restart wazuh.indexer
```

## ❌ Désinstallation

### Désinstallation complète

```bash
# Désinstallation avec suppression des données
sudo bash scripts/uninstall_wazuh.sh

# Conserver les données
sudo bash scripts/uninstall_wazuh.sh --keep-data

# Mode forcé (sans confirmation)
sudo bash scripts/uninstall_wazuh.sh --force
```

## 🐛 Troubleshooting

### Dashboard inaccessible

```bash
# Vérifier conteneurs
docker compose ps

# Vérifier logs
docker compose logs wazuh.dashboard

# Redémarrer Dashboard
docker compose restart wazuh.dashboard

# Attendre 2-3 minutes pour initialisation complète
```

### Wazuh Manager ne démarre pas

```bash
# Vérifier logs
docker compose logs wazuh.manager

# Vérifier configuration
docker compose exec wazuh.manager /var/ossec/bin/wazuh-control info

# Tester syntaxe règles
docker compose exec wazuh.manager /var/ossec/bin/wazuh-logtest
```

### Pas d'alertes RADIUS

```bash
# Vérifier que FreeRADIUS log
sudo tail -f /var/log/freeradius/radius.log

# Vérifier que Wazuh lit les logs
docker compose exec wazuh.manager grep "radiusd" /var/ossec/logs/ossec.log

# Tester règle manuellement
docker compose exec wazuh.manager /var/ossec/bin/wazuh-logtest
# Entrer: "Received Access-Accept for user alice@gym.fr"
# Doit afficher: Rule: 5001
```

### Consommation mémoire élevée

```bash
# Vérifier utilisation
docker stats

# Réduire mémoire Indexer
# Éditer docker-compose.override.yml
environment:
  - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"

# Redémarrer
docker compose restart wazuh.indexer
```

## 📚 Ressources

### Documentation officielle

- [Wazuh Documentation](https://documentation.wazuh.com/current/)
- [Wazuh Docker GitHub](https://github.com/wazuh/wazuh-docker)
- [Wazuh Ruleset](https://github.com/wazuh/wazuh-ruleset)

### Communauté

- [Wazuh Forum](https://wazuh.com/community/)
- [GitHub Issues](https://github.com/wazuh/wazuh/issues)
- [Slack](https://wazuh.com/community/join-us-on-slack/)

### Tutoriels SAE501

- [Configuration FreeRADIUS](../radius/README.md)
- [Intégration PHP-Admin](../php-admin/README.md)
- [Tests et validation](../tests/README.md)

## 👥 Auteurs

**Projet SAE 5.01 - GroupeNani**
- Configuration Wazuh personnalisée
- Intégration RADIUS/Syslog
- Règles de détection SAE501

---

🔒 **Sécurité avant tout !** Wazuh surveille votre infrastructure 24/7.
