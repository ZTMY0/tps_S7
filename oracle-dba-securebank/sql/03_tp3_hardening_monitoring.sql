-- TP3: hardening, injection demo, audit, detection job. Run as SYSDBA after 02.
-- NOTE 1: hr_owner.employees and analyst1 are minimal STAND-INS for objects the TP assumes.
-- NOTE 2: this script is a clean re-implementation. The live hardening_log (see
--         evidence/sql/verify_tp3.log) holds manual entries dated 2026-10-07 whose wording
--         differs from the strings written by this script.
WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = SECBANKPDB;
ACCEPT mgr_pw CHAR PROMPT 'audit_mgr password: ' HIDE
ACCEPT hr_pw  CHAR PROMPT 'hr_owner password: ' HIDE
ACCEPT an_pw  CHAR PROMPT 'analyst1 password: ' HIDE

CREATE USER audit_mgr IDENTIFIED BY "&&mgr_pw" DEFAULT TABLESPACE audit_data
  TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON audit_data;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE JOB TO audit_mgr;
GRANT SELECT ON sys.unified_audit_trail TO audit_mgr;

-- TP3 assumes hr_owner.employees and analyst1; minimal stand-ins
CREATE USER hr_owner IDENTIFIED BY "&&hr_pw" DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE TO hr_owner;
CREATE TABLE hr_owner.employees (employee_id NUMBER PRIMARY KEY, first_name VARCHAR2(50),
  last_name VARCHAR2(50), salary NUMBER(10,2));
INSERT INTO hr_owner.employees VALUES (100,'Steven','King',24000);
INSERT INTO hr_owner.employees VALUES (101,'Neena','Kochhar',17000);
INSERT INTO hr_owner.employees VALUES (102,'Lex','De Haan',17000);
COMMIT;
CREATE USER analyst1 IDENTIFIED BY "&&an_pw" TEMPORARY TABLESPACE temp;
GRANT CREATE SESSION TO analyst1;
GRANT SELECT ON hr_owner.employees TO analyst1;

CREATE TABLE audit_mgr.hardening_log (
  action_date TIMESTAMP DEFAULT SYSTIMESTAMP, action_type VARCHAR2(100),
  action_detail VARCHAR2(4000), performed_by VARCHAR2(100) DEFAULT USER);

DECLARE v_count NUMBER := 0;
BEGIN
  FOR rec IN (SELECT username FROM dba_users
               WHERE (oracle_maintained = 'Y' OR username IN ('SCOTT','HR','OE','PM','SH','IX','BI','OUTLN'))
                 AND username NOT IN ('SYS','SYSTEM') AND account_status LIKE '%OPEN%') LOOP
    EXECUTE IMMEDIATE 'ALTER USER ' || rec.username || ' ACCOUNT LOCK';
    INSERT INTO audit_mgr.hardening_log (action_type, action_detail)
    VALUES ('ACCOUNT_LOCK', 'Compte verrouillé : ' || rec.username);
    v_count := v_count + 1;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('locked: ' || v_count);
END;
/

CREATE TABLE audit_mgr.dangerous_packages AS
SELECT 'UTL_FILE' package_name, 'Accès fichiers' risk FROM dual
UNION ALL SELECT 'UTL_TCP','Connexions TCP' FROM dual
UNION ALL SELECT 'UTL_HTTP','Requêtes HTTP' FROM dual
UNION ALL SELECT 'UTL_SMTP','Envoi de mails' FROM dual
UNION ALL SELECT 'DBMS_SQL','SQL dynamique' FROM dual
UNION ALL SELECT 'DBMS_SCHEDULER','Planification de tâches' FROM dual
UNION ALL SELECT 'DBMS_JAVA','Exécution Java' FROM dual
UNION ALL SELECT 'DBMS_LDAP','Opérations LDAP' FROM dual;

DECLARE v_count NUMBER := 0;
BEGIN
  FOR rec IN (SELECT package_name FROM audit_mgr.dangerous_packages) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'REVOKE EXECUTE ON ' || rec.package_name || ' FROM PUBLIC';
      INSERT INTO audit_mgr.hardening_log (action_type, action_detail)
      VALUES ('PACKAGE_REVOKE', 'EXECUTE révoqué sur ' || rec.package_name);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('skipped ' || rec.package_name || ': ' || SQLERRM);
    END;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('revoked: ' || v_count);
END;
/

CREATE OR REPLACE PROCEDURE hr_owner.search_employee_vulnerable(p_name VARCHAR2) AS
  TYPE emp_cursor IS REF CURSOR;
  v_cur emp_cursor; v_id NUMBER; v_fn VARCHAR2(50); v_ln VARCHAR2(50); v_sal NUMBER;
  v_sql VARCHAR2(1000);
BEGIN
  v_sql := 'SELECT employee_id, first_name, last_name, salary FROM employees ' ||
           'WHERE first_name LIKE ''%' || p_name || '%''';
  DBMS_OUTPUT.PUT_LINE('SQL: ' || v_sql);
  OPEN v_cur FOR v_sql;
  LOOP FETCH v_cur INTO v_id, v_fn, v_ln, v_sal; EXIT WHEN v_cur%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_id||' - '||v_fn||' '||v_ln||' - '||v_sal);
  END LOOP; CLOSE v_cur;
