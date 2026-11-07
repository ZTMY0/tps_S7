package com.lab.securenotes

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity
import java.io.File

class NotesListActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_notes_list)
        val dossierNotes = File(filesDir, "notes")
        if (!dossierNotes.exists()) {
            dossierNotes.mkdirs()
            File(dossierNotes, "note_alice.txt").writeText("Rendez vous client reporté a vendredi.")
        }
        Session.estConnecte = true
        SyncManager.lancerSynchronisation()
        findViewById<Button>(R.id.btnOuvrirNote).setOnClickListener {
            val intent = Intent(this, NoteDetailActivity::class.java)
            intent.putExtra("cheminFichier", "note_alice.txt")
            startActivity(intent)
        }
        findViewById<Button>(R.id.btnProfil).setOnClickListener {
            startActivity(Intent(this, ProfilActivity::class.java))
        }
    }
}

