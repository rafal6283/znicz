package pl.znicz.znicz

import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Kanał „znicz/doba”: odczyt pobytów z aplikacji Doba (za zgodą użytkownika). */
class MainActivity : FlutterActivity() {
    private val perm = "pl.rafal.lifecycle.permission.READ_STAYS"
    private var pending: MethodChannel.Result? = null

    private fun installed(): Boolean = try {
        packageManager.getPackageInfo("pl.rafal.lifecycle", 0); true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun granted() = checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "znicz/doba").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf("installed" to installed(), "granted" to (installed() && granted())))
                "request" -> {
                    if (!installed()) { result.success(false); return@setMethodCallHandler }
                    if (granted()) { result.success(true); return@setMethodCallHandler }
                    pending?.success(false)
                    pending = result
                    requestPermissions(arrayOf(perm), 4711)
                }
                "stays" -> {
                    if (!installed() || !granted()) { result.success(emptyList<Any>()); return@setMethodCallHandler }
                    val from = (call.argument<Number>("from"))?.toLong() ?: 0L
                    val to = (call.argument<Number>("to"))?.toLong() ?: System.currentTimeMillis()
                    Thread {
                        val out = ArrayList<Map<String, Any?>>()
                        try {
                            contentResolver.query(
                                Uri.parse("content://pl.rafal.lifecycle.stays/stays?from=$from&to=$to"), null, null, null, null,
                            )?.use { c ->
                                while (c.moveToNext()) {
                                    out += mapOf(
                                        "start" to c.getLong(0), "end" to c.getLong(1),
                                        "lat" to c.getDouble(2), "lng" to c.getDouble(3),
                                        "place" to c.getString(4), "category" to c.getString(5),
                                    )
                                }
                            }
                        } catch (_: Exception) {
                        }
                        runOnUiThread { result.success(out) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pending = null
        }
    }
}
