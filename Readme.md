# Projet : Mise en place du monitoring pour MedAssist

## Contexte de l'entreprise

**MedAssist** est une startup spécialisée dans la téléconsultation médicale. Son application web permet aux patients de prendre rendez-vous en ligne, de consulter un médecin en visioconférence et de recevoir des ordonnances dématérialisées.

Suite à une croissance rapide (de 500 à 15 000 utilisateurs actifs en 6 mois), l'équipe technique fait face à des problèmes récurrents :

- **Les pannes sont découvertes par les patients** qui se plaignent sur les réseaux sociaux avant que l'équipe n'en soit informée
- **Le service de paiement plante régulièrement** sans que personne ne s'en rende compte — des consultations ne sont pas facturées
- **Les sauvegardes de la base de données échouent silencieusement** depuis 3 semaines
- **Une panne de 6 heures** le mois dernier a entraîné l'annulation de 47 consultations et une perte estimée à 8 500 €
- **Aucune visibilité** sur les performances : l'équipe ne sait pas si l'API répond en 200ms ou en 5 secondes
- **Aucun plan de réponse aux incidents** : quand un problème survient, c'est la panique générale

La direction de MedAssist vous mandate en tant qu'**ingénieurs DevOps/SRE** pour mettre en place une solution de monitoring complète sur leur infrastructure.

---

## Infrastructure fournie

L'application MedAssist est simulée par une stack Docker que vous devez lancer avant de commencer. Elle contient :

| Composant | Technologie | Description |
|-----------|-------------|-------------|
| Frontend | Nginx | Interface web statique + reverse proxy |
| API Backend | Flask (Python) | API REST avec métriques Prometheus intégrées |
| Base de données | MySQL 8.0 | Stockage des patients, rendez-vous, ordonnances |
| Cache | Redis 7 | Cache des données fréquemment consultées |
| Générateur de trafic | curl | Simule l'activité des patients (consultations, paiements) |

L'API expose déjà un endpoint `/metrics` au format Prometheus et produit des logs en JSON structuré. Le endpoint `/api/payment` a un taux d'erreur volontaire de ~5% pour simuler les problèmes de paiement.

### Lancement de l'application

```bash
cd etude-de-cas/
docker compose up -d
docker compose ps
curl http://localhost:5000/health
```

