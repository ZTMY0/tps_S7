package com.fintrust.vault

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class NotesListActivity : AppCompatActivity() {

    private lateinit var conteneurNotes: LinearLayout
    private val uriNotes: Uri = Uri.parse("content://com.fintrust.vault.provider/notes")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val racine = LinearLayout(this)
        racine.orientation = LinearLayout.VERTICAL
        racine.setPadding(50, 120, 50, 40)

        val titre = TextView(this)
        titre.text = "Mes notes"
        titre.textSize = 22f
        racine.addView(titre)

        val champNouvelleNote = EditText(this)
        champNouvelleNote.hint = "Nouvelle note"
        racine.addView(champNouvelleNote)

        val boutonAjouter = Button(this)
        boutonAjouter.text = "Ajouter"
        racine.addView(boutonAjouter)

        val boutonParametres = Button(this)
        boutonParametres.text = "Paramètres"
        racine.addView(boutonParametres)

        conteneurNotes = LinearLayout(this)
        conteneurNotes.orientation = LinearLayout.VERTICAL
        racine.addView(conteneurNotes)

        boutonAjouter.setOnClickListener {
            val texte = champNouvelleNote.text.toString()
            if (texte.isNotBlank()) {
                val valeurs = ContentValues()
                valeurs.put("contenu", texte)
                contentResolver.insert(uriNotes, valeurs)
                champNouvelleNote.setText("")
                chargerNotes()
            }
        }

        boutonParametres.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }

        setContentView(racine)
    }

    override fun onResume() {
        super.onResume()
        chargerNotes()
    }

    private fun chargerNotes() {
        conteneurNotes.removeAllViews()
        val cursor = contentResolver.query(uriNotes, null, null, null, null)
        cursor?.use {
            val indexContenu = it.getColumnIndex("contenu")
            while (it.moveToNext()) {
                val contenu = it.getString(indexContenu)
                ajouterLigneNote(contenu)
            }
        }
    }

    private fun ajouterLigneNote(contenuNote: String) {
        val ligne = LinearLayout(this)
        ligne.orientation = LinearLayout.HORIZONTAL
        ligne.setPadding(0, 16, 0, 16)

        val texteNote = TextView(this)
        texteNote.text = contenuNote
        texteNote.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        ligne.addView(texteNote)

        val boutonPartager = Button(this)
        boutonPartager.text = "Partager"
        boutonPartager.setOnClickListener { partagerNote(this, contenuNote) }
        ligne.addView(boutonPartager)

        conteneurNotes.addView(ligne)
    }
}

fun partagerNote(activity: android.app.Activity, contenuNote: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        // Vulnérable : le jeton de session ne devrait jamais figurer ici
        putExtra(Intent.EXTRA_TEXT, "$contenuNote\n\n(session: ${Session.token})")
    }
    activity.startActivity(Intent.createChooser(intent, "Partager la note"))
}
