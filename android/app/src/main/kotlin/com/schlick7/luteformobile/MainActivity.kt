package com.schlick7.luteformobile

import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private var termuxBridge: TermuxBridge? = null
    private var androidAppBridge: AndroidAppBridge? = null
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var hasAutoLaunched = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        android.util.Log.d("MainActivity", ">>> onCreate() <<<")
        setHighRefreshRate()

        if (!hasAutoLaunched) {
            hasAutoLaunched = true
            mainScope.launch {
                checkAndAutoLaunchTermux()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        android.util.Log.d("MainActivity", ">>> onResume() <<<")
        setHighRefreshRate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        setHighRefreshRate()
    }

    private fun setHighRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }

                if (display != null) {
                    val supportedModes = display.supportedModes
                    val maxMode = supportedModes.maxByOrNull { it.refreshRate }
                    if (maxMode != null) {
                        val layoutParams = window.attributes
                        if (layoutParams.preferredDisplayModeId != maxMode.modeId) {
                            layoutParams.preferredDisplayModeId = maxMode.modeId
                            window.attributes = layoutParams
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to set high refresh rate: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        android.util.Log.d("MainActivity", ">>> configureFlutterEngine() <<<")
        termuxBridge = TermuxBridge(this)
        termuxBridge?.registerMethodChannel(flutterEngine)

        androidAppBridge = AndroidAppBridge(this)
        androidAppBridge?.registerMethodChannel(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        termuxBridge?.dispose()
        androidAppBridge?.dispose()
    }

    /**
     * Checks if Termux should be launched on app start.
     * This is called in onCreate() to ensure it runs early in the app lifecycle.
     * Uses ContentProvider's cached server health check result when available.
     */
    private fun checkAndAutoLaunchTermux() {
        try {
            val prefs: SharedPreferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            val useTermux = prefs.getBoolean("flutter.use_termux", false)

            android.util.Log.d(
                "MainActivity",
                "checkAndAutoLaunchTermux: useTermux=$useTermux"
            )

            // Check ContentProvider for cached server health
            val cachedRunning = ServerHealthProvider.isServerRunning
            android.util.Log.d("MainActivity", "Cached server status from ContentProvider: $cachedRunning")

            if (useTermux) {
                // Perform auto-launch in a coroutine
                mainScope.launch {
                    try {
                        android.util.Log.d(
                            "MainActivity",
                            "Auto-launching Lute3 server..."
                        )
                        launchLute3ServerWithAutoShutdown(this@MainActivity)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Auto-launch failed: ${e.message}")
                    }
                }
            } else {
                android.util.Log.d(
                    "MainActivity",
                    "Auto-launch conditions not met: useTermux=$useTermux"
                )
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error in checkAndAutoLaunchTermux: ${e.message}")
        }
    }
}
