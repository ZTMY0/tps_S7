-- TP4 step 1. Run as SYSDBA. Then, as an application user, run the two queries listed in 04b.
ALTER SESSION SET CONTAINER = SECBANKPDB;
GRANT SELECT ANY TABLE TO bank_operator;
BEGIN
  DBMS_PRIVILEGE_CAPTURE.CREATE_CAPTURE(name => 'tp4_capture', type => DBMS_PRIVILEGE_CAPTURE.G_DATABASE);
  DBMS_PRIVILEGE_CAPTURE.ENABLE_CAPTURE('tp4_capture');
END;
/
