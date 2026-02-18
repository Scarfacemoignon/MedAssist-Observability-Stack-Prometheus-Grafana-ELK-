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
