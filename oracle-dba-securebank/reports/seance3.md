# Séance 3 — Durcissement, monitoring et réponse aux incidents

**Projet SecureBank — Oracle Database 19c EE** · Ihab Zaghdane · EIDIA, UEMF Fès

> Convention : les mots de passe sont remplacés par `<TDE_PASSWORD>` / `********`. La VM est `secbank.local` (CDB `SECBANK`, PDB `SECBANKPDB`, service `SECBANKPDB.local`, port 1521). Le travail réel s'est déroulé du 30 septembre au 28 octobre 2026 ; les vérifications ci-dessous ont été relancées le 6 novembre 2026 (`verify_tp3.sql`, 06:21).

## 1. Objectif

Durcir la base (comptes, packages, réseau), démontrer puis corriger une injection SQL, mettre en place l'audit unifié, des alertes et un job de détection, puis sauvegarder avec RMAN (chiffrement) et dérouler un exercice de réponse à incident.

Les objets `hr_owner.employees` et le compte `analyst1` sont des **substituts minimaux** des objets supposés par l'énoncé (schéma de l'énoncé `audit_admin` → `audit_mgr` ici).

## 2. Environnement

| Élément | Valeur |
|---|---|
| Système | Oracle Linux 8.8, `secbank.local`, utilisateur `oracle` |
| Base | CDB `SECBANK` / PDB `SECBANKPDB`, ARCHIVELOG |
| Schémas | `audit_mgr`, `hr_owner`, `bank_owner` |
| Outils | SQL*Plus, `lsnrctl`, RMAN 19.3 |

## 3. Partie 1 — Audit et durcissement

### Étapes et commandes

Script de référence : `sql/03_tp3_hardening_monitoring.sql` (réimplémentation propre ; voir « Limites »).

```sql
-- verrouillage des comptes Oracle par défaut (sauf SYS, SYSTEM)
ALTER USER <compte> ACCOUNT LOCK;
-- retrait des packages dangereux à PUBLIC
REVOKE EXECUTE ON <package> FROM PUBLIC;  -- UTL_FILE, UTL_TCP, UTL_HTTP, UTL_SMTP,
                                          -- DBMS_SQL, DBMS_SCHEDULER, DBMS_JAVA, DBMS_LDAP
```

Chaque action est tracée dans `audit_mgr.hardening_log`.

### Évidence

État des comptes Oracle (PDB) :

```
ACCOUNT_STATUS               NB
-------------------- ----------
EXPIRED & LOCKED              3
LOCKED                       30
OPEN                          2

USERNAME                 ACCOUNT_STATUS
------------------------ --------------------
ANONYMOUS                EXPIRED & LOCKED
DBSNMP                   LOCKED
OUTLN                    LOCKED
```

Journal de durcissement (`hardening_log`) :

```
2026-10-07 08:15:42 CRITICAL         ANONYMOUS verrouille et privileges revoques
2026-10-07 08:16:23 PACKAGE_REVOKE   EXECUTE revoque sur UTL_FILE
2026-10-07 08:16:23 PACKAGE_REVOKE   EXECUTE revoque sur UTL_TCP
2026-10-07 08:16:24 PACKAGE_REVOKE   EXECUTE revoque sur UTL_HTTP
2026-10-07 08:16:24 PACKAGE_REVOKE   EXECUTE revoque sur UTL_SMTP
2026-10-07 08:16:24 PACKAGE_REVOKE   EXECUTE revoque sur DBMS_LDAP
2026-10-07 08:28:40 REVOKE EXECUTE FROM PUBLIC   (DBMS_JAVA)
2026-10-07 08:29:05 REVOKE EXECUTE FROM PUBLIC   (DBMS_SQL)
2026-10-07 08:30:16 REVOKE EXECUTE FROM PUBLIC   (DBMS_SCHEDULER)
2026-10-07 08:30:55 ACCOUNT LOCK     PDBADMIN
2026-10-28 07:15:43 INCIDENT         ANALYST1 locked after mass SELECT on hr_owner.employees
```

*(Les trois lignes `REVOKE EXECUTE F… ROM PUBLIC` sont coupées par la largeur de colonne dans le log original ; elles sont regroupées ici sur une ligne, sans autre modification.)*

