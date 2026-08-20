package com.schlick7.luteformobile

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

class AndroidAppBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "AndroidAppBridge"
        private const val CHANNEL_NAME = "com.schlick7.luteformobile/android_apps"
        private const val ICON_SIZE = 96
    }

    private var channel: MethodChannel? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    fun registerMethodChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        Log.d(TAG, "AndroidAppBridge MethodChannel registered")
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledTextApps" -> {
                scope.launch {
                    try {
                        val apps = withContext(Dispatchers.IO) {
                            queryInstalledTextApps()
                        }
                        result.success(apps)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to query installed apps: ${e.message}", e)
                        result.error("QUERY_ERROR", e.message, null)
                    }
                }
            }
            "launchAppWithText" -> {
                val packageName = call.argument<String>("packageName")
                val activityName = call.argument<String>("activityName")
                val actionType = call.argument<String>("actionType") ?: "PROCESS_TEXT"
                val text = call.argument<String>("text") ?: ""

                if (packageName.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "packageName is required", null)
                    return
                }

                try {
                    val launched = launchApp(packageName, activityName, actionType, text)
                    result.success(launched)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to launch app $packageName: ${e.message}", e)
                    result.error("LAUNCH_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun queryInstalledTextApps(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val selfPackage = context.packageName
        val appMap = LinkedHashMap<String, MutableMap<String, Any?>>()

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PackageManager.MATCH_DEFAULT_ONLY
        } else {
            0
        }

        // 1. Query ACTION_PROCESS_TEXT activities
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val processTextIntent = Intent(Intent.ACTION_PROCESS_TEXT).apply {
                type = "text/plain"
            }
            val processTextActivities = pm.queryIntentActivities(processTextIntent, flags)
            for (resolveInfo in processTextActivities) {
                val pkg = resolveInfo.activityInfo.packageName
                if (pkg == selfPackage) continue

                val act = resolveInfo.activityInfo.name
                val key = "$pkg/$act"
                val label = resolveInfo.loadLabel(pm)?.toString() ?: pkg
                val iconBase64 = getIconBase64(resolveInfo, pm)

                appMap[key] = mutableMapOf(
                    "packageName" to pkg,
                    "activityName" to act,
                    "label" to label,
                    "iconBase64" to iconBase64,
                    "actionType" to "PROCESS_TEXT"
                )
            }
        }

        // 2. Query ACTION_SEND activities with mime type text/plain
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
        }
        val sendActivities = pm.queryIntentActivities(sendIntent, flags)
        for (resolveInfo in sendActivities) {
            val pkg = resolveInfo.activityInfo.packageName
            if (pkg == selfPackage) continue

            val act = resolveInfo.activityInfo.name
            val key = "$pkg/$act"

            // If already added by PROCESS_TEXT, keep PROCESS_TEXT as it is specifically designed for text processing
            if (!appMap.containsKey(key)) {
                val label = resolveInfo.loadLabel(pm)?.toString() ?: pkg
                val iconBase64 = getIconBase64(resolveInfo, pm)

                appMap[key] = mutableMapOf(
                    "packageName" to pkg,
                    "activityName" to act,
                    "label" to label,
                    "iconBase64" to iconBase64,
                    "actionType" to "SEND"
                )
            }
        }

        return appMap.values.toList()
    }

    private fun getIconBase64(resolveInfo: ResolveInfo, pm: PackageManager): String? {
        return try {
            val drawable = resolveInfo.loadIcon(pm) ?: return null
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.w(TAG, "Could not load icon for ${resolveInfo.activityInfo.packageName}: ${e.message}")
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            val src = drawable.bitmap
            if (src.width == ICON_SIZE && src.height == ICON_SIZE) {
                return src
            }
            return Bitmap.createScaledBitmap(src, ICON_SIZE, ICON_SIZE, true)
        }

        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun launchApp(
        packageName: String,
        activityName: String?,
        actionType: String,
        text: String
    ): Boolean {
        return try {
            val intent = if (actionType == "PROCESS_TEXT" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(Intent.ACTION_PROCESS_TEXT).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_PROCESS_TEXT, text)
                    putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
                    if (!activityName.isNullOrBlank()) {
                        component = ComponentName(packageName, activityName)
                    } else {
                        setPackage(packageName)
                    }
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            } else {
                Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    if (!activityName.isNullOrBlank()) {
                        component = ComponentName(packageName, activityName)
                    } else {
                        setPackage(packageName)
                    }
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            }

            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Primary launch failed: ${e.message}, attempting fallback...")
            try {
                // Fallback 1: Generic ACTION_SEND targeted at package
                val fallbackSend = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    setPackage(packageName)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(fallbackSend)
                true
            } catch (e2: Exception) {
                Log.w(TAG, "Fallback send failed: ${e2.message}, attempting package launch intent...")
                // Fallback 2: Launch main activity with extra
                val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    putExtra(Intent.EXTRA_TEXT, text)
                    putExtra("android.intent.extra.TEXT", text)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                if (launchIntent != null) {
                    context.startActivity(launchIntent)
                    true
                } else {
                    Log.e(TAG, "Could not find launch intent for $packageName")
                    false
                }
            }
        }
    }
}
