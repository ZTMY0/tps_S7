package com.lab.securenotes

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<Button>(R.id.buttonProfil).setOnClickListener {
            Session.estConnecte = true
            SessionUtilisateur.idActuel = "alice"
            // VULNERABLE (attaque 3) : jeton ecrit dans les logs
            Log.d("SecureNotesLab", "Authentification terminee, token = ${Session.token}")
            // VULNERABLE (attaque 5) : jeton stocke en clair
            Session.enregistrerToken(this)
            startActivity(Intent(this, AdminActivity::class.java))
        }

        findViewById<Button>(R.id.buttonNote).setOnClickListener {
            val intent = Intent(this, NoteDetailActivity::class.java)
            intent.putExtra("noteId", "note_alice_01")
            startActivity(intent)
        }

        findViewById<Button>(R.id.buttonDossier).setOnClickListener {
            val intent = Intent(this, DossierActivity::class.java)
            intent.putExtra("employeId", "alice")
            startActivity(intent)
        }
    }
}
