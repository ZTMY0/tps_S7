-- Before running: connect as account_mgr_paris_01 and run
--   SELECT account_id, balance FROM bank_owner.accounts WHERE branch_id = 'PARIS_01';
--   SELECT last_name FROM bank_owner.customers;
ALTER SESSION SET CONTAINER = SECBANKPDB;
BEGIN
  DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('tp4_capture');
  DBMS_PRIVILEGE_CAPTURE.GENERATE_RESULT('tp4_capture');
END;
/
SELECT username, sys_priv, object_owner, object_name FROM dba_used_privs WHERE capture = 'tp4_capture';
SELECT username, sys_priv FROM dba_unused_privs WHERE capture = 'tp4_capture';
REVOKE SELECT ANY TABLE FROM bank_operator;
