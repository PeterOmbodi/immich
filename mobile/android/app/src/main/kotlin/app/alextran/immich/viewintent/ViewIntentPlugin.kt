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
private const val COPY_BUFFER_SIZE = 64 * 1024

private data class ResolvedViewIntent(
  val localAssetId: String?,
  val displayName: String? = null,
  val sourceModifiedAt: Long? = null,
)

private data class UriMetadata(
  val displayName: String?,
  val size: Long?,
  val sourceModifiedAt: Long?,
)

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

        val resolved = resolveViewIntent(context, uri, mimeType)
        val materialized = if (resolved.localAssetId == null) {
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
          localAssetId = resolved.localAssetId,
          checksum = materialized?.checksum,
          displayName = if (materialized == null) null else resolved.displayName,
          sourceModifiedAt = if (materialized == null) null else resolved.sourceModifiedAt,
        )
        consumeViewIntent(intent)
        callback(Result.success(payload))
      } catch (e: Exception) {
        Log.e(TAG, "Failed to consume view intent URI: $uri", e)
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

  private fun resolveViewIntent(context: Context, uri: Uri, mimeType: String): ResolvedViewIntent {
    val isDocumentUri = tryIsDocumentUri(context, uri)
    tryExtractDocumentLocalAssetId(uri, isDocumentUri)?.let { return ResolvedViewIntent(localAssetId = it) }
    tryParseContentUriId(uri)?.let { return ResolvedViewIntent(localAssetId = it) }

    val metadata = queryUriMetadata(context, uri, isDocumentUri)
    val localAssetId = resolveLocalIdByNameAndSize(
      context,
      uri = uri,
      displayName = metadata?.displayName,
      size = metadata?.size,
      mimeType = mimeType,
    )
    return ResolvedViewIntent(
      localAssetId = localAssetId,
      displayName = metadata?.displayName,
      sourceModifiedAt = metadata?.sourceModifiedAt,
    )
  }

  private fun tryIsDocumentUri(context: Context, uri: Uri): Boolean {
    return try {
      DocumentsContract.isDocumentUri(context, uri)
    } catch (error: Exception) {
      Log.w(TAG, "Failed to identify document URI: $uri", error)
      false
    }
  }

  private fun tryExtractDocumentLocalAssetId(uri: Uri, isDocumentUri: Boolean): String? {
    return try {
      if (!isDocumentUri) return null
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
    val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)?.let { ".$it" }
    val tempFile = try {
      File.createTempFile("view_intent_", extension, context.cacheDir)
    } catch (error: Exception) {
      Log.w(TAG, "Failed to create a temporary file for view intent URI: $uri", error)
      return null
    }

    var completed = false
    return try {
      val digest = MessageDigest.getInstance("SHA-1")
      val inputStream = context.contentResolver.openInputStream(uri) ?: run {
        Log.w(TAG, "Failed to open view intent URI: $uri")
        return null
      }
      inputStream.use { input ->
        FileOutputStream(tempFile).use { output ->
          val buffer = ByteArray(COPY_BUFFER_SIZE)
          while (true) {
            val bytesRead = input.read(buffer)
            if (bytesRead < 0) break
            output.write(buffer, 0, bytesRead)
            digest.update(buffer, 0, bytesRead)
          }
        }
      }

      val checksum = Base64.encodeToString(digest.digest(), Base64.NO_WRAP)
      completed = true
      MaterializedViewIntent(tempFile, checksum)
    } catch (error: Exception) {
      Log.w(TAG, "Failed to materialize view intent URI: $uri", error)
      null
    } finally {
      if (!completed && tempFile.exists() && !tempFile.delete()) {
        Log.w(TAG, "Failed to delete incomplete view intent file: ${tempFile.absolutePath}")
      }
    }
  }

  private fun queryUriMetadata(context: Context, uri: Uri, isDocumentUri: Boolean): UriMetadata? {
    val projection =
      mutableListOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        .apply {
          if (isDocumentUri) add(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        }.toTypedArray()
    return try {
      context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
        if (!cursor.moveToFirst()) return null

        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
        val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        UriMetadata(
          displayName =
            if (nameIndex >= 0 && !cursor.isNull(nameIndex)) cursor.getString(nameIndex).takeUnless { it.isBlank() }
            else null,
          size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else null,
          sourceModifiedAt =
            if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) cursor.getLong(modifiedIndex) else null,
        )
      }
    } catch (error: Exception) {
      Log.w(TAG, "Failed to read metadata for view intent URI: $uri", error)
      null
    }
  }

  private fun resolveLocalIdByNameAndSize(
    context: Context,
    uri: Uri,
    displayName: String?,
    size: Long?,
    mimeType: String,
  ): String? {
    if (displayName.isNullOrBlank() || size == null || size < 0) return null

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
    } catch (error: Exception) {
      Log.w(TAG, "Failed to resolve local asset by view intent metadata: $uri", error)
      null
    }
  }
}
