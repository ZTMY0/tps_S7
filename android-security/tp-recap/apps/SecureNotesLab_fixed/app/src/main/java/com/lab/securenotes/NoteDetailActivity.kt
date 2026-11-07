package com.lab.securenotes

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class NoteDetailActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // FIXED : liste blanche explicite
        val notesAutorisees = setOf("note_alice_01")
        val noteId = intent.getStringExtra("noteId") ?: ""

        val contenu = if (noteId in notesAutorisees) {
            "Code projet interne : DEMO-2026"
        } else {
            "Entree refusee : valeur non autorisee"
        }

        val vue = TextView(this)
        vue.setPadding(40, 300, 40, 40)
        vue.textSize = 16f
        vue.text = "Note\n\n$contenu"
        setContentView(vue)
    }
}
