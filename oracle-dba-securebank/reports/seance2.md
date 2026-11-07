# Séance 2 — Gestion des accès bancaires et chiffrement des données

**Projet SecureBank — Oracle Database 19c EE** · Ihab Zaghdane · EIDIA, UEMF Fès

> Mots de passe : `<TDE_PASSWORD>` ou omis. Travail réel du 30 septembre au 28 octobre 2026 ; vérifications relancées le 6 novembre 2026 (`verify_tp2.sql`, 06:21) ; données de `BANK_OWNER` reconstruites ce jour-là.
> Les éléments **non confirmés** ou **non capturés** sont signalés comme tels.

## 1. Objectif

Préparer l'infrastructure (tablespaces, ARCHIVELOG, TDE), créer le schéma bancaire, une hiérarchie de rôles, un profil de mots de passe, des utilisateurs applicatifs, l'isolation par agence (VPD) et l'audit unifié.

## 2. Environnement

| Élément | Valeur |
|---|---|
| Système | Oracle Linux 8.8, `secbank.local`, utilisateur `oracle` |
| Base | CDB `SECBANK` / PDB `SECBANKPDB` |
| Schémas | `bank_owner`, `audit_mgr`, `hr_owner` |
| Utilisateurs | `advisor_paris_01`, `account_mgr_paris_01`, `advisor_lyon_03`, `security_auditor` |
| Rôles | `bank_employee`, `bank_reader`, `bank_operator`, `bank_auditor` |

## 3. Prérequis (anciennement « TP1 » du README)

### 3.1 Tablespaces

**Incident (30 septembre 2026)** — création de `TRANSACTIONS_DATA` en 50 Go :

```
SQL> CREATE TABLESPACE TRANSACTIONS_DATA
  DATAFILE '/u01/app/oracle/oradata/SECBANK/transactions_data01.dbf'
  SIZE 50G AUTOEXTEND ON NEXT 500M MAXSIZE UNLIMITED;
ORA-01144: File size (6553600 blocks) exceeds maximum of 4194303 blocks
```

Une seconde tentative a échoué sur `ORA-02494: invalid or missing maximum file size in MAXSIZE clause` (ligne `AUTOEXTEND` mal saisie en saisie interactive), puis une troisième sur le même `ORA-01144`. Le fichier n'est pas de type `BIGFILE` (`BIG = NO` dans la vérification) : la limite d'un fichier « smallfile » s'applique.

