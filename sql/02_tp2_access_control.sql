-- TP2: schema, roles, users, VPD, unified audit. Run as SYSDBA after TP1.
WHENEVER SQLERROR EXIT FAILURE
SET VERIFY OFF SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = SECBANKPDB;
ACCEPT owner_pw CHAR PROMPT 'bank_owner password: ' HIDE
ACCEPT user_pw  CHAR PROMPT 'password for the 4 application users: ' HIDE

CREATE PROFILE secbank_user_profile LIMIT
  SESSIONS_PER_USER 2 FAILED_LOGIN_ATTEMPTS 3 PASSWORD_LIFE_TIME 60
  PASSWORD_REUSE_TIME 365 PASSWORD_REUSE_MAX 6 PASSWORD_LOCK_TIME 2/24
  PASSWORD_GRACE_TIME 5 IDLE_TIME 30 CONNECT_TIME 480;

CREATE USER bank_owner IDENTIFIED BY "&&owner_pw"
  DEFAULT TABLESPACE accounts_data TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON accounts_data QUOTA UNLIMITED ON transactions_data
  QUOTA UNLIMITED ON audit_data PASSWORD EXPIRE;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE,
      CREATE SEQUENCE, CREATE TRIGGER, CREATE SYNONYM TO bank_owner;
GRANT SELECT ON sys.dba_sys_privs TO bank_owner;

ALTER SESSION SET CURRENT_SCHEMA = bank_owner;

CREATE TABLE customers (
  customer_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name VARCHAR2(50) NOT NULL, last_name VARCHAR2(50) NOT NULL,
  email VARCHAR2(100) UNIQUE, phone VARCHAR2(20), address VARCHAR2(200),
  city VARCHAR2(50), postal_code VARCHAR2(10),
  ssn VARCHAR2(15) ENCRYPT USING 'AES256' NO SALT,
  date_of_birth DATE, created_date TIMESTAMP DEFAULT SYSTIMESTAMP,
  modified_date TIMESTAMP, branch_id VARCHAR2(20) NOT NULL,
  CONSTRAINT chk_email CHECK (email LIKE '%@%')
) TABLESPACE accounts_data;

CREATE TABLE accounts (
  account_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_number VARCHAR2(24) UNIQUE NOT NULL, customer_id NUMBER NOT NULL,
  account_type VARCHAR2(20) NOT NULL, balance NUMBER(15,2) DEFAULT 0 NOT NULL,
  currency VARCHAR2(3) DEFAULT 'EUR', status VARCHAR2(20) DEFAULT 'ACTIVE',
  opened_date DATE DEFAULT SYSDATE, closed_date DATE,
  branch_id VARCHAR2(20) NOT NULL, created_date TIMESTAMP DEFAULT SYSTIMESTAMP,
  modified_date TIMESTAMP,
  CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  CONSTRAINT chk_account_type CHECK (account_type IN ('CHECKING','SAVINGS','BUSINESS')),
  CONSTRAINT chk_balance CHECK (balance >= -1000),
  CONSTRAINT chk_status CHECK (status IN ('ACTIVE','FROZEN','CLOSED'))
) TABLESPACE accounts_data;

