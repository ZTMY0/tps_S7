-- ============================================================
-- verify_tp2.sql : Séance 2 - Gestion des accès bancaires et chiffrement
-- Read-only checks. Run as SYSDBA. Output goes to verify_tp2.log
-- ============================================================
SET LINESIZE 200 PAGESIZE 100 TRIMSPOOL ON FEEDBACK ON VERIFY OFF
SET SERVEROUTPUT ON
SPOOL verify_tp2.log
ALTER SESSION SET CONTAINER = SECBANKPDB;
SHOW CON_NAME
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS run_at FROM dual;

PROMPT
PROMPT === Prerequis : mode ARCHIVELOG et tablespaces ===
COLUMN name FORMAT A20
COLUMN log_mode FORMAT A14
SELECT name, log_mode FROM v$database;
COLUMN tablespace_name FORMAT A20
SELECT tablespace_name, bigfile, encrypted, status
  FROM dba_tablespaces
 WHERE tablespace_name IN ('ACCOUNTS_DATA','TRANSACTIONS_DATA','AUDIT_DATA')
 ORDER BY tablespace_name;

PROMPT
PROMPT === Partie 1 : tables et donnees ===
COLUMN table_name FORMAT A22
SELECT table_name, tablespace_name FROM dba_tables
 WHERE owner = 'BANK_OWNER' ORDER BY table_name;
SELECT 'CUSTOMERS' AS t, COUNT(*) AS n FROM bank_owner.customers
UNION ALL SELECT 'ACCOUNTS', COUNT(*) FROM bank_owner.accounts
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM bank_owner.transactions
UNION ALL SELECT 'USER_BRANCH_MAPPING', COUNT(*) FROM bank_owner.user_branch_mapping;
COLUMN column_name FORMAT A18
SELECT table_name, column_name, data_type, data_length FROM dba_tab_columns
 WHERE owner='BANK_OWNER' AND ((table_name='CUSTOMERS' AND column_name='SSN')
    OR (table_name='ACCOUNTS' AND column_name='ACCOUNT_NUMBER'));

PROMPT
PROMPT === Partie 2 : hierarchie de roles ===
COLUMN role FORMAT A16
COLUMN granted_role FORMAT A22
SELECT role, granted_role FROM role_role_privs WHERE role LIKE 'BANK_%' ORDER BY role, granted_role;
COLUMN grantee FORMAT A16
COLUMN privilege FORMAT A22
COLUMN table_name FORMAT A18
SELECT grantee, privilege, table_name FROM dba_tab_privs
 WHERE grantee LIKE 'BANK_%' ORDER BY grantee, table_name, privilege;
SELECT grantee, privilege FROM dba_sys_privs WHERE grantee LIKE 'BANK_%' ORDER BY grantee, privilege;

PROMPT
PROMPT === Partie 3 : profil et utilisateurs applicatifs ===
COLUMN resource_name FORMAT A24
COLUMN limit FORMAT A14
SELECT resource_name, limit FROM dba_profiles
 WHERE profile = 'SECBANK_USER_PROFILE' ORDER BY resource_name;
COLUMN username FORMAT A22
COLUMN profile FORMAT A22
COLUMN account_status FORMAT A18
SELECT username, profile, account_status FROM dba_users
 WHERE profile = 'SECBANK_USER_PROFILE' ORDER BY username;
SELECT grantee, granted_role, default_role FROM dba_role_privs
 WHERE grantee IN ('ADVISOR_PARIS_01','ACCOUNT_MGR_PARIS_01','ADVISOR_LYON_03','SECURITY_AUDITOR')
 ORDER BY grantee;
COLUMN branch_id FORMAT A12
SELECT username, branch_id, role_type FROM bank_owner.user_branch_mapping ORDER BY branch_id, username;

PROMPT
PROMPT === Partie 4 : TDE (wallet, tablespaces, colonne SSN) ===
COLUMN wrl_parameter FORMAT A45
COLUMN status FORMAT A20
SELECT con_id, wrl_parameter, status, wallet_type FROM v$encryption_wallet;
COLUMN name FORMAT A20
SELECT t.name, e.encryptedts, e.encryptionalg
  FROM v$tablespace t JOIN v$encrypted_tablespaces e ON t.ts# = e.ts#
 ORDER BY t.name;
SELECT owner, table_name, column_name, encryption_alg FROM dba_encrypted_columns
 WHERE owner = 'BANK_OWNER';

PROMPT
PROMPT === Partie 5 : VPD ===
COLUMN policy_name FORMAT A32
COLUMN object_name FORMAT A16
SELECT object_name, policy_name, sel, ins, upd, del, enable FROM dba_policies
 WHERE object_owner = 'BANK_OWNER' ORDER BY object_name;
SELECT object_name, object_type, status FROM dba_objects
 WHERE owner='BANK_OWNER' AND object_name='BRANCH_SECURITY_POLICY';
SELECT grantee, privilege FROM dba_sys_privs WHERE privilege = 'EXEMPT ACCESS POLICY' ORDER BY grantee;

PROMPT
PROMPT === Partie 6 : audit unifie ===
COLUMN policy_name FORMAT A32
SELECT policy_name, enabled_option FROM audit_unified_enabled_policies
 WHERE policy_name LIKE 'SECBANK%' ORDER BY policy_name;
COLUMN dbusername FORMAT A22
COLUMN action_name FORMAT A12
COLUMN object_name FORMAT A14
SELECT dbusername, action_name, object_name, return_code, COUNT(*) AS nb
  FROM unified_audit_trail
 WHERE object_schema = 'BANK_OWNER'
 GROUP BY dbusername, action_name, object_name, return_code
 ORDER BY dbusername, action_name;
SELECT dbusername, userhost, COUNT(*) AS nb_echecs, MAX(event_timestamp) AS derniere_tentative
  FROM unified_audit_trail
 WHERE action_name = 'LOGON' AND return_code != 0
 GROUP BY dbusername, userhost ORDER BY nb_echecs DESC;

SPOOL OFF
EXIT
