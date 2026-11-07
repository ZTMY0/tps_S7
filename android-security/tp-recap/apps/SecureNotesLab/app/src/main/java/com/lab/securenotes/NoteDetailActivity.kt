package com.lab.securenotes

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class NoteDetailActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val noteId = intent.getStringExtra("noteId") ?: "inconnue"

        // VULNERABLE : noteId n'est jamais valide et est repris tel quel
        val contenu = when (noteId) {
            "note_alice_01" -> "Code projet interne : DEMO-2026"
            "../admin_config" -> "CONFIG ADMIN (fictif) : mode=debug ; cle=DEMO-ADMIN"
            else -> "Aucune note associee a cet identifiant"
        }

        val vue = TextView(this)
        vue.setPadding(40, 300, 40, 40)
        vue.textSize = 16f
        vue.text = "Note (id=$noteId)\n\n$contenu"
        setContentView(vue)
    }
}