CREATE TABLE transactions (
  transaction_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id NUMBER NOT NULL, transaction_type VARCHAR2(20) NOT NULL,
  amount NUMBER(15,2) NOT NULL, transaction_date TIMESTAMP DEFAULT SYSTIMESTAMP,
  description VARCHAR2(200), reference_number VARCHAR2(50) UNIQUE,
  status VARCHAR2(20) DEFAULT 'COMPLETED', branch_id VARCHAR2(20) NOT NULL,
  created_by VARCHAR2(100),
  CONSTRAINT fk_trans_account FOREIGN KEY (account_id) REFERENCES accounts(account_id),
  CONSTRAINT chk_trans_type CHECK (transaction_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER','FEE','INTEREST')),
  CONSTRAINT chk_trans_status CHECK (status IN ('PENDING','COMPLETED','FAILED','CANCELLED'))
) TABLESPACE transactions_data;

CREATE TABLE user_branch_mapping (
  username VARCHAR2(128) PRIMARY KEY, branch_id VARCHAR2(20) NOT NULL,
  role_type VARCHAR2(50), assigned_date DATE DEFAULT SYSDATE
) TABLESPACE accounts_data;

INSERT INTO customers (first_name,last_name,email,phone,address,city,postal_code,ssn,date_of_birth,branch_id) VALUES ('Jean','Dupont','jean.dupont@email.fr','0601020304','123 Rue de Rivoli','Paris','75001','177056789012',DATE '1977-05-15','PARIS_01');
INSERT INTO customers (first_name,last_name,email,phone,address,city,postal_code,ssn,date_of_birth,branch_id) VALUES ('Marie','Martin','marie.martin@email.fr','0602030405','45 Avenue des Champs','Paris','75008','285037812034',DATE '1985-03-22','PARIS_08');
INSERT INTO customers (first_name,last_name,email,phone,address,city,postal_code,ssn,date_of_birth,branch_id) VALUES ('Pierre','Bernard','pierre.bernard@email.fr','0603040506','78 Cours Lafayette','Lyon','69003','390018923045',DATE '1990-01-10','LYON_03');
INSERT INTO customers (first_name,last_name,email,phone,address,city,postal_code,ssn,date_of_birth,branch_id) VALUES ('Sophie','Dubois','sophie.dubois@email.fr','0604050607','12 Boulevard de la Croisette','Cannes','06400','478119034056',DATE '1978-11-28','CANNES_01');

INSERT INTO accounts (account_number,customer_id,account_type,balance,branch_id) VALUES ('FR7612345000012345678901',1,'CHECKING',5420.50,'PARIS_01');
INSERT INTO accounts (account_number,customer_id,account_type,balance,branch_id) VALUES ('FR7612345000012345678902',1,'SAVINGS',15000.00,'PARIS_01');
INSERT INTO accounts (account_number,customer_id,account_type,balance,branch_id) VALUES ('FR7612345000012345678903',2,'CHECKING',3210.75,'PARIS_08');
INSERT INTO accounts (account_number,customer_id,account_type,balance,branch_id) VALUES ('FR7612345000012345678904',3,'CHECKING',8750.00,'LYON_03');
INSERT INTO accounts (account_number,customer_id,account_type,balance,branch_id) VALUES ('FR7612345000012345678905',4,'BUSINESS',45600.25,'CANNES_01');

INSERT INTO transactions (account_id,transaction_type,amount,description,reference_number,branch_id,created_by) VALUES (1,'DEPOSIT',1000.00,'Dépôt espèces','TRX20241225001','PARIS_01','SYS');
INSERT INTO transactions (account_id,transaction_type,amount,description,reference_number,branch_id,created_by) VALUES (1,'WITHDRAWAL',-200.00,'Retrait DAB','TRX20241225002','PARIS_01','ATM_PARIS_01');
INSERT INTO transactions (account_id,transaction_type,amount,description,reference_number,branch_id,created_by) VALUES (3,'TRANSFER',500.00,'Virement entrant','TRX20241225003','PARIS_08','SYS');
INSERT INTO transactions (account_id,transaction_type,amount,description,reference_number,branch_id,created_by) VALUES (4,'DEPOSIT',2500.00,'Dépôt chèque','TRX20241225004','LYON_03','SYS');

INSERT INTO user_branch_mapping (username,branch_id,role_type) VALUES ('ADVISOR_PARIS_01','PARIS_01','ADVISOR');
INSERT INTO user_branch_mapping (username,branch_id,role_type) VALUES ('ACCOUNT_MGR_PARIS_01','PARIS_01','MANAGER');
INSERT INTO user_branch_mapping (username,branch_id,role_type) VALUES ('ADVISOR_LYON_03','LYON_03','ADVISOR');
COMMIT;

ALTER SESSION SET CURRENT_SCHEMA = sys;

CREATE ROLE bank_employee;
GRANT CREATE SESSION TO bank_employee;

CREATE ROLE bank_reader;
GRANT bank_employee TO bank_reader;
GRANT SELECT ON bank_owner.customers TO bank_reader;
GRANT SELECT ON bank_owner.accounts TO bank_reader;
GRANT SELECT ON bank_owner.transactions TO bank_reader;

CREATE ROLE bank_operator;
GRANT bank_reader TO bank_operator;
GRANT INSERT, UPDATE ON bank_owner.customers TO bank_operator;
GRANT INSERT, UPDATE ON bank_owner.accounts TO bank_operator;
GRANT INSERT ON bank_owner.transactions TO bank_operator;

CREATE ROLE bank_auditor;
GRANT bank_employee TO bank_auditor;
GRANT SELECT ANY TABLE TO bank_auditor;
GRANT SELECT_CATALOG_ROLE TO bank_auditor;
GRANT SELECT ON sys.unified_audit_trail TO bank_auditor;

CREATE USER advisor_paris_01 IDENTIFIED BY "&&user_pw" DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp PROFILE secbank_user_profile PASSWORD EXPIRE;
CREATE USER account_mgr_paris_01 IDENTIFIED BY "&&user_pw" DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp PROFILE secbank_user_profile PASSWORD EXPIRE;
CREATE USER advisor_lyon_03 IDENTIFIED BY "&&user_pw" DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp PROFILE secbank_user_profile PASSWORD EXPIRE;
CREATE USER security_auditor IDENTIFIED BY "&&user_pw" DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp PROFILE secbank_user_profile PASSWORD EXPIRE;
GRANT bank_reader TO advisor_paris_01;
GRANT bank_reader TO advisor_lyon_03;
GRANT bank_operator TO account_mgr_paris_01;
GRANT bank_auditor TO security_auditor;
ALTER USER advisor_paris_01 DEFAULT ROLE bank_reader;
ALTER USER advisor_lyon_03 DEFAULT ROLE bank_reader;
ALTER USER account_mgr_paris_01 DEFAULT ROLE bank_operator;
ALTER USER security_auditor DEFAULT ROLE bank_auditor;

CREATE OR REPLACE FUNCTION bank_owner.branch_security_policy(schema_var VARCHAR2, table_var VARCHAR2)
  RETURN VARCHAR2 AS
  v_user   VARCHAR2(128) := SYS_CONTEXT('USERENV','SESSION_USER');
  v_n      NUMBER;
  v_branch VARCHAR2(20);
BEGIN
  SELECT COUNT(*) INTO v_n FROM sys.dba_sys_privs
   WHERE grantee = v_user AND privilege = 'EXEMPT ACCESS POLICY';
  IF v_n > 0 THEN RETURN NULL; END IF;
  SELECT branch_id INTO v_branch FROM bank_owner.user_branch_mapping WHERE username = v_user;
  RETURN 'branch_id = ''' || v_branch || '''';
EXCEPTION WHEN NO_DATA_FOUND THEN
  RETURN '1=0';
END;
/

BEGIN
  FOR t IN (SELECT column_value o FROM TABLE(sys.odcivarchar2list('CUSTOMERS','ACCOUNTS','TRANSACTIONS'))) LOOP
    DBMS_RLS.ADD_POLICY('BANK_OWNER', t.o, 'BRANCH_ISOLATION_'||t.o, 'BANK_OWNER',
      'BRANCH_SECURITY_POLICY', statement_types => 'SELECT,INSERT,UPDATE,DELETE',
      update_check => TRUE, enable => TRUE);
  END LOOP;
END;
/
GRANT EXEMPT ACCESS POLICY TO security_auditor;

CREATE AUDIT POLICY secbank_account_access ACTIONS SELECT, INSERT, UPDATE, DELETE ON bank_owner.accounts;
CREATE AUDIT POLICY secbank_balance_changes ACTIONS UPDATE ON bank_owner.accounts
  WHEN 'SYS_CONTEXT(''USERENV'',''CURRENT_SQL'') LIKE ''%balance%''' EVALUATE PER STATEMENT;
CREATE AUDIT POLICY secbank_transactions ACTIONS INSERT, UPDATE, DELETE ON bank_owner.transactions;
CREATE AUDIT POLICY secbank_failed_logins ACTIONS LOGON
  WHEN 'SYS_CONTEXT(''USERENV'',''RETURNCODE'') != 0' EVALUATE PER SESSION;
CREATE AUDIT POLICY secbank_privilege_changes
  ACTIONS GRANT, REVOKE, CREATE USER, DROP USER, ALTER USER;
AUDIT POLICY secbank_account_access;
AUDIT POLICY secbank_balance_changes;
AUDIT POLICY secbank_transactions;
AUDIT POLICY secbank_failed_logins;
AUDIT POLICY secbank_privilege_changes;