**Correction** *(d'après l'historique shell, non fourni dans l'archive)* : `accounts_data` et `transactions_data` recréés avec `SIZE 50M AUTOEXTEND ON`.

```
TABLESPACE_NAME      BIG ENC STATUS
ACCOUNTS_DATA        NO  NO  ONLINE
AUDIT_DATA           NO  NO  ONLINE
TRANSACTIONS_DATA    NO  NO  ONLINE
```

### 3.2 Mode ARCHIVELOG

État constaté :

```
NAME                 LOG_MODE
SECBANK              ARCHIVELOG
```

La Séance 1 se terminait en `NOARCHIVELOG` (rapport Séance 1). Le journal d'alertes de l'instance (`alert_SECBANK.log`, extrait : `evidence/logs/alert_archivelog_extract.txt`) contient :

```
Completed: ALTER DATABASE   MOUNT
2026-09-30T06:10:41.452385-04:00
ALTER DATABASE ARCHIVELOG
Completed: ALTER DATABASE ARCHIVELOG
2026-09-30T06:10:46.875743-04:00
ALTER DATABASE OPEN
```

Le passage en `ARCHIVELOG` date donc du **30 septembre 2026 à 06:10** (heure du journal, UTC−04:00), entre un `MOUNT` et un `OPEN`, ce qui correspond à la séquence standard :

```sql
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

Le `SHUTDOWN`/`STARTUP` qui précède ne figure pas dans l'extrait relevé.

### 3.3 TDE (keystore)

D'après l'historique shell *(non fourni)* :

```sql
ALTER SYSTEM SET WALLET_ROOT = '<chemin>' SCOPE=SPFILE;
ALTER SYSTEM SET TDE_CONFIGURATION = 'KEYSTORE_CONFIGURATION=FILE';
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE ... IDENTIFIED BY <TDE_PASSWORD>;
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY <TDE_PASSWORD> CONTAINER=ALL;
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE ...;
```

État des clés maîtres constaté sur la VM le 6 novembre 2026 (`v$encryption_keys`) :

```
CREATION_TIME                          ACTIVATION_TIME                        CON_ID
28-OCT-26 11.22.31.045159 AM +00:00    28-OCT-26 11.22.31.045162 AM +00:00         1
28-OCT-26 11.24.05.014680 AM +00:00    28-OCT-26 11.24.05.014683 AM +00:00         3
```

Une clé maître existe pour la racine (CON_ID 1) et pour `SECBANKPDB` (CON_ID 3), toutes deux créées le 28 octobre 2026 (heures en UTC). Ces dates ne disent pas quelle forme de la commande a été utilisée.

**Commande de création de la clé maître (`ADMINISTER KEY MANAGEMENT SET KEY`) : non retrouvée dans l'historique.** L'énoncé propose `ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY <TDE_PASSWORD> WITH BACKUP;` ; rien ne confirme que cette forme a été utilisée (l'énoncé configure le wallet via `sqlnet.ora`, alors que la VM utilise `WALLET_ROOT`).

> **Sécurité :** le mot de passe du keystore a été exposé dans l'historique shell et dans une conversation. La commande `history -c` a été exécutée sur la VM le 6 novembre 2026. La **rotation** du mot de passe (`ADMINISTER KEY MANAGEMENT ALTER KEYSTORE PASSWORD ... WITH BACKUP`) n'a **pas** été réalisée : le mot de passe actuel n'est plus connu.

## 4. Partie 1 — Tables et données

`sql/02_tp2_access_control.sql` crée `customers`, `accounts`, `transactions`, `user_branch_mapping` (`secrets_rh` est ajoutée en Séance 4). Écarts par rapport à l'énoncé : `ssn VARCHAR2(15)` et `account_number VARCHAR2(24)` (les données d'exemple ne tenaient pas dans les tailles d'origine).

```
TABLE_NAME             TABLESPACE_NAME
ACCOUNTS               ACCOUNTS_DATA
CUSTOMERS              ACCOUNTS_DATA
SECRETS_RH             ACCOUNTS_DATA
TRANSACTIONS           TRANSACTIONS_DATA
USER_BRANCH_MAPPING    ACCOUNTS_DATA

CUSTOMERS 4 · ACCOUNTS 5 · TRANSACTIONS 4 · USER_BRANCH_MAPPING 3
```

## 5. Partie 2 — Hiérarchie de rôles

```sql
GRANT bank_employee TO bank_reader;   -- lecture
GRANT bank_reader   TO bank_operator; -- + INSERT/UPDATE
GRANT bank_employee TO bank_auditor;  -- + SELECT ANY TABLE, SELECT_CATALOG_ROLE
```

```
ROLE             GRANTED_ROLE
BANK_AUDITOR     AUDIT_VIEWER
BANK_AUDITOR     BANK_EMPLOYEE
BANK_AUDITOR     SELECT_CATALOG_ROLE
BANK_OPERATOR    BANK_READER
BANK_READER      BANK_EMPLOYEE
```

Privilèges objet : `BANK_READER` a `SELECT` sur `ACCOUNTS`, `CUSTOMERS`, `TRANSACTIONS` ; `BANK_OPERATOR` a `INSERT`/`UPDATE` sur `ACCOUNTS` et `CUSTOMERS`, `INSERT` sur `TRANSACTIONS` ; `BANK_AUDITOR` a `SELECT ANY TABLE`.

Constats : (a) la base montre `BANK_AUDITOR` avec le rôle `AUDIT_VIEWER`, que `02_tp2_access_control.sql` n'accorde pas ; (b) `BANK_READER` a `EXECUTE` sur `CHERCHER_CLIENT`, accordé par le script de la Séance 4.

## 6. Partie 3 — Profil et utilisateurs applicatifs

Profil `SECBANK_USER_PROFILE` : `FAILED_LOGIN_ATTEMPTS 3`, `PASSWORD_LIFE_TIME 60`, `PASSWORD_LOCK_TIME .0833` (2 h), `PASSWORD_REUSE_TIME 365`, `PASSWORD_REUSE_MAX 6`, `PASSWORD_GRACE_TIME 5`, `SESSIONS_PER_USER 2`, `IDLE_TIME 30`, `CONNECT_TIME 480`.

```
ACCOUNT_MGR_PARIS_01   BANK_OPERATOR   YES (défaut)
ADVISOR_LYON_03        BANK_READER     YES
ADVISOR_PARIS_01       BANK_READER     YES
SECURITY_AUDITOR       BANK_AUDITOR    YES
```

Les quatre comptes utilisent le profil et sont `OPEN`.

## 7. Partie 4 — TDE : wallet, tablespaces, colonne `SSN`

```
CON_ID WRL_PARAMETER   STATUS    WALLET_TYPE
     3                 OPEN      AUTOLOGIN
```

```
-- tablespaces chiffrés
no rows selected

OWNER        TABLE_NAME   COLUMN_NAME   ENCRYPTION_ALG
BANK_OWNER   CUSTOMERS    SSN           AES 256 bits key
```

### Analyse

Le wallet est ouvert en mode auto-login ; la colonne `SSN` est chiffrée en AES256 ; **aucun tablespace n'est chiffré** (`ENC = NO`) — l'énoncé demandait le chiffrement de `ACCOUNTS_DATA` et `TRANSACTIONS_DATA`, qui n'est pas réalisé dans l'état constaté. La colonne est déclarée `ENCRYPT USING 'AES256' NO SALT` (le mode sans `SALT` permet l'indexation mais divulgue les valeurs identiques).

## 8. Partie 5 — VPD (isolation par agence)

Fonction `bank_owner.branch_security_policy` : renvoie `NULL` si l'utilisateur a `EXEMPT ACCESS POLICY`, sinon `branch_id = '<agence>'` d'après `user_branch_mapping`, sinon `1=0`. `update_check => TRUE` est nécessaire avec `INSERT`.

```
OBJECT_NAME      POLICY_NAME                      SEL INS UPD DEL ENA
ACCOUNTS         BRANCH_ISOLATION_ACCOUNTS        YES YES YES YES YES
CUSTOMERS        BRANCH_ISOLATION_CUSTOMERS       YES YES YES YES YES
TRANSACTIONS     BRANCH_ISOLATION_TRANSACTIONS    YES YES YES YES YES

GRANTEE          PRIVILEGE
GSMUSER_ROLE     EXEMPT ACCESS POLICY
MDSYS            EXEMPT ACCESS POLICY
SECURITY_AUDITOR EXEMPT ACCESS POLICY
```

### Résultat rapporté — sortie non archivée

Preuve en direct (6 novembre 2026), **sans sortie dans l'archive** : `account_mgr_paris_01` ne voit que les comptes `PARIS_01` n° 1 et 2 et le client Dupont.

## 9. Partie 6 — Audit unifié

Cinq politiques actives (`BY USER`) : `SECBANK_ACCOUNT_ACCESS`, `SECBANK_BALANCE_CHANGES`, `SECBANK_FAILED_LOGINS`, `SECBANK_PRIVILEGE_CHANGES`, `SECBANK_TRANSACTIONS`.

Extrait des événements (utilisateurs applicatifs) :

```
DBUSERNAME             ACTION_NAME  OBJECT_NAME    RETURN_CODE   NB
ACCOUNT_MGR_PARIS_01   INSERT       TRANSACTIONS             0    1
ACCOUNT_MGR_PARIS_01   UPDATE       ACCOUNTS                 0    1
ADVISOR_PARIS_01       UPDATE       ACCOUNTS              2004    1
SECURITY_AUDITOR       SELECT       CUSTOMERS                0    1
SYS                    INSERT       ACCOUNTS             12899    1
```

Échecs de connexion :

```
DBUSERNAME      USERHOST         NB_ECHECS  DERNIERE_TENTATIVE
ANALYST1        secbank.local            6  28-OCT-26 05.32.25 AM
TEST_APP        secbank.local            2  28-OCT-26 06.38.55 AM
BANK_OWNER      secbank.local            1  30-SEP-26 06.06.02 AM
ADVISOR_PARIS_01 secbank.local           1  07-OCT-26 06.34.46 AM
SECBANK_APP     <CLIENT_WINDOWS>         1  04-NOV-26 07.14.25 AM
```

### Analyse

`ADVISOR_PARIS_01` (rôle lecture seule) a tenté un `UPDATE` sur `ACCOUNTS` : retour `2004`, tracé par l'audit. Le code `12899` côté `SYS` est cohérent avec l'élargissement de `ssn` et `account_number` signalé en partie 1 (lecture, non vérifiée dans un log d'erreur).

## 10. Exercice final — enquête sur une transaction suspecte

L'énoncé suppose un virement de 10 000 € du 25 décembre sur le compte 1. **Ce scénario n'existe pas dans la base** (aucune transaction de ce montant). La méthode de l'énoncé a donc été appliquée aux données réelles, ré-exécutée le 6 novembre 2026 en SYSDBA (sorties brutes : `evidence/sql/lot1_demos_20261106.log`).

**Étape 1 — transactions du compte 1** (données reconstruites le 6 novembre) :

```
TRANSACTION_ID TRANSACTION_TYPE  AMOUNT  TRANSACTION_DATE              DESCRIPTION   CREATED_BY
             2 WITHDRAWAL          -200   06-NOV-26 06.11.54.767261 AM  Retrait DAB   ATM_PARIS_01
             1 DEPOSIT             1000   06-NOV-26 06.11.54.765701 AM  D??p??t esp??ces SYS
```

**Étape 2 — `INSERT` sur `TRANSACTIONS` dans l'audit unifié** :

```
T                    DBUSERNAME            USERHOST       CLIENT_PROGRAM_NAME              SQL_TEXT
2026-11-06 06:11:54  SYS                   secbank.local  sqlplus@secbank.local (TNS V1-V3) INSERT INTO transactions (account_id,transaction_type,amount   (4 lignes)
2026-11-04 07:23:05  SYS                   secbank.local  sqlplus@secbank.local (TNS V1-V3) INSERT INTO secbank_app.transactions SELECT level, MOD(level
2026-10-07 06:34:23  ACCOUNT_MGR_PARIS_01  secbank.local  sqlplus@secbank.local (TNS V1-V3) INSERT INTO bank_owner.transactions (account_id, transaction
6 rows selected.
```

**Étape 3 — actions de `ACCOUNT_MGR_PARIS_01`** (16 événements, tous avec `RETURN_CODE = 0`) : le 7 octobre 06:34:23, des `SELECT` sur `DUAL` et `USER_BRANCH_MAPPING`, un `UPDATE` sur `ACCOUNTS` et un `INSERT` sur `TRANSACTIONS` ; le 6 novembre 06:43, des `SELECT` sur `ACCOUNTS` et `CUSTOMERS`.

**Étapes 4 et 5 — droits et agence** :

```
GRANTEE               GRANTED_ROLE
ACCOUNT_MGR_PARIS_01  BANK_OPERATOR

dba_sys_privs : no rows selected

USERNAME              BRANCH_ID  ROLE_TYPE
ADVISOR_PARIS_01      PARIS_01   ADVISOR
ACCOUNT_MGR_PARIS_01  PARIS_01   MANAGER
ADVISOR_LYON_03       LYON_03    ADVISOR
```

### Réponses aux questions de l'énoncé

- **Qui a inséré ?** Parmi les comptes applicatifs, seul `ACCOUNT_MGR_PARIS_01` apparaît (7 octobre 2026, 06:34:23). Les autres `INSERT` sont faits par `SYS` : les 4 du 6 novembre correspondent à la reconstruction des données.
- **Avait-il le droit ?** Oui : son rôle `BANK_OPERATOR` accorde `INSERT` sur `TRANSACTIONS` (voir §5) ; il n'a aucun privilège système direct.
- **Agence :** `PARIS_01` (rôle `MANAGER`). D'après `02_tp2_access_control.sql`, le compte 1 appartient aussi à `PARIS_01` ; la ligne insérée le 7 octobre n'existe plus (données reconstruites). Aucune violation de VPD n'est visible dans ces sorties.
- **Origine de la connexion :** `secbank.local`, programme `sqlplus@secbank.local`, donc depuis la VM elle-même.
- **Autres transactions suspectes ?** L'audit montre aussi un `INSERT` de `SYS` le 4 novembre 2026 à 07:23:05 dans `secbank_app.transactions` (schéma hors du schéma `bank_owner`). Il n'a pas été investigué ; son origine n'est pas établie ici.
- **Actions correctives (recommandations, non appliquées)** : verrouiller le compte, fermer ses sessions, révoquer temporairement `BANK_OPERATOR`, annuler la transaction avec validation compliance, renforcer la surveillance.

## 11. Conclusion

Le schéma, les rôles, le profil, le chiffrement de la colonne `SSN`, les trois politiques VPD et les cinq politiques d'audit sont en place et vérifiés par `verify_tp2.log`. Le chiffrement des tablespaces demandé n'est pas observé.

## 12. Limites

- Commande `SET KEY` **non retrouvée** ; passage en ARCHIVELOG daté par le journal d'alertes (30 septembre 2026, 06:10), sans le `SHUTDOWN`/`STARTUP` qui précède (voir §3.2 et §3.3) ; historique shell non fourni, étapes TDE et tablespaces reprises des notes.
- Preuve VPD de session (6 novembre) **non archivée**.
- Aucun tablespace chiffré ; `ssn` chiffré avec `NO SALT`.
- Écart base / script : rôle `AUDIT_VIEWER` de `BANK_AUDITOR`.
- Données reconstruites le 6 novembre 2026 ; travail réel du 30 septembre au 28 octobre.
- Redactions : IP de la VM, nom du poste client, PDB étrangère au projet. Le journal brut de session de la Séance 2 n'est pas publié (séquences d'échappement du terminal, commandes collées dans le shell).
