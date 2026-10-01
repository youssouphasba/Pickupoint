package com.denkma.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.ContactsContract
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class PhoneContactPicker(private val activity: FlutterFragmentActivity) {
    private var pending: MethodChannel.Result? = null
    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { response ->
        val result = pending ?: return@registerForActivityResult
        pending = null
        if (response.resultCode != Activity.RESULT_OK) {
            result.success(null)
            return@registerForActivityResult
        }
        val uri = response.data?.data
        if (uri == null || uri.scheme != "content") {
            result.error("invalid_contact", "Le contact sélectionné n'est pas disponible.", null)
            return@registerForActivityResult
        }
        try {
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            )
            activity.contentResolver.query(uri, projection, null, null, null).use { cursor ->
                if (cursor == null || !cursor.moveToFirst()) {
                    result.error("contact_without_phone", "Aucun numéro sélectionné.", null)
                } else {
                    val name = cursor.getString(cursor.getColumnIndexOrThrow(projection[0])) ?: ""
                    val phone = cursor.getString(cursor.getColumnIndexOrThrow(projection[1])) ?: ""
                    if (phone.isBlank()) {
                        result.error("contact_without_phone", "Aucun numéro sélectionné.", null)
                    } else {
                        result.success(mapOf("name" to name, "phone" to phone))
                    }
                }
            }
        } catch (_: Exception) {
            result.error("contact_read_failed", "Impossible de lire le numéro sélectionné.", null)
        }
    }

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("picker_busy", "Le sélecteur de contacts est déjà ouvert.", null)
            return
        }
        pending = result
        try {
            launcher.launch(Intent(Intent.ACTION_PICK).apply {
                type = ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE
            })
        } catch (_: ActivityNotFoundException) {
            pending = null
            result.error("picker_unavailable", "Aucun sélecteur de contacts disponible.", null)
        } catch (_: Exception) {
            pending = null
            result.error("picker_failed", "Impossible d'ouvrir le sélecteur de contacts.", null)
        }
    }

    fun dispose() {
        pending?.success(null)
        pending = null
    }
}