Requête « packages dangereux encore exécutables par PUBLIC » : `no rows selected`.

### Analyse

- Les 8 packages ciblés n'ont plus de droit `EXECUTE` pour `PUBLIC` : la requête de contrôle est vide.
- Le log montre 2 comptes Oracle-maintained encore `OPEN` ; leurs noms n'apparaissent pas dans la sortie.

## 4. Partie 2 — Sécurisation du réseau

### Configuration réelle (VM, 6 novembre 2026)

`sqlnet.ora` : chiffrement et somme de contrôle `REQUIRED` côté client et serveur (AES256/192/128, SHA512/384/256), `SQLNET.ALLOWED_LOGON_VERSION_SERVER = 12`, `TCP.VALIDNODE_CHECKING = YES`, `TCP.INVITED_NODES = (<VM_IP>,127.0.0.1,<ADMIN_CLIENT_IP>)`, `SQLNET.EXPIRE_TIME = 10`, `SQLNET.INBOUND_CONNECT_TIMEOUT = 60`.

`listener.ora` :

```
ADMIN_RESTRICTIONS_LISTENER = ON
INBOUND_CONNECT_TIMEOUT_LISTENER = 60
SECURE_REGISTER_LISTENER = TCP
LOGGING_LISTENER = ON
```

Le fichier `sqlnet.ora` réel **ne contient pas** `SQLNET.AUTHENTICATION_SERVICES` (l'énoncé le propose avec `(NONE)`). L'authentification `/ as sysdba` reste donc utilisable sur la VM.

### Évidence

```
Security                  ON: Local OS Authentication
Listening Endpoints Summary...
  (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=secbank.local)(PORT=1521)))
  (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=EXTPROC1521)))
...
Service "secbankpdb.local" has 1 instance(s).
  Instance "SECBANK", status READY, has 1 handler(s) for this service...
```

Le service `SECBANK.local`, `SECBANKXDB.local` et `secbankpdb.local` sont `READY`. Le listener expose aussi un service d'une **autre PDB sans rapport avec le projet** (nom masqué dans les preuves : `<AUTRE_PDB>`).

### Non capturé

La négociation effective du chiffrement (`v$session_connect_info`) n'a pas été re-capturée en Séance 3 ; la preuve existe dans le rapport de la Séance 1 (figure 9). Aucune capture Wireshark n'est fournie.

## 5. Partie 3 — Injection SQL : de l'attaque à la parade

### Procédures créées (`hr_owner`)

| Procédure | Rôle |
|---|---|
| `SEARCH_EMPLOYEE_VULNERABLE` | concatène `p_name` dans la requête dynamique |
| `SEARCH_EMPLOYEE_SECURE` | variable liée `:1` avec `USING` |
| `COUNT_ROWS_SECURE` | valide le nom de table avec `DBMS_ASSERT.SIMPLE_SQL_NAME` |

### Évidence

```
OWNER        OBJECT_NAME                    OBJECT_TYPE             STATUS
------------ ------------------------------ ----------------------- -------
HR_OWNER     COUNT_ROWS_SECURE              PROCEDURE               VALID
HR_OWNER     SEARCH_EMPLOYEE_SECURE         PROCEDURE               VALID
HR_OWNER     SEARCH_EMPLOYEE_VULNERABLE     PROCEDURE               VALID
```

### Démonstration (ré-exécutée le 6 novembre 2026)

Les sorties d'origine n'ont pas été conservées ; la démonstration a été rejouée en SYSDBA dans `SECBANKPDB` (`SET SERVEROUTPUT ON LINESIZE 200`). Les accents s'affichent « ?? » (encodage du terminal). Sorties complètes : `evidence/sql/tp3_tp4_demos_20261106.log` et `evidence/sql/lot1_demos_20261106.log`.

**1. Usage normal**

```
SQL> EXEC hr_owner.search_employee_vulnerable('Steven');
SQL ex??cut?? : SELECT employee_id, first_name, last_name, salary FROM employees WHERE first_name LIKE '%Steven%'
100 - Steven King - 24000
```

**2. Condition toujours vraie**

```
SQL> EXEC hr_owner.search_employee_vulnerable('x'' OR ''1''=''1'' --');
SQL ex??cut?? : SELECT employee_id, first_name, last_name, salary FROM employees WHERE first_name LIKE '%x' OR '1'='1' --%'
100 - Steven King - 24000
101 - Neena Kochhar - 17000
102 - Lex De Haan - 17000
103 - Alexander Hunold - 9000
104 - Bruce Ernst - 6000
105 - David Austin - 4800
106 - Valli Pataballa - 4800
107 - Diana Lorentz - 4200
```

**3. Exfiltration par `UNION`** (extrait : 52 lignes de comptes, 6 affichées ici ; la sortie complète est dans le fichier de preuve)

```
SQL> EXEC hr_owner.search_employee_vulnerable('x'' UNION SELECT -1, username, ''--'', 0 FROM dba_users --');
SQL ex??cut?? : SELECT employee_id, first_name, last_name, salary FROM employees WHERE first_name LIKE '%x' UNION SELECT -1, username, '--', 0 FROM dba_users --%'
-1 - ACCOUNT_MGR_PARIS_01 -- - 0
-1 - ADVISOR_LYON_03 -- - 0
-1 - ADVISOR_PARIS_01 -- - 0
...
-1 - XDB -- - 0
-1 - XS$NULL -- - 0
102 - Lex De Haan - 17000
```

La même attaque sur `all_users` donne la même liste.

**4. Version sécurisée**

```
SQL> EXEC hr_owner.search_employee_secure('Steven');
100 - Steven King - 24000
SQL> EXEC hr_owner.search_employee_secure('x'' OR ''1''=''1'' --');
PL/SQL procedure successfully completed.
```

(aucune ligne renvoyée pour la charge d'injection.)

**5. Noms d'objets dynamiques (`DBMS_ASSERT`)**

```
SQL> EXEC hr_owner.count_rows_secure('EMPLOYEES');
Lignes dans EMPLOYEES : 8
SQL> EXEC hr_owner.count_rows_secure('EMPLOYEES WHERE 1=0');
Nom de table invalide : ORA-44003: invalid SQL name
```

### Analyse

- **Version vulnérable :** la saisie est collée dans la requête (ligne `SQL exécuté`). Avec `OR '1'='1'` et `--`, la condition est toujours vraie : 8 lignes avec leurs salaires, dont des prénoms ne contenant pas « x ». Avec `UNION`, la liste des comptes de la base (52 comptes) remonte dans les résultats « employés ». Cette liste contient aussi des comptes d'un autre exercice du cours (CTF NovaTech) hébergés dans la même PDB : `NOVA`, `APP_OWNER`, `ANALYST`, `TEST_APP`, `DEMO`. La procédure s'exécute avec les droits de son propriétaire `hr_owner`.
- **Version sécurisée :** la même charge est traitée comme une simple valeur (variable liée) : aucune ligne. L'usage normal fonctionne toujours.
- **`DBMS_ASSERT` :** `count_rows_secure` accepte `EMPLOYEES` et rejette `EMPLOYEES WHERE 1=0` avec `ORA-44003`.
- Les charges de l'énoncé se terminent par `'1'='1`, que la procédure suit de `%'` : la condition devient `'1'='1%'` (fausse). J'ai donc utilisé `--` pour commenter la fin de la requête.

## 6. Partie 4 — Monitoring et alertes

### Mise en place

- Politiques d'audit unifié : `POL_CONNEXIONS` (échecs de connexion), `POL_EMPLOYES` (SELECT/UPDATE/DELETE sur `hr_owner.employees`), `POL_ADMIN` (opérations d'administration).
- Table `audit_mgr.security_alerts`, vue `audit_mgr.security_dashboard`.
- Procédure `audit_mgr.detect_security_threats` : alerte `BRUTE_FORCE` (≥ 3 échecs de connexion par utilisateur et hôte sur 1 h), alerte `MASS_DATA_ACCESS` (> 100 SELECT par utilisateur et objet sur 1 h). La détection n'élimine pas les doublons : chaque exécution réévalue la fenêtre glissante d'une heure.
- Job `AUDIT_MGR.SECURITY_MONITORING_JOB`, toutes les 15 minutes.

### Évidence

```
POLICY_NAME              ENABLED_OPTION  ENTITY_NAME
POL_ADMIN                BY USER         ALL USERS
POL_CONNEXIONS           BY USER         ALL USERS
POL_EMPLOYES             BY USER         ALL USERS

METRIC                   VALUE   SEVERITY
Echecs de connexion (1h) 0       LOW
Alertes non traitees     5       CRITICAL

JOB_NAME                   ENABL STATE      REPEAT_INTERVAL                 RUN_COUNT FAILURE_COUNT
SECURITY_MONITORING_JOB    TRUE  SCHEDULED  FREQ=MINUTELY; INTERVAL=15            100             0
```

## 7. Partie 5 — Sauvegarde RMAN chiffrée

### Configuration RMAN (extrait de `rman_summary.txt`)

```
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 30 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE ENCRYPTION FOR DATABASE ON;
CONFIGURE ENCRYPTION ALGORITHM 'AES256';
```

### Incident : échec de la première sauvegarde chiffrée (28 octobre 2026)

**Tentative 1** (`tp3_rman.log.clean.txt`, 06:33) : `SET ENCRYPTION ON IDENTIFIED BY ******** ONLY;` puis `BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG ... TAG 'FULL_CHIFFRE'`.

- Sauvegarde des journaux archivés (séquences 8 à 24) : **réussie** (pièce `full_SECBANK_20261028_15_1.bkp`, 45 s).
- Sauvegarde des fichiers de données de `SECBANKPDB` : **échec**.

```
RMAN-03009: failure of backup command on ORA_DISK_1 channel at 10/28/2026 06:34:28
ORA-19836: cannot use passphrase encryption for this backup
```

- Le script a poursuivi avec d'autres jeux (fichiers de la racine CDB, de l'autre PDB et de `PDB$SEED`, tag `TAG20261028T063427`), puis s'est terminé par `RMAN-03002: failure of backup plus archivelog command at 10/28/2026 06:35:53`. Les commandes `RESTORE DATABASE VALIDATE` et `LIST BACKUP SUMMARY` de cette tentative n'ont **pas** été exécutées.

