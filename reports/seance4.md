# Séance 4 — Sécurité avancée : Privilege Analysis, droits du définisseur, encodage vs chiffrement, Flashback

**Projet SecureBank — Oracle Database 19c EE** · Ihab Zaghdane · EIDIA, UEMF Fès

> Les vérifications ont été exécutées le 6 novembre 2026 (`verify_tp4.sql`, 06:21) sur `SECBANKPDB`. Les données de `BANK_OWNER` ont été reconstruites ce jour-là. Les démonstrations d'injection (fuite de `PRIME_DG`) et de `DBMS_CRYPTO` ont été **ré-exécutées le 6 novembre 2026** : les sorties d'origine n'ont pas été conservées.

## 1. Objectif

1. Identifier les privilèges réellement utilisés par un compte applicatif (Privilege Analysis) et retirer l'excédent.
2. Démontrer une injection SQL via une fonction à droits du définisseur, puis la corriger.
3. Distinguer encodage (Base64) et chiffrement (AES256).
4. Détecter et annuler une fraude sur un solde avec Flashback.

## 2. Environnement

| Élément | Valeur |
|---|---|
| Base | CDB `SECBANK` / PDB `SECBANKPDB` (service `SECBANKPDB.local`) |
| Schéma | `bank_owner` (`customers`, `accounts`, `transactions`, `secrets_rh`) |
| Comptes | `account_mgr_paris_01` (rôle `BANK_OPERATOR`), `bank_reader` |
| Scripts | `sql/04a`, `04b`, `04c`, `verify_tp4.sql` |

Différences avec l'énoncé : démonstration Flashback sur le compte `5` avec un débit de 40000 (le compte 105 n'existe pas, et 50000 viole `chk_balance`) ; `SUPPLEMENTAL LOG DATA` activé pour les requêtes de transactions Flashback.

## 3. Partie 1 — Privilege Analysis

### Étapes et commandes

```sql
-- 04a (SYSDBA) : donner volontairement un privilège excessif, puis capturer
GRANT SELECT ANY TABLE TO bank_operator;
BEGIN
  DBMS_PRIVILEGE_CAPTURE.CREATE_CAPTURE(name => 'tp4_capture',
      type => DBMS_PRIVILEGE_CAPTURE.G_DATABASE);
  DBMS_PRIVILEGE_CAPTURE.ENABLE_CAPTURE('tp4_capture');
END;
/
-- en tant que account_mgr_paris_01 : deux requêtes
SELECT account_id, balance FROM bank_owner.accounts WHERE branch_id = 'PARIS_01';
SELECT last_name FROM bank_owner.customers;
-- 04b (SYSDBA) : arrêt, résultat, correction
DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('tp4_capture');
DBMS_PRIVILEGE_CAPTURE.GENERATE_RESULT('tp4_capture');
REVOKE SELECT ANY TABLE FROM bank_operator;
```

La capture est de type `G_DATABASE` : elle enregistre tous les comptes de la base, pas seulement `account_mgr_paris_01`.

### Évidence (`verify_tp4.log`)

```
NAME           TYPE         E
-------------- ------------ -
tp4_capture    DATABASE     N
```

La capture est désactivée (`E = N`). La requête sur `dba_used_privs` renvoie 8 lignes, uniquement des objets internes (`AUDIT_MGR`, `AUDSYS`, `MDSYS`). La requête sur `dba_unused_privs` renvoie **54260 lignes**, essentiellement des comptes Oracle internes (omises du log publié, voir `evidence/sql/verify_tp4.log`).

Après le `REVOKE` :

```
-- apres REVOKE : SELECT ANY TABLE ne doit plus etre accorde a BANK_OPERATOR

no rows selected
```

`BANK_OPERATOR` n'a donc plus aucun privilège système.

### Évidence (`tp4_priv.log`, capture régénérée puis lue pour `account_mgr_paris_01`)

Privilèges **utilisés** :

```
USERNAME               SYS_PRIV         OBJECT_OWNER   OBJECT_NAME
ACCOUNT_MGR_PARIS_01                    SYS            DUAL
ACCOUNT_MGR_PARIS_01                    BANK_OWNER     CUSTOMERS
ACCOUNT_MGR_PARIS_01                    BANK_OWNER     ACCOUNTS
ACCOUNT_MGR_PARIS_01   CREATE SESSION
ACCOUNT_MGR_PARIS_01                    SYS            DBMS_APPLICATION_INFO
```

