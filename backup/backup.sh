#!/usr/bin/env bash
set -euo pipefail

# ---- Config
JOB="mysql_backup"
INSTANCE="medassist"
PUSHGATEWAY_URL="http://localhost:9091"   # depuis ton hôte/WSL
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/dumps"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_FILE="${BACKUP_DIR}/medassist_${TS}.sql"

mkdir -p "$BACKUP_DIR"

START_EPOCH="$(date +%s)"
STATUS=1

# ---- Dump MySQL via conteneur mysql (pas besoin d'avoir mysqldump sur Windows)
set +e
docker exec medassist-mysql sh -lc 'mysqldump -uroot -proot medassist' > "$OUT_FILE"
RC=$?
set -e

END_EPOCH="$(date +%s)"
DURATION_SEC=$((END_EPOCH - START_EPOCH))

if [ $RC -eq 0 ]; then
  STATUS=0
  SIZE_BYTES="$(wc -c < "$OUT_FILE" | tr -d ' ')"
else
  STATUS=1
  SIZE_BYTES=0
  rm -f "$OUT_FILE" || true
fi

# ---- Push metrics to Pushgateway (text format)
# backup_last_success_timestamp = timestamp of last SUCCESS backup (epoch seconds)
# backup_last_run_timestamp     = timestamp of last attempt (success or fail)
cat <<EOF | curl -s --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"
# TYPE backup_last_run_timestamp gauge
backup_last_run_timestamp ${END_EPOCH}
# TYPE backup_duration_seconds gauge
backup_duration_seconds ${DURATION_SEC}
# TYPE backup_size_bytes gauge
backup_size_bytes ${SIZE_BYTES}
# TYPE backup_status gauge
backup_status ${STATUS}
EOF

if [ $STATUS -eq 0 ]; then
  cat <<EOF | curl -s --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/${JOB}/instance/${INSTANCE}"
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp ${END_EPOCH}
EOF
fi

echo "Backup done. status=${STATUS} duration=${DURATION_SEC}s size=${SIZE_BYTES}B file=${OUT_FILE}"