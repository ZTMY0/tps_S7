# Audit de sécurité Android : MobileVaultLab

## Contexte et méthode

MobileVaultLab est une application Android de démonstration (package `edu.lab.mobilevault`, Kotlin, vues XML, sans AndroidX) qui simule une connexion locale et le stockage d'une note privée. Elle contient volontairement six défauts. L'objectif est de les reproduire, de les prouver avec adb, de les corriger, puis de refaire exactement les mêmes tests.

Environnement : Android Studio, émulateur Pixel 6a API 37.2, build debug, adb sous Windows. Avant chaque série de tests, les données de l'application sont effacées, ce qui rend les résultats « avant » et « après » comparables.

## Synthèse

| # | Faille | Gravité estimée | Constat avant correction | Après correction |
|---|--------|-----------------|--------------------------|------------------|
| V1 | Mot de passe codé en dur | Élevée | Lisible dans `classes3.dex` | Absent du dex (empreinte PBKDF2) |
| V2 | Token et note en clair | Moyenne | Lisibles dans `vault_lab.xml` | Token non stocké, note chiffrée |
| V3 | Session par simple booléen | Élevée | Accès à la note sans mot de passe | Accès refusé |
| V4 | Base64 présenté comme protection | Moyenne | Note décodée sans clé | AES-GCM, décodage impossible |
| V5 | Token dans logcat | Moyenne | Token visible dans les logs | Aucune trace |
| V6 | Sauvegarde permissive | Moyenne | `vault_lab.xml` en clair dans la sauvegarde | Réduit : extrait, mais chiffré |

## V1 : mot de passe codé en dur

- **Cause** : `LAB_PASSWORD = "vault-demo-2026"` est une constante de `MainActivity.kt` ; le compilateur la recopie telle quelle dans `classes.dex`.
- **Gravité** : élevée. L'APK est public et il suffit de l'avoir pour lire le secret, sans accès à l'appareil.
- **Attaque** : extraction de l'APK (`adb pull`), puis recherche de chaînes dans les fichiers `classes*.dex`.
- **Preuve** (avant) :

```
classes3.dex contient : vault-demo-2026
classes3.dex contient : DEMO_SESSION_TOKEN_2026
```

- **Correction** : l'application ne garde plus que l'empreinte du mot de passe (PBKDF2-HMAC-SHA256, sel, 120 000 itérations) et compare en temps constant.

```kotlin
// avant
private const val LAB_PASSWORD = "vault-demo-2026"
if (password.text.toString() == LAB_PASSWORD) { ... }

// après
val spec = PBEKeySpec(input.toCharArray(), salt, ITERATIONS, 256)
val derived = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
return MessageDigest.isEqual(hex(derived).toByteArray(), HASH_HEX.toByteArray())
```

- **Pourquoi ça fonctionne** : le mot de passe n'apparaît plus dans l'APK. Les itérations ralentissent chaque tentative de force brute, et `MessageDigest.isEqual` évite de révéler la position de la première différence par le temps de calcul.
- **Vérification** : la même recherche dans le dex ne trouve plus aucune des deux chaînes.

## V2 : token et note en clair dans les SharedPreferences

- **Cause** : `session_token` et `private_note` sont écrits tels quels dans `shared_prefs/vault_lab.xml`. `MODE_PRIVATE` limite l'accès aux autres applications, mais ne chiffre rien.
- **Gravité** : moyenne. Il faut accéder aux données de l'application (build debuggable avec `run-as`, appareil rooté, ou sauvegarde, voir V6).
- **Attaque** : `adb shell run-as edu.lab.mobilevault cat shared_prefs/vault_lab.xml`.
- **Preuve** (avant) :

```xml
<<V2_AVANT>>
```

- **Correction** : le token n'est plus écrit sur le disque (voir V3) et la note est chiffrée avant d'être enregistrée (voir V4).
- **Vérification** (après) :

```xml
<<V2_APRES>>
```

## V3 : session basée sur un booléen modifiable