Privilèges **accordés mais jamais utilisés** (la requête n'affiche que la colonne `SYS_PRIV`) :

```
USERNAME               SYS_PRIV
ACCOUNT_MGR_PARIS_01                      (5 lignes : colonne vide)
ACCOUNT_MGR_PARIS_01   SELECT ANY TABLE
ACCOUNT_MGR_PARIS_01                      (2 lignes : colonne vide)
8 rows selected.
```

Correction puis contrôle :

```
SQL> REVOKE SELECT ANY TABLE FROM bank_operator;
Revoke succeeded.
SQL> SELECT grantee, privilege FROM dba_sys_privs WHERE grantee = 'BANK_OPERATOR';
no rows selected
```

### Lecture

- Utilisés : `CREATE SESSION` et `SELECT` sur `bank_owner.customers` et `bank_owner.accounts` (plus `DUAL` et `DBMS_APPLICATION_INFO`, objets internes).
- Parmi les 8 privilèges inutilisés, **seul `SELECT ANY TABLE` est identifiable** : les 7 autres sont des privilèges objet, que la requête ne détaille pas (colonnes `obj_priv` et `object_name` non demandées). D'après les droits accordés à `BANK_OPERATOR` (`02_tp2_access_control.sql`), il s'agit vraisemblablement de `INSERT`/`UPDATE` sur `customers` et `accounts`, `INSERT` sur `transactions`, du `SELECT` sur `transactions` et de `EXECUTE` sur `chercher_client` ; ce rapprochement est une déduction, non une sortie observée.

### Analyse et limite

La fenêtre de capture ne contient que **deux `SELECT`** : « non utilisé » signifie « non utilisé dans cette fenêtre ». Seul `SELECT ANY TABLE` est clairement excessif pour ce rôle ; les droits `INSERT`/`UPDATE` sont attendus d'un `BANK_OPERATOR` et ne doivent pas être retirés sur cette seule base.

## 4. Partie 2 — Droits du définisseur et injection SQL

### Étapes (`04c`)

1. Création de `bank_owner.secrets_rh` avec la ligne `('PRIME_DG', 'confidentiel : 45000 EUR')`.
2. Fonction **vulnérable** `bank_owner.chercher_client` : requête dynamique par concaténation, `GRANT EXECUTE` à `bank_reader`.
3. Appel de la fonction vulnérable avec une charge d'injection (voir ci-dessous).
4. Fonction **corrigée** : variable liée `:1` avec `USING`.
5. Même charge sur la version corrigée.

### Évidence

Code de la fonction en base (`dba_source`) :

```sql
FUNCTION            chercher_client(p_nom IN VARCHAR2)
  RETURN VARCHAR2 AS v_res VARCHAR2(400);
BEGIN
  EXECUTE IMMEDIATE
    'SELECT MAX(last_name) FROM customers WHERE last_name = :1'
    INTO v_res USING p_nom;
  RETURN NVL(v_res, '(aucun)');
END;
```

```
OBJECT_NAME            OBJECT_TYPE             STATUS
CHERCHER_CLIENT        FUNCTION                VALID
SECRETS_RH             TABLE                   VALID

RESULTAT
(aucun)
```

La charge d'injection ne renvoie pas le secret sur la version corrigée.

### Fuite de `PRIME_DG` (ré-exécutée le 6 novembre 2026)

La fonction en base est déjà la version corrigée. La démonstration a donc été rejouée sur une **copie temporaire vulnérable** (`bank_owner.chercher_client_demo`, même code par concaténation que dans `04c`), créée puis supprimée ; `chercher_client` n'a pas été modifiée.

```
SQL> SELECT bank_owner.chercher_client_demo('Dupont') AS normal FROM dual;
NORMAL
--------------------
(aucun)

SQL> SELECT bank_owner.chercher_client_demo('x'' HAVING 1=0 UNION SELECT valeur FROM bank_owner.secrets_rh WHERE cle=''PRIME_DG''--') AS attaque FROM dual;
ATTAQUE
--------------------
confidentiel : 45000 EUR

SQL> DROP FUNCTION bank_owner.chercher_client_demo;
Function dropped.
```

La fonction vulnérable divulgue la valeur de `secrets_rh`, table que l'appelant (`bank_reader`) ne peut pas lire directement : la fonction s'exécute avec les droits de son propriétaire (`bank_owner`). Le `HAVING 1=0` vide la partie d'origine de la requête pour qu'il ne reste qu'une ligne, celle du secret.

Même charge sur la **fonction corrigée** `chercher_client` (variable liée), ré-exécutée le 6 novembre 2026 :

```
SQL> SELECT bank_owner.chercher_client('x'' HAVING 1=0 UNION SELECT valeur FROM bank_owner.secrets_rh WHERE cle=''PRIME_DG''--') AS attaque_corrigee FROM dual;
ATTAQUE_CORRIGEE
--------------------
(aucun)
```

La charge est traitée comme un simple nom de client : le secret ne sort pas. Sortie brute : `evidence/sql/lot1_demos_20261106.log`.

Le texte du code en base diffère légèrement de la mise en forme du script `04c` (même logique). Sortie brute : `evidence/sql/tp3_tp4_demos_20261106.log`.

## 5. Partie 3 — Encodage vs chiffrement

### Évidence

```
ENCODE_BASE64
NDUzOTE0ODgwMzQzNjQ2Nw==
```

Le numéro de test `4539148803436467` est encodé en Base64 ; l'opération est **réversible sans clé**.

Le bloc PL/SQL `DBMS_CRYPTO` (AES256, CBC, PKCS5) s'est terminé par `PL/SQL procedure successfully completed.`

### `DBMS_CRYPTO` (ré-exécuté le 6 novembre 2026)

```
chiffre : 3F4C599369673CDD2BEBB69A341D82A37DCD837CB4A87477B474EFA8733F3BF0
dechiffre : 4539148803436467

PL/SQL procedure successfully completed.
```

Le numéro est chiffré en AES256 (CBC, PKCS5) puis retrouvé uniquement avec la clé. La clé du script est une **clé de démonstration codée en dur** (`04c`) : elle ne doit jamais servir hors laboratoire ; une vraie clé se gère dans un keystore ou un HSM.

## 6. Partie 4 — Flashback

### Évidence

Comptes (état au 6 novembre) : le compte `5` (`FR7612345000012345678905`) a un solde de `45600.25`. `SUPP_LOG = YES`, `undo_retention = 900`.

Versions du compte 5 (fenêtre depuis 06:13) :

```
VERSIONS_XID         O VERSIONS_STARTTIME                BALANCE
04000D0029030000     U 06-NOV-26 06.17.17 AM              5600.25
03000E0070030000     U 06-NOV-26 06.18.38 AM             45600.25
0700150018030000     U 06-NOV-26 06.19.05 AM              5600.25
0A0014000D030000     U 06-NOV-26 06.19.38 AM             45600.25
                                                          45600.25
```

Requêtes d'annulation (`flashback_transaction_query`) :

```
update "BANK_OWNER"."ACCOUNTS" set "BALANCE" = '5600.25'  where ROWID = 'AAAR5WAAcAAAACtAAE';
update "BANK_OWNER"."ACCOUNTS" set "BALANCE" = '45600.25' where ROWID = 'AAAR5WAAcAAAACtAAE';
update "BANK_OWNER"."ACCOUNTS" set "BALANCE" = '5600.25'  where ROWID = 'AAAR5WAAcAAAACtAAE';
3 rows selected.
```

### Flashback Query (étape 2 de l'énoncé, ré-exécutée le 6 novembre 2026)

Même débit de 40000 sur le compte `5`, puis lecture du solde cinq minutes plus tôt et rétablissement manuel :

```
AVANT            45600.25
UPDATE bank_owner.accounts SET balance = balance - 40000 WHERE account_id = 5;  COMMIT;
APRES             5600.25
SELECT balance FROM bank_owner.accounts AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '5' MINUTE) WHERE account_id = 5;
FLASHBACK_5MIN   45600.25
UPDATE bank_owner.accounts SET balance = balance + 40000 WHERE account_id = 5;  COMMIT;
RETABLI          45600.25
```

La Flashback Query retrouve le solde d'avant la fraude (45600.25) ; l'écart avec le solde après débit vaut 40000. Cette séquence s'ajoute aux deux exécutions décrites ci-dessous.

### Analyse

- Le débit de 40000 fait passer le solde de 45600.25 à 5600.25 ; le `undo_sql` portant `45600.25` le rétablit.
- La démonstration a été jouée **deux fois** (4 changements de version, retour final à 45600.25).
- La requête de transactions Flashback renvoie **3 lignes** pour 4 changements de version ; les logs n'expliquent pas l'écart.

## 7. Conclusion

La Privilege Analysis a mis en évidence `SELECT ANY TABLE` comme privilège excessif de `BANK_OPERATOR` et celui-ci a été révoqué (vérifié). Une fonction par concaténation divulgue `PRIME_DG` (démonstration ré-exécutée) ; la fonction corrigée par variable liée ne renvoie pas le secret avec la même charge. Le Base64 est démontré réversible ; Flashback a permis de repérer et d'annuler une fraude sur le compte 5.

## 8. Limites

- Fenêtre de capture : deux `SELECT` seulement. Les 7 privilèges objet inutilisés ne sont pas nommés dans la sortie (voir §3).
- Démonstrations de la fuite `PRIME_DG` et de `DBMS_CRYPTO` **ré-exécutées le 6 novembre 2026** (sorties d'origine non conservées).
- Clé AES de démonstration codée en dur.
- Données `BANK_OWNER` reconstruites le 6 novembre 2026 ; travail réel antérieur.
- Écart 3 lignes / 4 versions Flashback non expliqué.
