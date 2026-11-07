package edu.lab.mobilevault

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** Session en memoire uniquement : rien n'est ecrit sur le disque. */
private object Session {
    @Volatile var token: String? = null
}

class MainActivity : Activity() {
    companion object {
        // Verification par empreinte PBKDF2 : le mot de passe n'est plus present dans l'APK.
        private const val SALT_HEX = "08fe2d60b8459279fea6dddb2ef58595"
        private const val HASH_HEX = "65308c7245907cf115e49cadb9702366aa282d2d4d161913d6e370d98ad0e083"
        private const val ITERATIONS = 120000
    }

    private val prefs by lazy { getSharedPreferences("vault_lab", MODE_PRIVATE) }
    private lateinit var password: EditText
    private lateinit var note: EditText
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        password = findViewById(R.id.passwordInput)
        note = findViewById(R.id.noteInput)
        status = findViewById(R.id.statusText)
        findViewById<Button>(R.id.loginButton).setOnClickListener { login() }
        findViewById<Button>(R.id.logoutButton).setOnClickListener { logout() }
        findViewById<Button>(R.id.saveButton).setOnClickListener { saveNote() }
        findViewById<Button>(R.id.readButton).setOnClickListener { readNote() }
        findViewById<Button>(R.id.encodeButton).setOnClickListener { encodeNote() }
        show("Application d\u00e9marr\u00e9e. Session locale : ${isLoggedIn()}")
    }

    private fun isLoggedIn(): Boolean = Session.token != null

    private fun hex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }

    private fun passwordMatches(input: String): Boolean {
        val salt = SALT_HEX.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val spec = PBEKeySpec(input.toCharArray(), salt, ITERATIONS, 256)
        val derived = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        return MessageDigest.isEqual(hex(derived).toByteArray(), HASH_HEX.toByteArray())
    }

    private fun login() {
        if (passwordMatches(password.text.toString())) {
            val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
            Session.token = hex(raw)
            show("Connexion de d\u00e9monstration accept\u00e9e")
        } else show("Connexion refus\u00e9e")
    }

    private fun logout() {
        Session.token = null
        show("D\u00e9connexion locale")
    }

    private fun storedNote(): String {
        val enc = prefs.getString("private_note", null) ?: return ""
        return VaultCrypto.unprotect(enc)
    }

    private fun saveNote() {
        if (!isLoggedIn()) { show("Connectez-vous pour enregistrer"); return }
        prefs.edit().putString("private_note", VaultCrypto.protect(note.text.toString())).apply()
        show("Note fictive enregistr\u00e9e (chiffr\u00e9e)")
    }

    private fun readNote() {
        if (!isLoggedIn()) { show("Acc\u00e8s refus\u00e9 : session locale absente"); return }
        try {
            val plain = storedNote()
            show("Note : ${if (plain.isEmpty()) "(vide)" else plain}")
        } catch (e: Exception) {
            show("Note illisible")
        }
    }

    private fun encodeNote() {
        if (!isLoggedIn()) { show("Connectez-vous d'abord"); return }
        try {
            prefs.edit().putString("protected_note", VaultCrypto.protect(storedNote())).apply()
            show("Note chiffr\u00e9e (AES-GCM) et stock\u00e9e")
        } catch (e: Exception) {
            show("Chiffrement impossible")
        }
    }

    private fun show(message: String) { status.text = message }
}