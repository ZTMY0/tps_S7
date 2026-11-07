package edu.lab.mobilevault

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.EditText
import android.widget.TextView

/** Deliberately vulnerable, fully offline teaching application. */
class MainActivity : Activity() {
    companion object {
        private const val LAB_PASSWORD = "vault-demo-2026" // intentional audit finding
        private const val LOG_TAG = "MobileVaultLab"
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
        show("Application démarrée. Session locale : ${isLoggedIn()}")
    }
    private fun isLoggedIn(): Boolean = prefs.getBoolean("logged_in", false)
    private fun login() {
        if (password.text.toString() == LAB_PASSWORD) {
            val token = "DEMO_SESSION_TOKEN_2026"
            prefs.edit().putBoolean("logged_in", true).putString("session_token", token).apply()
            Log.d(LOG_TAG, "Debug token=$token") // intentional log leak
            show("Connexion de démonstration acceptée")
        } else show("Connexion refusée")
    }
    private fun logout() {
        prefs.edit().remove("logged_in").remove("session_token").apply()
        show("Déconnexion locale")
    }
    private fun saveNote() {
        if (!isLoggedIn()) { show("Connectez-vous pour enregistrer"); return }
        prefs.edit().putString("private_note", note.text.toString()).apply()
        show("Note fictive enregistrée")
    }
    private fun readNote() {
        if (!isLoggedIn()) { show("Accès refusé : session locale absente"); return }
        show("Note : ${prefs.getString("private_note", "(vide)")}")
    }
    private fun encodeNote() {
        if (!isLoggedIn()) { show("Connectez-vous d'abord"); return }
        val plain = prefs.getString("private_note", "") ?: ""
        val encoded = VaultCrypto.protect(plain)
        prefs.edit().putString("protected_note", encoded).apply()
        show("Note prétendument protégée et stockée")
    }
    private fun show(message: String) { status.text = message }
}
