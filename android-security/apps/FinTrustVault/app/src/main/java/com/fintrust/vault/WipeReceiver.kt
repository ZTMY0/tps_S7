package com.fintrust.vault

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

class WipeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Vulnérable : aucune permission n'est exigée pour déclencher l'effacement
        val dbHelper = NotesDbHelper(context)
        val db = dbHelper.writableDatabase
        db.delete("notes", null, null)
        Toast.makeText(context, "Toutes les notes ont été effacées", Toast.LENGTH_LONG).show()
    }
}