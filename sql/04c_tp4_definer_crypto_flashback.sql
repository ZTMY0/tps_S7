-- TP4 steps 2-4. Run as SYSDBA.
WHENEVER SQLERROR EXIT FAILURE
SET SERVEROUTPUT ON LINESIZE 200
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER SESSION SET CONTAINER = SECBANKPDB;

CREATE TABLE bank_owner.secrets_rh (cle VARCHAR2(30), valeur VARCHAR2(100));
INSERT INTO bank_owner.secrets_rh VALUES ('PRIME_DG', 'confidentiel : 45000 EUR');
COMMIT;

CREATE OR REPLACE FUNCTION bank_owner.chercher_client(p_nom IN VARCHAR2) RETURN VARCHAR2 AS
  v_sql VARCHAR2(1000); v_res VARCHAR2(400);
BEGIN
  v_sql := 'SELECT MAX(last_name) FROM customers WHERE last_name = ''' || p_nom || '''';
  EXECUTE IMMEDIATE v_sql INTO v_res;
  RETURN NVL(v_res, '(aucun)');
END;
/
GRANT EXECUTE ON bank_owner.chercher_client TO bank_reader;
SELECT bank_owner.chercher_client('x'' HAVING 1=0 UNION SELECT valeur FROM bank_owner.secrets_rh WHERE cle=''PRIME_DG''--') AS attaque FROM dual;

CREATE OR REPLACE FUNCTION bank_owner.chercher_client(p_nom IN VARCHAR2) RETURN VARCHAR2 AS
  v_res VARCHAR2(400);
BEGIN
  EXECUTE IMMEDIATE 'SELECT MAX(last_name) FROM customers WHERE last_name = :1' INTO v_res USING p_nom;
  RETURN NVL(v_res, '(aucun)');
END;
/
SELECT bank_owner.chercher_client('x'' HAVING 1=0 UNION SELECT valeur FROM bank_owner.secrets_rh WHERE cle=''PRIME_DG''--') AS attaque_corrigee FROM dual;

SELECT UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(UTL_RAW.CAST_TO_RAW('4539148803436467'))) AS encode FROM dual;
DECLARE
  -- DEMO-ONLY KEY: hardcoded for the lab. Never reuse it; real keys come from a keystore/HSM.
  v_cle   RAW(32) := HEXTORAW('0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF');
  v_typ   PLS_INTEGER := DBMS_CRYPTO.ENCRYPT_AES256 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5;
  v_chiff RAW(2000);
BEGIN
  v_chiff := DBMS_CRYPTO.ENCRYPT(UTL_RAW.CAST_TO_RAW('4539148803436467'), v_typ, v_cle);
  DBMS_OUTPUT.PUT_LINE('chiffre : ' || RAWTOHEX(v_chiff));
  DBMS_OUTPUT.PUT_LINE('dechiffre : ' || UTL_RAW.CAST_TO_VARCHAR2(DBMS_CRYPTO.DECRYPT(v_chiff, v_typ, v_cle)));
END;
/

-- Flashback demo on account 5 with a 40000 debit (105 does not exist; 50000 breaks chk_balance)
SELECT balance FROM bank_owner.accounts WHERE account_id = 5;
UPDATE bank_owner.accounts SET balance = balance - 40000 WHERE account_id = 5;
COMMIT;
SELECT versions_xid, versions_operation, versions_starttime, balance
  FROM bank_owner.accounts VERSIONS BETWEEN TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE) AND SYSTIMESTAMP
 WHERE account_id = 5 ORDER BY versions_starttime;
SELECT operation, undo_sql FROM flashback_transaction_query
 WHERE table_owner = 'BANK_OWNER' AND table_name = 'ACCOUNTS'
   AND start_timestamp > SYSTIMESTAMP - INTERVAL '30' MINUTE;
-- apply the undo_sql shown above to restore the balance