**Cause : non établie.** Les logs montrent le message `ORA-19836` sur les fichiers de `SECBANKPDB` et rien d'autre ; aucune cause n'est avancée ici.

**Tentative 2 / contournement** (`tp3_rman2.log.clean.txt`, 06:37) :

```
SET ENCRYPTION ON IDENTIFIED BY ******** ONLY;
BACKUP AS COMPRESSED BACKUPSET
  TABLESPACE SECBANKPDB:SYSTEM, SECBANKPDB:SYSAUX, SECBANKPDB:UNDOTBS1,
             SECBANKPDB:USERS, SECBANKPDB:AUDIT_DATA
  TAG 'SECBANKPDB_NO_TDE';
BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL NOT BACKED UP TAG 'ARCH_CHIFFRE';
SET DECRYPTION IDENTIFIED BY ********
RESTORE TABLESPACE SECBANKPDB:USERS, SECBANKPDB:AUDIT_DATA VALIDATE;
LIST BACKUP SUMMARY;
```

### Évidence (tentative 2)

```
channel ORA_DISK_1: backup set complete, elapsed time: 00:00:25
...
skipping archived logs of thread 1 from sequence 8 to 24; already backed up
input archived log thread=1 sequence=25 RECID=18 STAMP=1247812655
...
channel ORA_DISK_1: restored backup piece 1
channel ORA_DISK_1: validation complete, elapsed time: 00:00:07
Finished restore at 28-OCT-26
```

