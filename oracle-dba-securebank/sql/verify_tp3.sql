-- ============================================================
-- verify_tp3.sql : Séance 3 - Durcissement, monitoring, reponse aux incidents
-- Read-only checks. Run as SYSDBA. Output goes to verify_tp3.log
-- Objects named in the doc: hr_owner, audit_admin, analyst1. If you used
-- different names (e.g. bank_owner), edit them below before running.
-- An ORA-00942 on a query means that object does not exist in your database.
-- ============================================================
SET LINESIZE 200 PAGESIZE 100 TRIMSPOOL ON FEEDBACK ON VERIFY OFF
SPOOL verify_tp3.log
ALTER SESSION SET CONTAINER = SECBANKPDB;
SHOW CON_NAME
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS run_at FROM dual;

PROMPT
PROMPT === Partie 1 : durcissement des comptes ===
COLUMN username FORMAT A24
COLUMN account_status FORMAT A20
SELECT account_status, COUNT(*) AS nb FROM dba_users
 WHERE oracle_maintained = 'Y' GROUP BY account_status ORDER BY account_status;
SELECT username, account_status FROM dba_users
 WHERE username IN ('SCOTT','HR','OE','PM','SH','IX','BI','OUTLN','ANONYMOUS','DBSNMP')
 ORDER BY username;
COLUMN action_type FORMAT A16
COLUMN action_detail FORMAT A60
SELECT TO_CHAR(action_date,'YYYY-MM-DD HH24:MI:SS') AS quand, action_type, action_detail
  FROM audit_mgr.hardening_log ORDER BY action_date;

PROMPT
PROMPT === Partie 1 : packages dangereux (doit etre VIDE) ===
COLUMN table_name FORMAT A22
SELECT table_name FROM dba_tab_privs
 WHERE grantee = 'PUBLIC' AND privilege = 'EXECUTE'
   AND table_name IN ('UTL_FILE','UTL_TCP','UTL_HTTP','UTL_SMTP','DBMS_SQL',
                      'DBMS_SCHEDULER','DBMS_JAVA','DBMS_LDAP');

PROMPT
PROMPT === Partie 3 : procedures (vulnerable, securisee, DBMS_ASSERT) ===
COLUMN owner FORMAT A12
COLUMN object_name FORMAT A30
SELECT owner, object_name, object_type, status FROM dba_objects
 WHERE object_name IN ('SEARCH_EMPLOYEE_VULNERABLE','SEARCH_EMPLOYEE_SECURE','COUNT_ROWS_SECURE')
 ORDER BY object_name;

PROMPT
PROMPT === Partie 4 : audit, alertes, job de detection ===
COLUMN policy_name FORMAT A24
COLUMN entity_name FORMAT A16
SELECT policy_name, enabled_option, entity_name FROM audit_unified_enabled_policies
 WHERE policy_name IN ('POL_CONNEXIONS','POL_EMPLOYES','POL_ADMIN') ORDER BY policy_name;
SELECT metric, value, severity FROM audit_mgr.security_dashboard;
COLUMN alert_type FORMAT A18
COLUMN severity FORMAT A10
COLUMN source_user FORMAT A14
SELECT alert_type, severity, source_user, acknowledged,
       TO_CHAR(detected_at,'YYYY-MM-DD HH24:MI') AS detected
  FROM audit_mgr.security_alerts ORDER BY detected_at DESC;
COLUMN job_name FORMAT A26
COLUMN repeat_interval FORMAT A30
SELECT job_name, enabled, state, repeat_interval, run_count, failure_count
  FROM dba_scheduler_jobs WHERE job_name = 'SECURITY_MONITORING_JOB';

PROMPT
PROMPT === Exercice final : etat du compte analyst1 ===
SELECT username, account_status FROM dba_users WHERE username = 'ANALYST1';

SPOOL OFF
EXIT
