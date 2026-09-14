package app.alextran.immich.viewintent

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

private const val TAG = "ViewIntentPlugin"
private const val HASH_BUFFER_SIZE = 64 * 1024

private data class MaterializedViewIntent(val file: File, val checksum: String)

class ViewIntentPlugin : FlutterPlugin, ActivityAware, PluginRegistry.NewIntentListener, ViewIntentHostApi {
  private var context: Context? = null
  private var activity: Activity? = null
  private var unconsumedIntent: Intent? = null
  private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    ViewIntentHostApi.setUp(binding.binaryMessenger, this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    ViewIntentHostApi.setUp(binding.binaryMessenger, null)
    ioScope.cancel()
    context = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    unconsumedIntent = binding.activity.intent
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onNewIntent(intent: Intent): Boolean {
    unconsumedIntent = intent
    return false
  }

  override fun consumeViewIntent(callback: (Result<ViewIntentPayload?>) -> Unit) {
    val context = context ?: run {
      callback(Result.success(null))
      return
    }
    val intent = unconsumedIntent ?: activity?.intent

    if (intent?.action != Intent.ACTION_VIEW) {
      callback(Result.success(null))
      return
    }

    val uri = intent.data
    if (uri == null) {
      callback(Result.success(null))
      return
    }

    ioScope.launch {
      try {
        val mimeType = context.contentResolver.getType(uri) ?: intent.type
        if (mimeType == null || (!mimeType.startsWith("image/") && !mimeType.startsWith("video/"))) {
          callback(Result.success(null))
          return@launch
        }

        val localAssetId = extractLocalAssetId(context, uri, mimeType)
        val materialized = if (localAssetId == null) {
          materializeUri(context, uri, mimeType) ?: run {
            callback(Result.success(null))
            return@launch
          }
        } else {
          null
        }
        val payload = ViewIntentPayload(
          path = materialized?.file?.absolutePath,
          mimeType = mimeType,
          localAssetId = localAssetId,
          checksum = materialized?.checksum,
        )
        consumeViewIntent(intent)
        callback(Result.success(payload))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  private fun consumeViewIntent(currentIntent: Intent) {
    unconsumedIntent = Intent(currentIntent).apply {
      action = null
      data = null
      type = null
    }
    activity?.intent = unconsumedIntent
  }

  private fun extractLocalAssetId(context: Context, uri: Uri, mimeType: String): String? {
    return tryExtractDocumentLocalAssetId(context, uri)
      ?: tryParseContentUriId(uri)
      ?: resolveLocalIdByNameAndSize(context, uri, mimeType)
  }

  private fun tryExtractDocumentLocalAssetId(context: Context, uri: Uri): String? {
    return try {
      if (!DocumentsContract.isDocumentUri(context, uri)) return null
      val docId = DocumentsContract.getDocumentId(uri)
      if (docId.isBlank() || docId.startsWith("raw:")) return null
      docId.substringAfter(':', docId).toLongOrNull()?.toString()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to resolve local asset id from document URI: $uri", e)
      null
    }
  }

  private fun tryParseContentUriId(uri: Uri): String? {
    val id = uri.lastPathSegment?.toLongOrNull() ?: return null
    return if (id >= 0) id.toString() else null
  }

  private fun materializeUri(context: Context, uri: Uri, mimeType: String): MaterializedViewIntent? {
    var tempFile: File? = null
    var completed = false
    return try {
      val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)?.let { ".$it" }
      tempFile = File.createTempFile("view_intent_", extension, context.cacheDir)
      val digest = MessageDigest.getInstance("SHA-1")
      context.contentResolver.openInputStream(uri)?.use { inputStream ->
        FileOutputStream(tempFile).use { outputStream ->
          val buffer = ByteArray(HASH_BUFFER_SIZE)
          while (true) {
            val bytesRead = inputStream.read(buffer)
            if (bytesRead == -1) break
            outputStream.write(buffer, 0, bytesRead)
            digest.update(buffer, 0, bytesRead)
          }
        }
      } ?: return null
      completed = true
      MaterializedViewIntent(tempFile, Base64.encodeToString(digest.digest(), Base64.NO_WRAP))
    } catch (_: Exception) {
      null
    } finally {
      if (!completed) {
        tempFile?.delete()
      }
    }
  }

  private fun resolveLocalIdByNameAndSize(context: Context, uri: Uri, mimeType: String): String? {
    val metaProjection = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
    val (displayName, size) =
      try {
        context.contentResolver.query(uri, metaProjection, null, null, null)?.use { cursor ->
          if (!cursor.moveToFirst()) return null
          val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
          val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
          val name = if (nameIdx >= 0) cursor.getString(nameIdx) else null
          val bytes = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else -1L
          if (name.isNullOrBlank() || bytes < 0) return null
          name to bytes
        } ?: return null
      } catch (_: Exception) {
        return null
      }

    val tableUri = when {
      mimeType.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
      mimeType.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
      else -> return null
    }
    return try {
      context.contentResolver
        .query(
          tableUri,
          arrayOf(MediaStore.MediaColumns._ID),
          "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.SIZE}=?",
          arrayOf(displayName, size.toString()),
          "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
        )?.use { cursor ->
          if (!cursor.moveToFirst()) return null
          val idIndex = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
          if (idIndex < 0) return null
          cursor.getLong(idIndex).toString()
        }
    } catch (_: Exception) {
      null
    }
  }
}