END;
/
CREATE OR REPLACE PROCEDURE hr_owner.search_employee_secure(p_name VARCHAR2) AS
  TYPE emp_cursor IS REF CURSOR;
  v_cur emp_cursor; v_id NUMBER; v_fn VARCHAR2(50); v_ln VARCHAR2(50); v_sal NUMBER;
BEGIN
  OPEN v_cur FOR
    'SELECT employee_id, first_name, last_name, salary FROM employees ' ||
    'WHERE first_name LIKE ''%'' || :1 || ''%''' USING p_name;
  LOOP FETCH v_cur INTO v_id, v_fn, v_ln, v_sal; EXIT WHEN v_cur%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_id||' - '||v_fn||' '||v_ln||' - '||v_sal);
  END LOOP; CLOSE v_cur;
END;
/
CREATE OR REPLACE PROCEDURE hr_owner.count_rows_secure(p_table VARCHAR2) AS
  v_ok VARCHAR2(128); v_count NUMBER;
BEGIN
  v_ok := DBMS_ASSERT.SIMPLE_SQL_NAME(p_table);
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_ok INTO v_count;
  DBMS_OUTPUT.PUT_LINE('Lignes dans ' || v_ok || ' : ' || v_count);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Nom de table invalide : ' || SQLERRM);
END;
/

CREATE AUDIT POLICY pol_connexions ACTIONS LOGON, LOGOFF;
AUDIT POLICY pol_connexions WHENEVER NOT SUCCESSFUL;
CREATE AUDIT POLICY pol_employes ACTIONS SELECT, UPDATE, DELETE ON hr_owner.employees;
AUDIT POLICY pol_employes;
CREATE AUDIT POLICY pol_admin PRIVILEGES CREATE USER, DROP USER, ALTER USER, GRANT ANY PRIVILEGE;
AUDIT POLICY pol_admin;

CREATE TABLE audit_mgr.security_alerts (
  alert_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  alert_type VARCHAR2(100),
  severity VARCHAR2(20) CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  alert_message CLOB, detected_at TIMESTAMP DEFAULT SYSTIMESTAMP,
  source_user VARCHAR2(128), source_ip VARCHAR2(100), acknowledged CHAR(1) DEFAULT 'N');
CREATE INDEX audit_mgr.idx_alerts_sev ON audit_mgr.security_alerts(severity, detected_at);

CREATE OR REPLACE VIEW audit_mgr.security_dashboard AS
SELECT 'Échecs de connexion (1h)' metric, TO_CHAR(COUNT(*)) value,
       CASE WHEN COUNT(*) > 5 THEN 'HIGH' ELSE 'LOW' END severity
  FROM unified_audit_trail
 WHERE action_name = 'LOGON' AND return_code <> 0
   AND event_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
UNION ALL
SELECT 'Alertes non traitées', TO_CHAR(COUNT(*)),
       CASE WHEN COUNT(*) > 0 THEN 'CRITICAL' ELSE 'LOW' END
  FROM audit_mgr.security_alerts WHERE acknowledged = 'N';

CREATE OR REPLACE PROCEDURE audit_mgr.detect_security_threats AS
  v_msg VARCHAR2(4000);
BEGIN
  FOR rec IN (SELECT dbusername, userhost, COUNT(*) nb FROM unified_audit_trail
               WHERE action_name = 'LOGON' AND return_code <> 0
                 AND event_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
               GROUP BY dbusername, userhost HAVING COUNT(*) >= 3) LOOP
    v_msg := 'Force brute : '||rec.nb||' échecs pour '||rec.dbusername||' depuis '||rec.userhost;
    INSERT INTO audit_mgr.security_alerts(alert_type,severity,alert_message,source_user,source_ip)
    VALUES ('BRUTE_FORCE','HIGH',v_msg,rec.dbusername,rec.userhost);
  END LOOP;
  FOR rec IN (SELECT dbusername, object_name, COUNT(*) nb FROM unified_audit_trail
               WHERE action_name = 'SELECT' AND event_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
                 AND object_schema NOT IN ('SYS','SYSTEM')
               GROUP BY dbusername, object_name HAVING COUNT(*) > 100) LOOP
    v_msg := 'Accès massif : '||rec.dbusername||' a lu '||rec.object_name||' '||rec.nb||' fois en 1h';
    INSERT INTO audit_mgr.security_alerts(alert_type,severity,alert_message,source_user)
    VALUES ('MASS_DATA_ACCESS','CRITICAL',v_msg,rec.dbusername);
  END LOOP;
  COMMIT;
END;
/

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(job_name => 'AUDIT_MGR.SECURITY_MONITORING_JOB',
    job_type => 'PLSQL_BLOCK', job_action => 'BEGIN audit_mgr.detect_security_threats; END;',
    start_date => SYSTIMESTAMP, repeat_interval => 'FREQ=MINUTELY; INTERVAL=15', enabled => TRUE);
END;
/
