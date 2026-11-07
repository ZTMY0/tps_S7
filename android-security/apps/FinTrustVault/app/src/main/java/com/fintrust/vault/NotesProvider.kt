package com.fintrust.vault

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri

class NotesDbHelper(context: Context) :
    SQLiteOpenHelper(context, "notes.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE notes (id INTEGER PRIMARY KEY, contenu TEXT)")
        db.execSQL("INSERT INTO notes (contenu) VALUES ('Réunion budget vendredi')")
        db.execSQL("INSERT INTO notes (contenu) VALUES ('Code d accès local : 4821')")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldV: Int, newV: Int) {}
}

class NotesProvider : ContentProvider() {
    private lateinit var dbHelper: NotesDbHelper

    override fun onCreate(): Boolean {
        dbHelper = NotesDbHelper(context!!)
        return true
    }

    override fun query(
        uri: Uri, projection: Array<String>?, selection: String?,
        selectionArgs: Array<String>?, sortOrder: String?
    ): Cursor {
        val db = dbHelper.readableDatabase
        // Vulnérable : la clause "selection" fournie par l'appelant
        // est concaténée telle quelle dans la requête.
        return db.query("notes", projection, selection, selectionArgs, null, null, sortOrder)
    }

    override fun getType(uri: Uri) = "vnd.android.cursor.dir/notes"

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        val db = dbHelper.writableDatabase
        val id = db.insert("notes", null, values)
        return Uri.parse("content://com.fintrust.vault.provider/notes/$id")
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?) = 0
}