### Endpoints disponibles

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/health` | GET | Health check (état MySQL + Redis) |
| `/api/doctors` | GET | Liste des médecins disponibles |
| `/api/consultations` | GET / POST | Liste et prise de rendez-vous |
| `/api/payment` | GET / POST | Traitement des paiements (~5% d'erreurs) |
| `/metrics` | GET | Métriques Prometheus |

---

## Travail demandé

Votre mission se décompose en **6 parties**. Chaque partie doit être réalisée et documentée. Vous devez rendre un dépôt Git contenant l'ensemble de vos fichiers de configuration et un rapport.

---

### Partie 1 — Monitoring infrastructure avec Prometheus et Grafana

Mettez en place le monitoring de l'infrastructure MedAssist avec Prometheus et Grafana.

#### Ce que vous devez réaliser

1. Ajouter **Prometheus**, **Grafana**, **cAdvisor** et **Node Exporter** au `docker-compose.yml`
2. Configurer Prometheus pour scraper les métriques de l'API, des conteneurs et du système hôte
3. Créer un dashboard Grafana appliquant la **méthode USE** (Utilisation, Saturation, Erreurs) pour les ressources infrastructure (CPU, mémoire, réseau)
4. Créer un dashboard Grafana appliquant la **méthode RED** (Rate, Errors, Duration) pour l'API

#### Indices

- L'API expose ses métriques sur `/metrics` au format Prometheus (compteurs de requêtes, histogramme de latence, etc.)
- cAdvisor expose les métriques des conteneurs Docker (CPU, mémoire, réseau par conteneur)
- Node Exporter expose les métriques du système hôte (CPU, disque, mémoire totale)
- Explorez les métriques disponibles dans Prometheus avant de créer vos dashboards

#### Livrables partie 1

- [ ] Prometheus accessible et scrape toutes les cibles
- [ ] Grafana accessible avec Prometheus comme datasource
- [ ] cAdvisor et Node Exporter déployés et fonctionnels
- [ ] Dashboard USE avec au moins 6 panneaux (2 par ressource)
- [ ] Dashboard RED avec au moins 3 panneaux
- [ ] Captures d'écran des dashboards dans le rapport

---

### Partie 2 — Centralisation des logs avec la stack ELK

Centralisez tous les logs de MedAssist avec Elasticsearch, Kibana et Filebeat.

#### Ce que vous devez réaliser

1. Déployer **Elasticsearch** et **Kibana** dans le `docker-compose.yml`
2. Déployer **Filebeat** pour collecter les logs de tous les conteneurs Docker
3. Créer un **dashboard Kibana** pour l'analyse des logs applicatifs avec au moins 5 visualisations pertinentes (pensez : erreurs dans le temps, endpoints les plus sollicités, distribution des temps de réponse, erreurs par service, logs en temps réel)
4. Configurer une **alerte Kibana** qui se déclenche quand le taux d'erreurs HTTP 5xx dépasse un seuil sur une fenêtre glissante

#### Indices

- L'API produit des logs JSON structurés avec les champs : `method`, `endpoint`, `status`, `duration`, `remote_addr`
- Filebeat peut collecter les logs Docker et les envoyer directement à Elasticsearch
- Pensez à ajouter les métadonnées Docker aux logs pour pouvoir filtrer par conteneur
- Pour tester votre alerte, générez du trafic sur `/api/payment` qui a un taux d'erreur naturel de ~5%

#### Livrables partie 2

- [ ] Elasticsearch et Kibana accessibles
- [ ] Filebeat collectant les logs de tous les conteneurs
- [ ] Dashboard Kibana avec au moins 5 visualisations
- [ ] Alerte Kibana configurée et testée
- [ ] Captures d'écran dans le rapport

---

### Partie 3 — Monitoring des sauvegardes

Mettez en place un monitoring complet des sauvegardes MySQL avec des alertes sur la conformité RPO.

#### Ce que vous devez réaliser

1. Déployer **Pushgateway** et le configurer comme cible Prometheus
2. Écrire un **script de sauvegarde** (`backup/backup.sh`) qui :
   - Exécute un `mysqldump` de la base de données
   - Mesure le temps d'exécution, la taille du fichier et le statut (succès/échec)
   - Pousse ces métriques vers Pushgateway
3. Configurer des **règles d'alerte Prometheus** pour détecter :
   - Un échec de sauvegarde
   - Un dépassement du RPO (dernière sauvegarde trop ancienne)
   - Une anomalie de taille de sauvegarde
4. Créer un **dashboard Grafana** dédié au monitoring des sauvegardes (statut, durée, taille, conformité RPO)
5. **Tester les alertes** en simulant un échec (par exemple en arrêtant MySQL avant de lancer le backup)

#### Indices

- Pushgateway permet de pousser des métriques depuis des jobs batch (comme un script de backup)
- Pensez à `honor_labels: true` dans la configuration Prometheus pour Pushgateway
- La fonction `time()` de PromQL retourne le timestamp actuel — utile pour calculer le temps écoulé depuis la dernière sauvegarde
- Le RPO cible pour MedAssist est de 30 minutes (données médicales sensibles)

#### Livrables partie 3

- [ ] Pushgateway déployé et scrappé par Prometheus
- [ ] Script de sauvegarde fonctionnel qui pousse des métriques
- [ ] Au moins 3 règles d'alerte pour les sauvegardes
- [ ] Dashboard Grafana dédié aux sauvegardes (5 panneaux minimum)
- [ ] Test d'échec réalisé avec capture d'écran de l'alerte

---

### Partie 4 — Monitoring de la haute disponibilité et simulation PCA/PRA

Mettez en place le monitoring de la haute disponibilité et simulez des scénarios d'incident.

#### Ce que vous devez réaliser

1. Scaler l'API à **3 replicas** derrière un load balancer **HAProxy**
2. Configurer HAProxy avec des health checks et une page de statistiques
3. Créer un **dashboard Grafana** pour monitorer la santé des backends (nombre d'instances actives, basculements, santé individuelle)
4. **Simuler une panne partielle** (arrêter 1 replica) et mesurer le **MTTD** (Mean Time To Detect)
5. **Simuler une panne totale** (arrêter API + MySQL + Redis), documenter la cascade d'alertes, puis restaurer le service et valider la reprise via le monitoring

#### Ce que vous devez documenter

- **MTTD** : combien de temps entre l'arrêt d'un composant et le déclenchement de l'alerte ?
- **Impact utilisateur** : le service est-il resté disponible pendant la panne partielle ?
- **Timeline d'incident** : pour la panne totale, créez une timeline complète (heures, événements, alertes déclenchées, actions, restauration)

#### Indices

- HAProxy propose une page de statistiques intégrée qui expose aussi des métriques
- `docker compose up -d --scale api=3` permet de scaler un service
- Lors de la restauration après panne totale, l'ordre de redémarrage des services a de l'importance (pensez aux dépendances)

#### Livrables partie 4

- [ ] API scalée à 3 replicas derrière HAProxy
- [ ] Page de stats HAProxy accessible
- [ ] Dashboard HA dans Grafana
- [ ] Mesure du MTTD documentée pour la panne partielle
- [ ] Timeline complète de l'incident de panne totale
- [ ] Validation de la restauration via le monitoring

---

### Partie 5 — Stratégie d'alerting et plan de réponse aux incidents

Définissez et implémentez une stratégie d'alerting complète avec des procédures de réponse.

#### Ce que vous devez réaliser

1. Définir une **stratégie d'alerting à 4 niveaux de priorité** (P1 à P4) adaptée au contexte médical de MedAssist
2. Déployer **Alertmanager** et le configurer avec un routage par sévérité (chaque niveau de priorité doit être routé vers un receiver différent)
3. Écrire au moins **8 règles d'alerte** dans Prometheus couvrant les 4 niveaux de priorité
4. Rédiger **3 runbooks** (procédures de réponse) pour les alertes les plus critiques. Chaque runbook doit contenir : description de l'alerte, impact sur les patients/médecins, étapes de diagnostic, étapes de résolution, procédure d'escalade, checklist post-mortem
5. **Tester chaque niveau d'alerte** en simulant les conditions de déclenchement et vérifier le routage dans Alertmanager

#### Indices

- Alertmanager supporte le routage par labels (`severity`), le grouping, l'inhibition et le silencing
- En l'absence de vrais services de notification (Slack, PagerDuty, etc.), vous pouvez utiliser le webhook `/api/webhook/alert` de l'API qui logue les alertes reçues
- Pensez à des alertes pour : disponibilité des services, taux d'erreurs, latence, sauvegardes, ressources système, haute disponibilité
- Le contexte médical implique des exigences plus strictes (données de santé, disponibilité critique pour les consultations en cours)

#### Livrables partie 5

- [ ] Alertmanager déployé et accessible
- [ ] Configuration Alertmanager avec routage P1-P4
- [ ] Au moins 8 règles d'alerte couvrant les 4 niveaux
- [ ] 3 runbooks détaillés pour les alertes critiques
- [ ] Test de chaque niveau documenté avec captures d'écran

---

### Partie 6 — Rapport final

Rédigez un **rapport de monitoring professionnel** qui sera le livrable principal de ce projet.

#### Contenu attendu du rapport

1. **Schéma d'architecture** : diagramme montrant tous les composants de monitoring déployés et leurs interactions
2. **Définition des SLI/SLO** : pour chaque service (API, base de données, sauvegardes), définissez des indicateurs de niveau de service (SLI) et des objectifs (SLO) adaptés au contexte médical. Justifiez vos choix.
3. **Stratégie de sauvegarde** : fréquence, RPO/RTO, procédure de restauration
4. **Procédure de réponse aux incidents** : matrice d'escalade, runbooks, procédure de communication (interne et vers les patients)
5. **Recommandations d'amélioration** : quelles améliorations proposez-vous ? Quels outils supplémentaires seraient utiles ? Comment améliorer la résilience ?


### Bonus

- Automatisation du déploiement avec un Makefile ou des scripts
- Dashboards supplémentaires pertinents (ex : dashboard SLO avec error budget)
- Intégration d'outils supplémentaires (Jaeger pour le tracing, Loki, etc.)
- Tests de charge avec résultats analysés dans le monitoring
- Utilisation de provisioning Grafana (dashboards as code)

--- 

## Modalités de rendu

### Contenu du dépôt Git à rendre

```
.
├── docker-compose.yml          # Fichier complet avec tous les services
├── prometheus/
│   ├── prometheus.yml          # Configuration Prometheus
│   └── alert_rules.yml         # Règles d'alerte
├── alertmanager/
│   └── alertmanager.yml        # Configuration Alertmanager
├── grafana/                    # Provisioning Grafana (optionnel)
├── filebeat/
│   └── filebeat.yml            # Configuration Filebeat
├── haproxy/
│   └── haproxy.cfg             # Configuration HAProxy
├── backup/
│   └── backup.sh               # Script de sauvegarde
├── rapport.md (ou rapport.pdf) # Rapport final
└── screenshots/                # Captures d'écran organisées par partie
    ├── partie1/
    ├── partie2/
    ├── partie3/
    ├── partie4/
    └── partie5/
```