`LIST BACKUP SUMMARY` (extrait) : clés 14 (`FULL_CHIFFRE`, archivelogs), 18 (`SECBANKPDB_NO_TDE`) et 20 (`ARCH_CHIFFRE`) à l'état `A`, compressées. Le résumé du 6 novembre contient en plus les clés 22 (28 oct.) et 23 (4 nov.), sans détail dans les logs fournis.

### Analyse

- Le contournement protège par mot de passe les tablespaces `SYSTEM`, `SYSAUX`, `UNDOTBS1`, `USERS` et `AUDIT_DATA` de la PDB ainsi que les journaux archivés ; seule la restauration de `USERS` et `AUDIT_DATA` a été validée (`RESTORE ... VALIDATE`).
- **Les tablespaces `ACCOUNTS_DATA` et `TRANSACTIONS_DATA` ne sont dans aucune sauvegarde du dépôt RMAN.** Vérification faite sur la VM le 6 novembre 2026 :

```
RMAN> LIST BACKUP OF TABLESPACE SECBANKPDB:ACCOUNTS_DATA, SECBANKPDB:TRANSACTIONS_DATA;
specification does not match any backup in the repository
```

  Les données bancaires ne sont donc pas sauvegardées, ni par les deux exécutions du 28 octobre, ni par les sauvegardes antérieures listées (clés 1 à 23). Le contournement `SECBANKPDB_NO_TDE` n'a pas couvert ces deux tablespaces ; la raison de ce choix n'est pas documentée dans les logs.
