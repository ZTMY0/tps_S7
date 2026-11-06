#!/bin/bash
# Build order matters: each step depends on the one before. Run as oracle on the VM.
# Prerequisites (manual, see reports/seance2.md): tablespaces, ARCHIVELOG, TDE wallet open.
# Required env: TNS_ADMIN, VM_IP, ADMIN_CLIENT_IP  (placeholders in config/sqlnet.ora)
set -euo pipefail
cd "$(dirname "$0")"
: "${TNS_ADMIN:?set TNS_ADMIN}" "${VM_IP:?set VM_IP}" "${ADMIN_CLIENT_IP:?set ADMIN_CLIENT_IP}"

sqlplus / as sysdba @sql/02_tp2_access_control.sql
sqlplus / as sysdba @sql/03_tp3_hardening_monitoring.sql

# Install the real network config (replaces files; no appending, so no duplicated keys)
ts=$(date +%Y%m%d%H%M%S)
for f in sqlnet.ora listener.ora tnsnames.ora; do
  [ -f "$TNS_ADMIN/$f" ] && cp "$TNS_ADMIN/$f" "$TNS_ADMIN/$f.bak.$ts"
done
sed -e "s/<VM_IP>/$VM_IP/g" -e "s/<ADMIN_CLIENT_IP>/$ADMIN_CLIENT_IP/g" config/sqlnet.ora > "$TNS_ADMIN/sqlnet.ora"
cp config/listener.ora config/tnsnames.ora "$TNS_ADMIN/"
lsnrctl stop; lsnrctl start

# sqlnet.ora has no SQLNET.AUTHENTICATION_SERVICES line, so OS authentication ("rman target /") still works.
bash scripts/03b_tp3_rman_backup.sh
echo "TP4: run sql/04a, then as account_mgr_paris_01 the two queries listed in sql/04b, then 04b, then 04c."
