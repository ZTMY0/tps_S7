-- ============================================================
-- verify_tp4.sql : Séance 4 - Securite avancee sur SecureBank
-- Run as SYSDBA. Output goes to verify_tp4.log
-- Only read-only queries, plus re-running the TP's own harmless demo calls
-- (the injection test on chercher_client and the DBMS_CRYPTO round trip).
-- ============================================================
SET LINESIZE 200 PAGESIZE 100 TRIMSPOOL ON FEEDBACK ON VERIFY OFF
SET SERVEROUTPUT ON
SPOOL verify_tp4.log
ALTER SESSION SET CONTAINER = SECBANKPDB;
SHOW CON_NAME
SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') AS run_at FROM dual;

PROMPT
PROMPT === TP 1 : Privilege Analysis ===
COLUMN name FORMAT A14
COLUMN type FORMAT A12
SELECT name, type, enabled FROM dba_priv_captures WHERE name = 'tp4_capture';
COLUMN username FORMAT A18
COLUMN sys_priv FORMAT A22
COLUMN object_name FORMAT A22
SELECT username, sys_priv, object_owner, object_name FROM dba_used_privs
 WHERE capture = 'tp4_capture' ORDER BY username, object_name;
PROMPT -- privileges jamais utilises (SELECT ANY TABLE doit apparaitre si encore accorde)
SELECT username, sys_priv FROM dba_unused_privs WHERE capture = 'tp4_capture' ORDER BY username;
PROMPT -- apres REVOKE : SELECT ANY TABLE ne doit plus etre accorde a BANK_OPERATOR
COLUMN grantee FORMAT A16
SELECT grantee, privilege FROM dba_sys_privs WHERE grantee = 'BANK_OPERATOR';

PROMPT
PROMPT === TP 2 : droits du definisseur ===
SELECT object_name, object_type, status FROM dba_objects
 WHERE owner = 'BANK_OWNER' AND object_name IN ('SECRETS_RH','CHERCHER_CLIENT');
PROMPT -- code actuel de la fonction (doit contenir une variable liee :1 et USING)
SELECT text FROM dba_source
 WHERE owner = 'BANK_OWNER' AND name = 'CHERCHER_CLIENT' ORDER BY line;
PROMPT -- meme attaque que l'etape 2 du TP, sur la version corrigee
PROMPT -- resultat attendu : (aucun)  (ou une erreur, mais jamais la valeur secrete)
SELECT bank_owner.chercher_client('x'' UNION SELECT valeur FROM bank_owner.secrets_rh WHERE cle=''PRIME_DG''--') AS resultat
  FROM dual;

PROMPT
PROMPT === TP 3 : encodage vs chiffrement ===
SELECT UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(UTL_RAW.CAST_TO_RAW('4539148803436467'))) AS encode_base64 FROM dual;
DECLARE
  v_cle   RAW(32) := HEXTORAW('0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF');
  v_typ   PLS_INTEGER := DBMS_CRYPTO.ENCRYPT_AES256 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5;
  v_chiff RAW(2000);
BEGIN
  v_chiff := DBMS_CRYPTO.ENCRYPT(UTL_RAW.CAST_TO_RAW('4539148803436467'), v_typ, v_cle);
  DBMS_OUTPUT.PUT_LINE('Chiffre (hex) : ' || RAWTOHEX(v_chiff));
  DBMS_OUTPUT.PUT_LINE('Dechiffre     : ' || UTL_RAW.CAST_TO_VARCHAR2(DBMS_CRYPTO.DECRYPT(v_chiff, v_typ, v_cle)));
END;
/

PROMPT
PROMPT === TP 4 : Flashback ===
PROMPT -- comptes reels de votre base (le doc suppose account_id = 105, qui n'existe pas chez vous)
SELECT account_id, account_number, balance FROM bank_owner.accounts ORDER BY account_id;
SELECT supplemental_log_data_min AS supp_log_min FROM v$database;
COLUMN name FORMAT A20
COLUMN value FORMAT A12
SELECT name, value FROM v$parameter WHERE name = 'undo_retention';
ACCEPT acc NUMBER PROMPT 'account_id utilise pour la demo de fraude (ex: 10) : '
COLUMN versions_xid FORMAT A20
COLUMN versions_operation FORMAT A4
SELECT versions_xid, versions_operation AS op, versions_starttime, balance
  FROM bank_owner.accounts
  VERSIONS BETWEEN TIMESTAMP (TIMESTAMP '2026-11-06 06:13:00') AND SYSTIMESTAMP
 WHERE account_id = &acc
 ORDER BY versions_starttime;
COLUMN undo_sql FORMAT A100
SELECT operation, table_name, undo_sql FROM flashback_transaction_query
 WHERE table_owner = 'BANK_OWNER' AND table_name = 'ACCOUNTS'
   AND start_timestamp > TIMESTAMP '2026-11-06 06:13:00'
 ORDER BY start_timestamp;

SPOOL OFF
EXIT