- **Cause** : `isLoggedIn()` lit simplement `logged_in` dans les préférences. Rien ne lie ce booléen à une authentification réelle.
- **Gravité** : élevée en impact (contournement complet de l'authentification), mais elle suppose de pouvoir écrire dans les données de l'application (build debug ou appareil rooté).
- **Attaque** : écriture d'un `vault_lab.xml` contenant `logged_in=true`, relance de l'application, clic sur « Lire note » sans saisir de mot de passe.
- **Preuve** :

```
avant : Note : NOTE_FORGEE_SANS_MOT_DE_PASSE
après : Accès refusé : session locale absente
```

- **Correction** : l'état de session devient un jeton aléatoire gardé en mémoire uniquement ; le flag `logged_in` n'est plus lu nulle part.

```kotlin
// avant
prefs.edit().putBoolean("logged_in", true).putString("session_token", token).apply()
private fun isLoggedIn() = prefs.getBoolean("logged_in", false)

// après
Session.token = hex(ByteArray(32).also { SecureRandom().nextBytes(it) })
private fun isLoggedIn() = Session.token != null
```

- **Pourquoi ça fonctionne** : l'état d'authentification n'existe plus sur le disque, donc modifier les préférences ne change rien. Contrepartie : la session est perdue quand le processus est tué, ce qui est acceptable pour ce laboratoire.

## V4 : Base64 présenté comme protection

- **Cause** : `VaultCrypto.protect()` n'utilise ni clé ni algorithme de chiffrement, seulement `Base64.encodeToString`. Base64 est un codage, pas un chiffrement.
- **Gravité** : moyenne. La donnée n'est lisible que si l'attaquant atteint le fichier (V2, V6), mais l'utilisateur croit à tort qu'elle est protégée.
- **Attaque** : lecture de `protected_note`, puis `[Convert]::FromBase64String(...)` en PowerShell.
- **Preuve** (avant) : `decode Base64 sans clé = NoteSecreteLab42`.

- **Correction** : chiffrement AES-256-GCM, avec une clé générée dans l'Android Keystore (aucune dépendance AndroidX).

```kotlin
// avant
fun protect(plain: String) = Base64.encodeToString(plain.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)

// après
val c = Cipher.getInstance("AES/GCM/NoPadding")
c.init(Cipher.ENCRYPT_MODE, key())              // clé non exportable (Keystore)
val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
return Base64.encodeToString(c.iv + ct, Base64.NO_WRAP)   // IV aléatoire de 12 octets
```

- **Pourquoi ça fonctionne** : sans la clé, qui ne quitte pas le Keystore, le contenu est illisible, et GCM détecte aussi toute modification. Dans la sauvegarde de la V6, `private_note` et `protected_note` ont des valeurs différentes alors qu'elles chiffrent la même note : c'est l'effet de l'IV aléatoire.

## V5 : token écrit dans logcat

- **Cause** : `Log.d(LOG_TAG, "Debug token=$token")` est exécuté à chaque connexion.
- **Gravité** : moyenne. Sur un Android récent, une application ne peut pas lire les logs des autres, mais le journal reste lisible par adb et se retrouve dans les rapports de bug.
- **Attaque** : `adb logcat -d -s MobileVaultLab` après une connexion.
- **Preuve** (avant) :

```
11-07 14:32:56.203 24742 24742 D MobileVaultLab: Debug token=DEMO_SESSION_TOKEN_2026
```

- **Correction** : suppression de l'appel `Log.d`. Après correction, le même filtre logcat ne renvoie aucune ligne.

## V6 : sauvegarde permissive

- **Cause** : `allowBackup="true"` dans le manifest, et `data_extraction_rules.xml` inclut tout le domaine `sharedpref` pour `cloud-backup` et `device-transfer`.
- **Gravité** : moyenne. L'extraction demande adb (ou le compte de sauvegarde) et une confirmation à l'écran, mais elle contourne totalement le contrôle d'accès de l'application.
- **Attaque** : `adb backup -f backup.ab -noapk edu.lab.mobilevault`, retrait de l'en-tête, décompression, extraction de l'archive tar.
- **Résultat avant** : `apps/edu.lab.mobilevault/sp/vault_lab.xml` est présent dans la sauvegarde, avec le token et la note en clair.

- **Correction** :

```xml
<!-- avant -->
<application android:allowBackup="true" ...>
<cloud-backup><include domain="sharedpref" path="."/></cloud-backup>

<!-- après -->
<application android:allowBackup="false" ...>
<cloud-backup><exclude domain="sharedpref" path="."/></cloud-backup>
```

- **Résultat après** : le flag `ALLOW_BACKUP` a disparu de `dumpsys package`, mais `adb backup` extrait encore `vault_lab.xml` sur ce build debuggable. Il ne contient plus que des valeurs chiffrées :

```xml
<map>
    <string name="private_note">+jOH9VpDKzfi18Qm+ZaLX69Ujhr0haBa5CsuJwApgJl5BcyKUG19x3+fGUs=</string>
    <string name="protected_note">C2GdAS/KJw2Z2ZqAHurh77Y80VdbUMpVns0hCcktrlRKFR1qdn0wsQqORpU=</string>
</map>
```

La clé AES reste dans le Keystore et n'est pas sauvegardée : ces valeurs sont inexploitables hors de l'appareil. Le défaut est donc réduit, pas supprimé. La cause du contournement de `allowBackup="false"` n'a pas été vérifiée ; l'hypothèse la plus probable est le caractère `debuggable` du build, à confirmer avec un build release.

## Limites et points ouverts

- **V6** : à confirmer avec un build non débogable, où la sauvegarde devrait être refusée.
- **Mot de passe** : l'empreinte est dans l'application, donc un mot de passe faible reste attaquable par force brute hors ligne. Aucune vérification purement locale n'est parfaite ; une vraie application s'appuierait sur un serveur.
- **Session** : rien n'est validé côté serveur, et la session disparaît quand le processus est tué.
- **Build debug** : l'application reste débogable, donc `run-as` fonctionne encore. Il ne donne plus que du contenu chiffré.

## Difficultés rencontrées

- **V6 inattendue** : après `allowBackup="false"`, la sauvegarde contenait encore le fichier. Il a fallu lire son contenu pour constater qu'il était désormais chiffré, et en déduire que le défaut était réduit plutôt que supprimé.
- **Coordonnées des boutons** : celles relevées sur une capture ne correspondaient pas aux pixels réels de l'écran (1080×2400). Elles ont été relevées avec un dump de l'interface (`uiautomator dump`).
- **Confirmation de la sauvegarde** : `adb backup` attend une validation sur l'écran de l'émulateur, ce qui bloque la commande tant qu'elle n'est pas faite.
- **Build à jour** : pour être sûr que le retest portait sur le nouveau code, la date `lastUpdateTime` du paquet et ses flags (`ALLOW_BACKUP`) ont été contrôlés avant chaque série.

## Conclusion

Les six défauts ont été reproduits et prouvés avant correction. Cinq sont corrigés et vérifiés par le même test ; le sixième est réduit à une sauvegarde chiffrée. L'enseignement principal est que stocker un secret demande de le chiffrer avec une clé hors d'atteinte du fichier (Keystore), et que l'état d'authentification ne doit jamais être une valeur modifiable depuis le disque.