# TP Monitoring

[Enoncé](https://www.notion.so/Enonc-30a10ddc2fe880858392c1ff63cf869b?pvs=21)

## **Lancement de l'application**

```
docker compose up -d
docker compose ps
curl http://localhost:5000/health
```

## **Endpoints disponibles**

| **Endpoint** | **Méthode** | **Description** |
| --- | --- | --- |
| `/health` | GET | Health check (état MySQL + Redis) |
| `/api/doctors` | GET | Liste des médecins disponibles |
| `/api/consultations` | GET / POST | Liste et prise de rendez-vous |
| `/api/payment` | GET / POST | Traitement des paiements (~5% d'erreurs) |
| `/metrics` | GET | Métriques Prometheus |

## **Travail demandé**

> Votre mission se décompose en **6 parties**. Chaque partie doit être réalisée et documentée. Vous devez rendre un dépôt Git contenant l'ensemble de vos fichiers de configuration et un rapport.
> 

# **Partie 1 — Monitoring infrastructure avec Prometheus et Grafana**

Mettez en place le monitoring de l'infrastructure MedAssist avec Prometheus et Grafana.

1.  Ajouter **Prometheus**, **Grafana**, **cAdvisor** et **Node Exporter** au `docker-compose.yml`

Dans le `docker-compose.yml`,  On ajoute ces services : 

## Prometheus

`prometheus:
image: prom/prometheus:latest
container_name: medassist-prometheus
ports:
- "9090:9090"
volumes:
- ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
- prometheus_data:/prometheus
command:
- "--config.file=/etc/prometheus/prometheus.yml"
- "--storage.tsdb.path=/prometheus"
networks:
- medassist-network
restart: unless-stopped`

## Grafana

`grafana:
image: grafana/grafana:latest
container_name: medassist-grafana
ports:
- "3000:3000"
environment:
- GF_SECURITY_ADMIN_USER=admin
- GF_SECURITY_ADMIN_PASSWORD=admin
volumes:
- grafana_data:/var/lib/grafana
depends_on:
- prometheus
networks:
- medassist-network
restart: unless-stopped`

## cAdvisor (métriques conteneurs Docker)

`cadvisor:
image: [gcr.io/cadvisor/cadvisor:latest](http://gcr.io/cadvisor/cadvisor:latest)
container_name: medassist-cadvisor
ports:
- "8080:8080"
volumes:
- /:/rootfs:ro
- /var/run:/var/run:ro
- /sys:/sys:ro
- /var/lib/docker/:/var/lib/docker:ro
- /dev/disk/:/dev/disk:ro
privileged: true
networks:
- medassist-network
restart: unless-stopped`

## Node Exporter (métriques OS hôte)

`node-exporter:
image: prom/node-exporter:latest
container_name: medassist-node-exporter
ports:
- "9100:9100"
volumes:
- /proc:/host/proc:ro
- /sys:/host/sys:ro
- /:/rootfs:ro
command:
- "--path.procfs=/host/proc"
- "--path.sysfs=/host/sys"
- "--path.rootfs=/rootfs"
networks:
- medassist-network
restart: unless-stopped
Et dans la section volumes: (en bas), ajoute :`

`prometheus_data:
name: medassist-prometheus-data
grafana_data:
name: medassist-grafana-data`

1. Crée le fichier `prometheus/prometheus.yml`

Crée le dossier `prometheus/` puis ce fichier :

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # API Flask (métriques Prometheus sur /metrics)
  - job_name: "medassist-api"
    metrics_path: /metrics
    static_configs:
      - targets: ["api:5000"]

  # cAdvisor (conteneurs)
  - job_name: "cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]

  # Node Exporter (hôte)
  - job_name: "node-exporter"
    static_configs:
      - targets: ["node-exporter:9100"]
```

## 3) Démarre et vérifie

Depuis la racine du projet`/` :

```bash
docker compose up -d
docker compose ps
```

### Vérifs rapides

- Prometheus : http://localhost:9090
    
    → **Status > Targets** : tu dois voir `medassist-api`, `cadvisor`, `node-exporter` en **UP**
    
- Grafana : http://localhost:3000 (admin / admin)
- cAdvisor : http://localhost:8080
- Node exporter : http://localhost:9100/metrics

## 4) Création des dashboard Grafana

## Étape 1.1 — Ajoutons Prometheus comme datasource Grafana

1. Va sur **http://localhost:3000** (admin / admin)
2. **Connections → Data sources → Add data source → Prometheus**
3. URL :**`http://prometheus:9090`**
4. **Save & Test** → on doit avoir “Data source is working”.

## Étape 1.2 — Vérifions que Prometheus scrape bien

Dans Prometheus (http://localhost:9090) → **Status → Targets** :

Tu dois voir `medassist-api`, `cadvisor`, `node-exporter` en **UP**.

![image.png](images/image.png)

## Étape 2 — Créons Dashboard Grafana appliquant la **méthode USE** (Utilisation, Saturation, Erreurs) pour les ressources infrastructure (CPU, mémoire, réseau)

### Dashboard 1 : USE (infra) — 6 panneaux mini

Objectif : **U**tilisation, **S**aturation, **E**rreurs pour **CPU, Mémoire, Réseau** (2 panneaux par ressource = 6 panneaux).

Crée un dashboard Grafana : **Dashboards → New → New dashboard → Add visualization**

### ✅ CPU (2 panneaux)

**Panel 1 — CPU Utilisation (%) (Node Exporter)**

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Panel 2 — CPU Saturation (Load 1m)**

```
node_load1
```

> Si tu veux la version “relative” au nb de CPU (plus parlant) :
> 

```
node_load1 / count by(instance) (node_cpu_seconds_total{mode="idle"})
```

---

### ✅ Mémoire (2 panneaux)

**Panel 3 — Mémoire utilisée (%)**

```
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))
```

**Panel 4 — Saturation mémoire (swap in/out)**

```
rate(node_vmstat_pswpin[5m]) + rate(node_vmstat_pswpout[5m])
```

> Si pas de swap, ça restera proche de 0 (et c’est OK).
> 

---

### ✅ Réseau (2 panneaux)

**Panel 5 — RX (octets/s)**

```
sum by (instance) (rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*"}[5m]))
```

**Panel 6 — TX (octets/s)**

```
sum by (instance) (rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*"}[5m]))
```

> Bonus “Erreurs réseau” (optionnel en 7e panel si tu veux)
> 

```
sum by(instance) (rate(node_network_receive_errs_total{device!~"lo|docker.*|veth.*"}[5m]))
+
sum by(instance) (rate(node_network_transmit_errs_total{device!~"lo|docker.*|veth.*"}[5m]))
```

![image.png](images/image%201.png)

## Dashboad : Creation d’un dashboard Grafana appliquant la **méthode RED** (Rate, Errors, Duration) pour l'API

Nos métriques :

- `flask_http_request_created` → compteur de requêtes
- `flask_http_request_duration_seconds_bucket` → histogramme de latence

### 🔹 Rate (RPS)

Voir combien de requêtes ton API reçoit par seconde.

Code

`sum(rate(flask_http_request_created[5m]))`

### 🔹 Errors (5xx)

Tu as un label `status`, donc on peut filtrer les erreurs facilement.

Code

`sum(rate(flask_http_request_created{status=~"5.."}[5m]))`

### 🔹 Duration (p95)

Tu as un histogramme → parfait pour un quantile.

Code

`histogram_quantile(
  0.95,
  sum by (le) (rate(flask_http_request_duration_seconds_bucket[5m]))
)`

### 🔹 RPS par endpoint

Code

`sum by (endpoint) (rate(flask_http_request_created[5m]))`

### 🔹 Latence p99

Code

`histogram_quantile(
  0.99,
  sum by (le) (rate(flask_http_request_duration_seconds_bucket[5m]))
)`

On a ce résultat : 

![image.png](images/image%202.png)

# **Partie 2 — Centralisation des logs avec la stack ELK**

Étape 2.1 — Ajouter Elasticsearch + Kibana + Filebeat au `docker-compose.yml`

Ajoutons ces 3 services (et les volumes) à ton `docker-compose.yml`.

### Elasticsearch

`elasticsearch:
image: [docker.elastic.co/elasticsearch/elasticsearch:8.13.4](http://docker.elastic.co/elasticsearch/elasticsearch:8.13.4)
container_name: medassist-elasticsearch
environment:
- discovery.type=single-node
- xpack.security.enabled=false
- ES_JAVA_OPTS=-Xms512m -Xmx512m
ports:
- "9200:9200"
volumes:
- es_data:/usr/share/elasticsearch/data
networks:
- medassist-network
restart: unless-stopped`

### Kibana

`kibana:
image: [docker.elastic.co/kibana/kibana:8.13.4](http://docker.elastic.co/kibana/kibana:8.13.4)
container_name: medassist-kibana
environment:
- ELASTICSEARCH_HOSTS=http://elasticsearch:9200
ports:
- "5601:5601"
depends_on:
- elasticsearch
networks:
- medassist-network
restart: unless-stopped`

### Filebeat (collecte logs Docker)

`filebeat:
image: [docker.elastic.co/beats/filebeat:8.13.4](http://docker.elastic.co/beats/filebeat:8.13.4)
container_name: medassist-filebeat
user: root
volumes:
- ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
- /var/lib/docker/containers:/var/lib/docker/containers:ro
- /var/run/docker.sock:/var/run/docker.sock:ro
depends_on:
- elasticsearch
networks:
- medassist-network
restart: unless-stopped`

### Étape 2.4 — Démarrer et vérifier

```bash
docker compose up -d
docker compose ps
```

Vérifs :

- Elasticsearch : http://localhost:9200
    
    Tu dois voir un JSON avec `cluster_name` etc.
    
- Kibana : http://localhost:5601
- Dans Elasticsearch, tu peux vérifier l’index :
    
    ```bash
    curl -s http://localhost:9200/_cat/indices?v | grep medassist
    ```
    

Elasticsearch :

![image.png](images/image%203.png)

ElasticSearch : 

![image.png](images/image%204.png)

### Etape 2 : Déployons File beat pour la collecte des Logs

Il faut créer un fichier `filebeat/filebeat.yml` 

```yaml
filebeat.inputs:
  - type: filestream
    id: docker-containers
    enabled: true
    paths:
      - /var/lib/docker/containers/*/*.log

processors:
  # Parse le JSON si tes logs applicatifs sont en JSON dans "message"
  - decode_json_fields:
      fields: ["message"]
      target: ""
      overwrite_keys: true
      add_error_key: true

  # Ajoute les métadonnées Docker (container.name, image, labels, etc.)
  - add_docker_metadata:
      host: "unix:///var/run/docker.sock"

  - add_tags:
      tags: ["medassist"]

output.elasticsearch:
  hosts: ["http://elasticsearch:9200"]
  index: "medassist-logs-%{+yyyy.MM.dd}"

setup.template.enabled: true
setup.template.name: "medassist-logs"
setup.template.pattern: "medassist-logs-*"

logging.level: info
```

`docker compose restart filebeat`
Une fois redemarré filebeat, on fait ce qui suit :

Kibana : Data View + Discover

Dans Kibana (http://localhost:5601) :

- **Stack Management → Data Views → Create data view**
    - `medassist-logs-*`
    - time field : `@timestamp`
- **Discover** : tu dois voir les logs

![image.png](images/image%205.png)

### Etape 3 : Créer un **dashboard Kibana** pour l'analyse des logs applicatifs avec au moins 5 visualisations pertinentes

### 1️⃣ **Erreurs HTTP 5xx dans le temps**

**Type :** Line chart (Lens)

### Champs :

- `status`
- `@timestamp`

![image.png](images/image%206.png)

### 2️⃣ **Endpoints les plus sollicités**

**Type :** Bar chart horizontal

### Champs :

- `endpoint`

![image.png](images/image%207.png)

### 3️⃣ **Distribution des temps de réponse**

**Type :** Histogram

### Champs :

- `duration`

![image.png](images/image%208.png)

### 4️⃣ **Erreurs par service / conteneur**

**Type :** Pie chart

### Champs :

- `container.name`
- `count`

![image.png](images/image%209.png)

### 5️⃣ **Logs en temps réel**

**Type :** Data Table 

Pour des probleme de ressources RAM, je vais utiliser  ceci :

![image.png](images/image%2010.png)

### Etape 4 : Configurer et TESTER l’alerte Kibana

Créer la règle P2 - Erreurs 5xx sur /api/payment : 

![image.png](images/image%2011.png)

Grace à cette commande, on va generer des erreur : 

> `for ($i=1; $i -le 2000; $i++) {Invoke-WebRequest -Uri "<http://localhost:5000/api/payment>" -UseBasicParsing -ErrorAction SilentlyContinue | Out-Null
}`
> 

Et on a une alerte : 

![image.png](images/image%2012.png)

# **Partie 3 : Monitoring des sauvegardes**

### Étape 3.1 : Ajoutons Pushgateway au `docker-compose.yml`

`pushgateway:
image: prom/pushgateway:latest
container_name: medassist-pushgateway
ports:
- "9091:9091"
networks:
- medassist-network
restart: unless-stopped`

Puis redémarrons:

```bash
docker compose up -d
docker compose ps
```

Vérifie : http://localhost:9091

![image.png](images/image%2013.png)

Étape 3.2 : Scraper Pushgateway dans Prometheus

Dans `prometheus/prometheus.yml`, on ajoute un job :

  

```yaml
- job_name: "pushgateway"
	honor_labels: true
	static_configs:`
		 - targets: ["pushgateway:9091"]
```

`docker compose restart prometheus`
Vérifie dans Prometheus → Status → Targets : pushgateway doit être UP.

![image.png](images/image%2014.png)

Étape 3.3 — Créons le script `backup/backup.sh`

Créons un dossier `backup/` puis fichier `backup/backup.sh` :

Pour des raisons de distributions, j’ai converti mon `backup/backup.sh` en `backup/backup.ps1`

```powershell
# ============================================
# MedAssist - MySQL Backup + Pushgateway (Windows-safe)
# Dump inside container + docker cp
# ============================================
# Run:
#   powershell -ExecutionPolicy Bypass -File .\backup\backup.ps1
# ============================================

$ErrorActionPreference = "Stop"

# ----- Configuration -----
$Job          = "mysql_backup"
$Instance     = "medassist"
$Pushgateway  = "http://localhost:9091"
$BackupDir    = Join-Path $PSScriptRoot "dumps"

$MysqlContainer = "medassist-mysql"
$MysqlUser      = "root"
$MysqlPassword  = "medassist"
$MysqlDatabase  = "medassist"
# --------------------------

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outFile = Join-Path $BackupDir ("medassist_{0}.sql" -f $ts)

$tmpSql = "/tmp/medassist_$ts.sql"
$tmpErr = "/tmp/medassist_$ts.err"

$startEpoch = [int][double]::Parse((Get-Date -UFormat %s))
$status = 1
$sizeBytes = 0
$durationSec = 0

try {
    Write-Host "Starting MySQL backup (container dump + docker cp)..."

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Vérifie conteneur présent
    $exists = docker ps --format "{{.Names}}" | Select-String -SimpleMatch $MysqlContainer
    if (-not $exists) { throw "MySQL container '$MysqlContainer' not found. Check: docker compose ps" }

    # Dump DANS le conteneur (stdout->tmpSql, stderr->tmpErr)
    docker exec $MysqlContainer sh -lc "rm -f $tmpSql $tmpErr; mysqldump -u$MysqlUser -p$MysqlPassword $MysqlDatabase > $tmpSql 2> $tmpErr"
    if ($LASTEXITCODE -ne 0) {
        $err = docker exec $MysqlContainer sh -lc "cat $tmpErr 2>/dev/null || true"
        throw "mysqldump failed (exitcode=$LASTEXITCODE). stderr: $err"
    }

    # Copie vers Windows
    docker cp "${MysqlContainer}:$tmpSql" "$outFile"
    if ($LASTEXITCODE -ne 0) { throw "docker cp failed (exitcode=$LASTEXITCODE)." }

    # Taille
    $sizeBytes = (Get-Item $outFile).Length
    if ($sizeBytes -lt 100) {
        $err = docker exec $MysqlContainer sh -lc "cat $tmpErr 2>/dev/null || true"
        throw "Dump file too small ($sizeBytes bytes). stderr: $err"
    }

    # Nettoyage tmp
    docker exec $MysqlContainer sh -lc "rm -f $tmpSql $tmpErr" | Out-Null

    $sw.Stop()
    $durationSec = [int][Math]::Round($sw.Elapsed.TotalSeconds)
    $status = 0

    Write-Host "Backup successful."
}
catch {
    Write-Host "Backup failed!"
    Write-Host $_.Exception.Message
    $status = 1
    if (Test-Path $outFile) { Remove-Item $outFile -Force }
}

$endEpoch = [int][double]::Parse((Get-Date -UFormat %s))
if ($durationSec -eq 0) { $durationSec = [Math]::Max(1, ($endEpoch - $startEpoch)) }

# ----- Pushgateway metrics (LF only) -----
$body = @(
"# TYPE backup_last_run_timestamp gauge",
"backup_last_run_timestamp $endEpoch",
"# TYPE backup_duration_seconds gauge",
"backup_duration_seconds $durationSec",
"# TYPE backup_size_bytes gauge",
"backup_size_bytes $sizeBytes",
"# TYPE backup_status gauge",
"backup_status $status",
""
) -join "`n"
$body = $body -replace "`r",""

Invoke-WebRequest -UseBasicParsing `
  -Uri "$Pushgateway/metrics/job/$Job/instance/$Instance" `
  -Method Post `
  -Body $body `
  -ContentType "text/plain" | Out-Null

if ($status -eq 0) {
    $body2 = @(
    "# TYPE backup_last_success_timestamp gauge",
    "backup_last_success_timestamp $endEpoch",
    ""
    ) -join "`n"
    $body2 = $body2 -replace "`r",""

    Invoke-WebRequest -UseBasicParsing `
      -Uri "$Pushgateway/metrics/job/$Job/instance/$Instance" `
      -Method Post `
      -Body $body2 `
      -ContentType "text/plain" | Out-Null
}

Write-Host ""
Write-Host "======================================="
Write-Host "Backup done."
Write-Host "Status   : $status (0=OK, 1=FAIL)"
Write-Host "Duration : $durationSec seconds"
Write-Host "Size     : $sizeBytes bytes"
Write-Host "File     : $outFile"
Write-Host "======================================="

exit $status

```

`powershell -ExecutionPolicy Bypass -File .\backup\backup.ps1`

Et on a ceci : 

![image.png](images/image%2015.png)

Étape 3.3 : Vérifier Pushgateway + Prometheus

![image.png](images/image%2016.png)

On a la confirmation que promotheus scrape bien.

![image.png](images/image%2017.png)

### Étape 3.4 — Règles d’alertes Prometheus (3 alertes)

Dans `prometheus/alert_rules.yml` on ajoute ce groupe :

```yaml
groups:
  - name: medassist-backups
    rules:
      - alert: MySQLBackupFailed
        expr: backup_status{job="mysql_backup"} == 1
        for: 1m
        labels:
          severity: P1
        annotations:
          summary: "MySQL backup failed"
          description: "Backup script reported failure (backup_status=1)."

      - alert: MySQLBackupRPOExceeded
        expr: (time() - backup_last_success_timestamp{job="mysql_backup"}) > 1800
        for: 2m
        labels:
          severity: P1
        annotations:
          summary: "MySQL backup RPO exceeded (>30min)"
          description: "Last successful backup older than 30 minutes."

      - alert: MySQLBackupSizeAnomaly
        expr: backup_size_bytes{job="mysql_backup"} < 10000
        for: 2m
        labels:
          severity: P2
        annotations:
          summary: "MySQL backup size anomaly"
          description: "Backup size unexpectedly small (<10KB)."
```

Ensuite :  `docker compose restart prometheus`

J’ai mes 03 alertes, qui sont pour le moment inactives : 

![image.png](images/image%2018.png)

### Test  : simuler un échec

Stop MySQL :

```bash
docker compose stop mysql
```

Lançons le backup :

```powershell
powershell-ExecutionPolicy Bypass-File .\backup\backup.ps1
```

On doit avoir : 

![image.png](images/image%2019.png)

Et notre alerte sur promotheurs passe en FIRING.

![image.png](images/image%2020.png)

## Étape 3.5 : Dashboard Grafana Backups

### Panel 1 : *Backup Status*

Afficher si le dernier backup est **successful (1)** ou **failed (0)**.

Code

`backup_status{job="mysql_backup"}`

![image.png](images/image%2021.png)

### Panel 2 : *Backup Duration (seconds)*

Voir combien de temps a duré le dernier backup.

Code

`backup_duration_seconds{job="mysql_backup"}`

![image.png](images/image%2022.png)

### Panel 3 : Backup Size (bytes)

Afficher la taille du dernier backup.

Code

`backup_size_bytes{job="mysql_backup"}`

![image.png](images/image%2023.png)

### Panel 4 : Âge de la dernière sauvegarde successful (seconds)

Afficher depuis combien de temps le dernier backup réussi a eu lieu.

Code

`time() - backup_last_success_timestamp{job="mysql_backup"}`

![image.png](images/image%2024.png)

### Panel 5 : *RPO dépassé (0/1)*

Afficher si le RPO (30 min ici) est dépassé.

Code

`(time() - backup_last_success_timestamp{job="mysql_backup"}) > 1800`

![image.png](images/image%2025.png)

Au total : 

![image.png](images/image%2026.png)

# **Partie 4 — Monitoring de la haute disponibilité et simulation PCA/PRA**

### 1. Scaler l’API à 3 replicas derrière HAProxy

### 1.1. Ajouter HAProxy dans `docker-compose.yml`

```yaml
 # -------------------------------------------------------------------------
  # haproxy
  # -------------------------------------------------------------------------    
  haproxy:
    image: haproxy:2.9
    container_name: medassist-haproxy
    ports:
      - "8088:8088"
      - "8404:8404"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - api
    networks:
      - medassist-network
    restart: unless-stopped

  haproxy-exporter:
    image: prom/haproxy-exporter:latest
    container_name: medassist-haproxy-exporter
    command:
      - "--haproxy.scrape-uri=http://admin:admin@haproxy:8404/stats;csv"
    ports:
      - "9101:9101"
    depends_on:
      - haproxy
    networks:
      - medassist-network
    restart: unless-stopped
```

`docker compose up -d --scale api=3`

### 2. Config HAProxy avec health checks + stats

### 2.1. `haproxy/haproxy.cfg`

```yaml
global
  log stdout format raw local0
  maxconn 4096

defaults
  log global
  mode http
  option httplog
  timeout connect 5s
  timeout client  30s
  timeout server  30s

listen stats
  bind *:8404
  stats enable
  stats uri /stats
  stats refresh 5s
  stats auth admin:admin

frontend fe_api
  bind *:8088
  default_backend be_api

backend be_api
  balance roundrobin
  option httpchk GET /health
  http-check expect status 200
  default-server inter 2s fall 2 rise 2

  # IMPORTANT: en compose "api:5000" peut déjà être load-balancé via DNS
  server api api:5000 check
```

### 2.2. Ajouter la cible dans `prometheus.yml`

```yaml
- job_name: 'haproxy'
	static_configs:
	 - targets: ['haproxy-exporter:9101']
```

`docker compose restart prometheus`

### 2.3 — Démarrer HAProxy

```bash
docker compose up -d
docker compose ps
```

Une fois demarré, sur promotheus on a : 

![image.png](images/image%2027.png)

Puis sur 

Stats HAProxy : [http://localhost:8404/stats](http://localhost:8404/stats) (admin/admin), on a : 

![image.png](images/image%2028.png)

### 3. Dashboard Grafana “HA / API”

![image.png](images/image%2029.png)

### 4. PANNE PARTIELLE — Stop 1 replica API → Mesurer le MTTD

TEST 1 — Panne partielle (1 replica down)

Objectif

- Vérifier que le service reste disponible
- Mesurer le **MTTD (Mean Time To Detect)**
- Observer le dashboard HA

### “Comment je mesure le MTTD ?”

1. notons l’heure exacte : 11h39
2. stop 1 replica :

```
dockerstopmedassist-observability-stack-prometheus-grafana-elk--api-1
```

![image.png](images/image%2030.png)

On a un API en moins.

> **Impact utilisateur :** la panne partielle (arrêt d’un replica API) n’a pas interrompu le service.
> 
> 
> Les requêtes vers `http://localhost:8088/health` sont restées en **HTTP 200**, car HAProxy a continué à router vers les 2 autres instances saines.
> 

```
1..30|% {curl-UseBasicParsing-s-oNUL-w"%{http_code}`n"http://localhost:8088/health }
```

**Timeline panne totale :**

- **T0 (11:39:27)** : arrêt des services `api`, `mysql`, `redis`
- **T0+Xs** : HAProxy détecte `0` backend API disponible (stats HAProxy)
- **T0+Ys** : Alerte “API down / backends down” passe FIRING (Prometheus)
- **T0+Zs** : Alerte “MySQL down” passe FIRING
- **T0+…** : Alerte “Redis down” passe FIRING
- **Action** : redémarrage `mysql` + `redis`
- **T1 (HH:MM:SS)** : MySQL et Redis redeviennent healthy
- **Action** : redémarrage des 3 replicas API
- **T2 (HH:MM:SS)** : HAProxy voit de nouveau 3 backends UP
- **Validation** : `/health` retourne `200 OK` et les dashboards repassent au vert

![image.png](images/image%2031.png)

# **Partie 5 : Stratégie d'alerting et plan de réponse aux incidents**

### 1️⃣ Stratégie d’alerting

### Contexte médical = exigences élevées

MedAssist gère :

- consultations médicales en temps réel
- paiements
- données de santé sensibles

Donc indisponibilité = impact patient immédiat.

### Niveaux de priorité

### 🔴 P1 — Critique (Interruption service)

Impact immédiat sur les patients.

Exemples :

- Tous les backends API down
- MySQL down
- RPO dépassé (données médicales)
- Taux d’erreur API > 20%

Action :

- Intervention immédiate (< 5 min)
- Escalade CTO si > 15 min

### 🟠 P2 — Majeur (Dégradation)

Service partiellement affecté.

Exemples :

- 1 replica API down
- Taux d’erreur paiement > 10%
- Latence API > 2s
- Sauvegarde échouée

Action :

- Intervention < 30 min

### 🟡 P3 — Mineur (Risque futur)

Pas d’impact immédiat.

Exemples :

- CPU > 80%
- Mémoire > 85%
- Disk > 85%

### 🔵 P4 — Informationnel

Monitoring préventif.

Exemples :

- Restart container
- Pic temporaire trafic

## 2️⃣ Alertmanager — configuration complète

On crée :  `alertmanager/alertmanager.yml`

## La suite pour bientot....