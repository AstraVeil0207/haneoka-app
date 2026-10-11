package org.haneoka.haneoka

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.Executors

/**
 * Reads the game's save files on the phone itself. Since Android 11 the
 * game's `Android/data` folder is readable only by the shell user, which
 * Shizuku lends to apps; on Android 8–12 the system folder picker can also
 * grant that one folder. Only listing and reading run, under the game's own
 * `files/<account>` folders.
 */
class SaveChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "org.haneoka/saves")
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingGrant: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, result ->
        if (code == SHIZUKU_REQUEST) {
            pendingPermission?.success(result == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    init {
        channel.setMethodCallHandler(this)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    fun dispose() {
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shizukuStatus" -> result.success(shizukuStatus())
            "shizukuRequest" -> {
                if (shizukuStatus() != "needsPermission") result.success(shizukuStatus() == "ready")
                else {
                    pendingPermission = result
                    Shizuku.requestPermission(SHIZUKU_REQUEST)
                }
            }
            "openShizuku" -> {
                val intent = activity.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
                if (intent != null) activity.startActivity(intent)
                result.success(intent != null)
            }
            "shizukuRead" -> background(result) { shizukuRead(call.argument<String>("package")!!) }
            "canGrantGameFolder" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU)
            "grantGameFolder" -> grantGameFolder(call.argument<String>("package")!!, result)
            "grantedFolders" -> result.success(
                activity.contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri.toString() },
            )
            "readFolder" -> background(result) { readTree(Uri.parse(call.argument<String>("uri")!!)) }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            val outcome = runCatching(work)
            activity.runOnUiThread {
                outcome.fold({ result.success(it) }, { result.error("read_failed", it.message, null) })
            }
        }
    }

    private fun shizukuStatus(): String = try {
        when {
            !Shizuku.pingBinder() -> "notRunning"
            Shizuku.isPreV11() -> "unsupported"
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> "ready"
            else -> "needsPermission"
        }
    } catch (_: Throwable) {
        "notRunning"
    }

    /** Every small file in the package's account folders, with its size and time. */
    private fun shizukuRead(packageId: String): List<Map<String, Any?>> {
        require(packageId in PACKAGES) { "unknown package" }
        val root = "/sdcard/Android/data/$packageId/files"
        val top = run("ls", "-1p", root) ?: return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        for (dir in top.lines().filter { it.endsWith("/") }.map { it.dropLast(1) }.filter { ACCOUNT_DIR.matches(it) }) {
            val path = "$root/$dir"
            val listing = run("ls", "-1p", path) ?: continue
            for (name in listing.lines().filter { it.isNotEmpty() && !it.endsWith("/") }) {
                val file = "$path/$name"
                val stat = run("stat", "-c", "%s %Y", file)?.trim()?.split(" ") ?: continue
                val size = stat.firstOrNull()?.toLongOrNull() ?: continue
                if (size <= 0 || size > MAX_FILE) continue
                val bytes = runBytes("cat", file) ?: continue
                out += mapOf(
                    "source" to "$packageId/$dir/$name",
                    "group" to "$packageId/$dir",
                    "modified" to (stat.getOrNull(1)?.toLongOrNull()?.times(1000)),
                    "package" to packageId,
                    "bytes" to bytes,
                )
            }
        }
        return out
    }

    private fun run(vararg argv: String): String? = runBytes(*argv)?.toString(Charsets.UTF_8)

    /** Runs argv as the shell user, without a shell, so paths need no quoting. */
    private fun runBytes(vararg argv: String): ByteArray? {
        val service = IShizukuService.Stub.asInterface(Shizuku.getBinder()) ?: return null
        val process = service.newProcess(arrayOf(*argv), null, null)
        try {
            val out = ByteArrayOutputStream()
            val complete = ParcelFileDescriptor.AutoCloseInputStream(process.inputStream).use { copy(it, out) }
            ParcelFileDescriptor.AutoCloseInputStream(process.errorStream).use { it.readBytes() }
            if (!complete) return null
            return if (process.waitFor() == 0) out.toByteArray() else null
        } finally {
            runCatching { process.destroy() }
        }
    }

    private fun copy(input: InputStream, output: ByteArrayOutputStream): Boolean {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) return true
            total += n
            if (total > MAX_FILE) return false
            output.write(buffer, 0, n)
        }
    }

    /** Opens the system folder picker on the game's folder; one tap grants it for good. */
    private fun grantGameFolder(packageId: String, result: MethodChannel.Result) {
        require(packageId in PACKAGES) { "unknown package" }
        pendingGrant?.success(null)
        pendingGrant = result
        val initial = DocumentsContract.buildDocumentUri(STORAGE, "primary:Android/data/$packageId")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, GRANT_REQUEST)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != GRANT_REQUEST) return false
        val tree = data?.data
        if (resultCode == Activity.RESULT_OK && tree != null) {
            activity.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            pendingGrant?.success(tree.toString())
        } else {
            pendingGrant?.success(null)
        }
        pendingGrant = null
        return true
    }

    /** Walks a granted folder: in the game's own tree only `files/<account>` is entered. */
    private fun readTree(tree: Uri): List<Map<String, Any?>> {
        val resolver = activity.contentResolver
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val packageId = PACKAGES.firstOrNull { rootId == "primary:Android/data/$it" || rootId.startsWith("primary:Android/data/$it/") }
        val out = ArrayList<Map<String, Any?>>()
        fun walk(docId: String, path: String, depth: Int) {
            if (depth > 4 || out.size > 400) return
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            val columns = arrayOf(
                Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
                Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED,
            )
            val rows = ArrayList<Array<Any?>>()
            resolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) rows += arrayOf(c.getString(0), c.getString(1), c.getString(2), c.getLong(3), c.getLong(4))
            }
            for ((id, name, mime, size, modified) in rows.map { Row(it) }) {
                if (mime == Document.MIME_TYPE_DIR) {
                    if (name in SKIPPED) continue
                    if (packageId != null && name != "files" && !ACCOUNT_DIR.matches(name)) continue
                    walk(id, "$path/$name", depth + 1)
                } else if (size in 1..MAX_FILE) {
                    val bytes = resolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, id))?.use { it.readBytes() } ?: continue
                    out += mapOf("source" to "$path/$name", "group" to path, "modified" to modified, "package" to packageId, "bytes" to bytes)
                }
            }
        }
        walk(rootId, packageId ?: rootId, 0)
        return out
    }

    private class Row(values: Array<Any?>) {
        val id = values[0] as String
        val name = (values[1] as String?) ?: ""
        val mime = values[2] as String?
        val size = values[3] as Long
        val modified = values[4] as Long
        operator fun component1() = id
        operator fun component2() = name
        operator fun component3() = mime
        operator fun component4() = size
        operator fun component5() = modified
    }

    companion object {
        private const val SHIZUKU_REQUEST = 7301
        private const val GRANT_REQUEST = 7302
        private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
        private const val STORAGE = "com.android.externalstorage.documents"
        private const val MAX_FILE = 16L shl 20
        private val PACKAGES = listOf("com.bilibili.sirius.official", "com.bilibili.sirius", "com.bushiroad.sirius")
        private val ACCOUNT_DIR = Regex("^[0-9a-fA-F]{16,128}$")
        private val SKIPPED = setOf(
            "EncryptedBundles", "Addressables", "Master", "RemoteCatalog", "il2cpp", "Unity", "UnityCache", "cache", "tmp",
            "com.unity3d.player",
        )
    }
}
