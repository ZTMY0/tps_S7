# SecureNotesLab - Challenge (TP2)

Repo : https://github.com/ZTMY0/tps_S7/tree/main/android-security/tp-recap-challenge

## Contexte

Nouvelle version de SecureNotesLab fournie sans liste de vulnerabilites. Chaque faille a ete identifiee par revue de code, puis prouvee par une attaque reelle (adb et/ou AttackLab) avant correction.

## Vulnerabilites

**C1 - Path traversal (NoteDetailActivity)**
Cause : activite exportee, construit `File(filesDir, "notes/$nomFichier")` sans valider l'extra `cheminFichier`.
Preuve : `adb shell am start -n com.lab.securenotes/.NoteDetailActivity -e cheminFichier "../../databases/notes.db"` affiche le contenu brut de la base SQLite.
Cause racine : aucune verification du chemin resultant, activite exportee.

**C2 - ProfilActivity accessible sans authentification**
Cause : activite exportee, n'a jamais verifie `Session.estConnecte`.
Preuve : `adb shell am start -n com.lab.securenotes/.ProfilActivity` affiche le token et le niveau administrateur sans connexion.
Cause racine : aucune verification de session, activite exportee.

**C3 - Cle API dans logcat**
Cause : `Log.d` affiche `SyncManager.API_KEY` en clair a chaque ouverture de session.
Preuve : `adb logcat` apres connexion montre `SNL-SYNC-98213` en clair.
Cause racine : logcat n'est pas un canal protege.

**C4 - Permission ContentProvider illusoire**
Cause : `NotesProvider` protege par une permission `protectionLevel="normal"`, accordee automatiquement a l'installation.
Preuve : AttackLab declare la permission et interroge le provider sans intervention de l'utilisateur.
Cause racine : `normal` n'empeche pas une app malveillante determinee.

**C6 - Pas de controle d'acces par ligne**
Cause : `NotesProvider.query()` ignore `selection`/`selectionArgs` (codes en dur a `null`), retourne toutes les lignes.
Preuve : via AttackLab, lecture des notes d'alice ET de bob depuis une app tierce.
Cause racine : le filtrage par ligne est une responsabilite applicative, jamais implementee.

**C5 - Cle API codee en dur dans le bytecode**
Cause : `API_KEY` est une constante compilee dans `classes3.dex`, independamment de C3.
Preuve : extraction de l'APK, recherche binaire de la chaine dans les fichiers dex -> trouvee.
Cause racine : aucun chiffrement/obfuscation du secret.

**C7 - Injection SQL via sortOrder**
Cause : `sortOrder` transmis tel quel a `db.query(...)`, sans validation.
Preuve : `--es sortOrder "(SELECT 1 FROM table_qui_n_existe_pas)"` provoque une `SQLiteException` confirmant l'execution de la sous-requete injectee.
Cause racine : aucune validation des parametres avant utilisation SQL.

## Corrections

| Vuln | Correction | Retestee |
|------|------------|----------|
| C1 | Validation via `canonicalPath`, chemin force dans `notes/` | Oui |
| C2 | Verif `Session.estConnecte` + `exported="false"` | Oui |
| C3 | Suppression cle en dur + `Log.d` associes | Oui |
| C4 | `protectionLevel` passe a `signature` | Oui |
| C5 | Suppression de la constante en dur | Oui |
| C6 | `selection`/`selectionArgs` reellement transmis | Oui (protection principale : C4) |
| C7 | Liste blanche de colonnes pour `sortOrder` | Oui (protection principale : C4) |