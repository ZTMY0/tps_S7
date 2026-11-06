#!/bin/bash
# TP3 part 5: encrypted RMAN backup (workaround that worked on 2026-10-28, see
# evidence/logs/tp3_rman2.log.clean.txt). The passphrase is read from the terminal, never stored.
#
# History: the first attempt (evidence/logs/tp3_rman.log.clean.txt) was
#   BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG
#     FORMAT '/u01/app/oracle/backup/secbank/full_%d_%T_%s_%p.bkp' TAG 'FULL_CHIFFRE';
# The archivelog part succeeded; the SECBANKPDB datafiles failed with
#   ORA-19836: cannot use passphrase encryption for this backup
# (root cause not established in the logs). This script reproduces the second run.
#
# The second run did NOT cover ACCOUNTS_DATA / TRANSACTIONS_DATA. They were backed up on
# 2026-11-06 (evidence/logs/tp3_rman3_20261106.log.clean.txt) and are included below.
set -euo pipefail
read -rsp "Backup encryption passphrase: " BP; echo
rman target / <<RMAN
CONFIGURE ENCRYPTION FOR DATABASE ON;
CONFIGURE ENCRYPTION ALGORITHM 'AES256';
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 30 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
SET ENCRYPTION ON IDENTIFIED BY "$BP" ONLY;
BACKUP AS COMPRESSED BACKUPSET
  TABLESPACE SECBANKPDB:SYSTEM, SECBANKPDB:SYSAUX, SECBANKPDB:UNDOTBS1, SECBANKPDB:USERS, SECBANKPDB:AUDIT_DATA
  TAG 'SECBANKPDB_NO_TDE';
BACKUP AS COMPRESSED BACKUPSET
  TABLESPACE SECBANKPDB:ACCOUNTS_DATA, SECBANKPDB:TRANSACTIONS_DATA TAG 'SECBANKPDB_DATA';
BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL NOT BACKED UP TAG 'ARCH_CHIFFRE';
SET DECRYPTION IDENTIFIED BY "$BP";
RESTORE TABLESPACE SECBANKPDB:USERS, SECBANKPDB:AUDIT_DATA, SECBANKPDB:ACCOUNTS_DATA, SECBANKPDB:TRANSACTIONS_DATA VALIDATE;
LIST BACKUP SUMMARY;
RMAN
unset BP