- Les logs ne précisent pas si les jeux `TAG20261028T063427` (créés malgré l'échec) sont chiffrés ; la requête sur `v$backup_set_details` du 6 novembre le précise (voir « État du chiffrement des jeux de sauvegarde » ci-dessous).

### Complément du 6 novembre 2026 — sauvegarde des tablespaces bancaires

Le constat du §7 a été corrigé le 6 novembre 2026 à 07:09 (`tp3_rman3_20261106.log.clean.txt`). Même méthode que le 28 octobre : chiffrement par phrase de passe (`********` dans le log).

```
SET ENCRYPTION ON IDENTIFIED BY ******** ONLY;
BACKUP AS COMPRESSED BACKUPSET
  TABLESPACE SECBANKPDB:ACCOUNTS_DATA, SECBANKPDB:TRANSACTIONS_DATA TAG 'SECBANKPDB_DATA';
SET DECRYPTION IDENTIFIED BY ********;
RESTORE TABLESPACE SECBANKPDB:ACCOUNTS_DATA, SECBANKPDB:TRANSACTIONS_DATA VALIDATE;
```

```
input datafile file number=00028 name=.../SECBANKPDB/accounts_data01.dbf
input datafile file number=00029 name=.../SECBANKPDB/transactions_data01.dbf
channel ORA_DISK_1: backup set complete, elapsed time: 00:00:01
...
channel ORA_DISK_1: restored backup piece 1
channel ORA_DISK_1: validation complete, elapsed time: 00:00:01
BS Key  Type LV Size       Device Type Elapsed Time Completion Time
24      Full    1.06M      DISK        00:00:01     06-NOV-26
        BP Key: 24   Status: AVAILABLE  Compressed: YES  Tag: SECBANKPDB_DATA
```

Analyse :
- La sauvegarde par phrase de passe de ces deux tablespaces a **réussi** et la validation de restauration également (jeu 24, `AVAILABLE`). Aucun `ORA-19836` n'est apparu pendant cette exécution ; les logs ne permettent pas de dire pourquoi l'erreur du 28 octobre s'était produite.
- Les fichiers sont `accounts_data01.dbf` (n° 28) et `transactions_data01.dbf` (n° 29) ; le 28 octobre, `TRANSACTIONS_DATA` reposait sur `transactions_data02.dbf` (n° 19). Les tablespaces ont donc été recréés entre-temps, ce qui est cohérent avec la reconstruction des données de `BANK_OWNER` du 6 novembre. Cette sauvegarde couvre l'état reconstruit, pas celui du 28 octobre.
- `RESTORE ... VALIDATE` lit la pièce sans restaurer les fichiers : ce n'est pas un test de restauration complète.

### État du chiffrement des jeux de sauvegarde (relevé du 6 novembre 2026)

Requête exécutée en SYSDBA dans `CDB$ROOT` (`evidence/sql/backup_set_details_20261106.log`). La requête initiale sur `v$backup_piece` était erronée (colonne `BS_KEY` inexistante) ; la colonne `TAG` n'existe pas non plus dans `v$backup_set_details`.

```
SELECT bs_key, backup_type, con_id,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') start_time,
       status, compressed, encrypted
FROM v$backup_set_details
ORDER BY bs_key;

    BS_KEY B	 CON_ID START_TIME	     S COM ENC
---------- - ---------- -------------------- - --- ---
	 1 D	      1 2026-09-30 06:20:39  A NO  NO
	 2 D	      1 2026-09-30 07:04:00  A NO  NO
	 3 D	      1 2026-09-30 07:44:02  A NO  NO
	 4 D	      1 2026-10-07 07:31:11  A NO  NO
	 5 L	      0 2026-10-07 08:20:25  A YES NO
	 6 D	      3 2026-10-07 08:20:32  A YES YES
	 7 D	      1 2026-10-07 08:20:57  A YES NO
	 8 D	      2 2026-10-07 08:21:32  A YES NO
	 9 L	      0 2026-10-07 08:21:47  A YES NO
	10 D	      1 2026-10-07 08:21:48  A NO  NO
	11 D	      1 2026-10-14 05:28:16  A NO  NO
	12 D	      1 2026-10-14 05:58:16  A NO  NO
	13 D	      1 2026-10-28 06:10:09  A NO  NO
	14 L	      0 2026-10-28 06:33:42  A YES YES
	15 D	      1 2026-10-28 06:34:28  A YES YES
	16 D	      4 2026-10-28 06:35:13  A YES YES
	17 D	      2 2026-10-28 06:35:38  A YES YES
	18 D	      3 2026-10-28 06:37:08  A YES YES
	19 D	      1 2026-10-28 06:37:34  A NO  YES
	20 L	      0 2026-10-28 06:37:35  A YES YES
	21 D	      1 2026-10-28 06:37:36  A NO  YES
	22 D	      1 2026-10-28 07:46:38  A NO  YES
	23 D	      1 2026-11-04 07:30:08  A NO  YES
	24 D	      3 2026-11-06 07:11:12  A YES YES
	25 D	      1 2026-11-06 07:11:13  A NO  YES

25 rows selected.
```

Constats (strictement lus dans la sortie) :

- Les jeux **14** (`FULL_CHIFFRE`), **18** (`SECBANKPDB_NO_TDE`), **20** (`ARCH_CHIFFRE`) et **24** (`SECBANKPDB_DATA`) sont **chiffrés** (`ENCRYPTED = YES`). Les jeux 15, 16 et 17 (`TAG20261028T063427`, créés malgré l'échec `ORA-19836`) le sont aussi.
- Les jeux **19, 21, 22, 23 et 25** sont également à `YES` (non compressés, `CON_ID` 1). La vue ne dit ni ce qu'ils contiennent ni s'ils sont protégés par phrase de passe ou par le portefeuille ; cela n'est pas établi ici.
- Les jeux **1 à 4, 10, 11, 12 et 13** (30 septembre au 28 octobre 06:10) sont **non chiffrés** (`NO`), de même que les jeux 5, 7, 8 et 9 du 7 octobre. Ils restent dans le dépôt RMAN (fenêtre de rétention : 30 jours) ; leur contenu n'a pas été examiné.
- Le 7 octobre, seul le jeu 6 (`CON_ID` 3) est à `YES`, alors que les jeux 7 et 8 portant le même tag sont à `NO`. Cette différence n'est pas expliquée par les sorties disponibles.
- La colonne `CON_ID` indique le conteneur concerné ; `0` désigne les journaux archivés.
- Cette vue ne dit pas si les pièces sont restaurables : seule la validation de restauration décrite plus haut (jeux 18 et 24) en témoigne, et pour les tablespaces indiqués seulement.

## 8. Exercice final — Incident `analyst1` (28 octobre 2026)

### Chronologie (sources : `security_alerts`, `hardening_log`)

| Heure (28 oct.) | Événement |
|---|---|
| 06:31 → 07:15 | 7 alertes `BRUTE_FORCE` (HIGH) sur `ANALYST1` |
| 07:15 → 08:15 | 5 alertes `MASS_DATA_ACCESS` (CRITICAL) sur `ANALYST1` |
| 07:15:43 | entrée manuelle `INCIDENT` : `ANALYST1` verrouillé après SELECT massif sur `hr_owner.employees` |

### Évidence

```
ALERT_TYPE         SEVERITY   SOURCE_USER    A DETECTED
MASS_DATA_ACCESS   CRITICAL   ANALYST1       N 2026-10-28 08:15
MASS_DATA_ACCESS   CRITICAL   ANALYST1       N 2026-10-28 08:00
MASS_DATA_ACCESS   CRITICAL   ANALYST1       N 2026-10-28 07:45
MASS_DATA_ACCESS   CRITICAL   ANALYST1       N 2026-10-28 07:30
BRUTE_FORCE        HIGH       ANALYST1       N 2026-10-28 07:30
MASS_DATA_ACCESS   CRITICAL   ANALYST1       Y 2026-10-28 07:15
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 07:15
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 07:15
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 07:00
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 06:45
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 06:32
BRUTE_FORCE        HIGH       ANALYST1       Y 2026-10-28 06:31
12 rows selected.

USERNAME                 ACCOUNT_STATUS
ANALYST1                 LOCKED
```

Audit unifié (`verify_tp2.log`) : 6 échecs de connexion pour `ANALYST1`, dernière tentative le 28-OCT-26 à 05:32:25 (horodatage de l'audit).

### Analyse

- Détection : 12 alertes dont 5 non acquittées ; confinement : compte `ANALYST1` verrouillé.
- Les 5 alertes `MASS_DATA_ACCESS` espacées de 15 min correspondent au rythme du job ; le script ne dédoublonne pas (voir §6).
- L'écart d'une heure entre l'audit (05:32) et la première alerte (06:31) n'est pas expliqué par les logs (fuseaux horaires possibles, non vérifié).
- Les étapes « éradication » (acquittement, révocation) et « restauration » de l'énoncé ne sont pas documentées par un log : les 5 alertes restent non acquittées.

### Leçons de l'incident (recommandations, non mises en œuvre)

- **Ce qui a permis l'incident :** `analyst1` pouvait lire massivement `hr_owner.employees` (plus de 100 `SELECT` sur la fenêtre d'une heure d'après les alertes).
- **Ce qui l'a détecté :** l'audit unifié (`POL_EMPLOYES`, `POL_CONNEXIONS`) et le job de détection toutes les 15 minutes (alertes `BRUTE_FORCE` et `MASS_DATA_ACCESS`).
- **À renforcer :** limiter les droits de `analyst1`, dédoublonner les alertes, acquitter et traiter les alertes ouvertes, et revoir les seuils.

## 9. Conclusion

Le durcissement des comptes et des packages est vérifié, le réseau est configuré en chiffrement/intégrité obligatoires, la détection (alertes + job 15 min, 100 exécutions, 0 échec) a levé 12 alertes lors de l'incident `analyst1`, et un contournement RMAN a permis de sauvegarder une partie de la PDB après l'échec `ORA-19836` ; les tablespaces bancaires (`ACCOUNTS_DATA`, `TRANSACTIONS_DATA`), absents de toute sauvegarde jusque-là, n'ont été sauvegardés que le 6 novembre 2026.

## 10. Limites

- Le script du dépôt est une **réimplémentation propre** : le `hardening_log` réel contient des entrées manuelles du 7 octobre dont le texte diffère de celui écrit par le script ; de même, le message affiché par la procédure vulnérable en base (`SQL exécuté :`) diffère de celui du script (`SQL:`).
- Cause d'`ORA-19836` **non élucidée** ; `ACCOUNTS_DATA` et `TRANSACTIONS_DATA` n'étaient dans aucune sauvegarde avant le 6 novembre 2026 (corrigé, voir complément §7) ; les sauvegardes du 28 octobre ne couvrent pas les données bancaires d'origine.
- Démonstration d'injection SQL **ré-exécutée le 6 novembre 2026** (sortie d'origine non conservée).
- Plusieurs sauvegardes antérieures au 28 octobre 06:33 sont **non chiffrées** (jeux 1 à 4, 10 à 13 et 5, 7, 8, 9) ; elles n'ont pas été supprimées ni examinées.
- `hr_owner.employees` et `analyst1` sont des substituts.
- Données de `BANK_OWNER` reconstruites le 6 novembre 2026 ; travail réel du 30 septembre au 28 octobre.
- Informations redactées : IP de la VM et du poste d'administration, nom du poste client, PDB étrangère au projet.
