package com.tiipee.tiipee

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.tiipee/screen_time"
    private val EVENT_CHANNEL  = "com.tiipee/screen_events"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel : permissions + usage stats ──────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission"      -> result.success(hasUsagePermission())
                    "requestPermission"  -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "getScreenOffMinutes" -> {
                        val hours = call.argument<Int>("hours") ?: 24
                        result.success(getScreenOffMinutes(hours))
                    }
                    "startMonitoring"    -> { startMonitorService(); result.success(null) }
                    "stopMonitoring"     -> {
                        stopService(Intent(this, ScreenMonitorService::class.java))
                        result.success(null)
                    }
                    else                 -> result.notImplemented()
                }
            }

        // ── EventChannel : événements écran on/off en temps réel ───────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    ScreenMonitorService.eventSink = events
                    startMonitorService()
                }
                override fun onCancel(arguments: Any?) {
                    ScreenMonitorService.eventSink = null
                }
            })
    }

    private fun startMonitorService() {
        val intent = Intent(this, ScreenMonitorService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    // ── UsageStatsManager (toujours disponible pour stats historiques) ─

    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getScreenOffMinutes(hours: Int): Int {
        val mgr      = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime  = System.currentTimeMillis()
        val startTime = endTime - hours * 3_600_000L
        val fgMs     = mgr.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
            ?.sumOf { it.totalTimeInForeground } ?: 0L
        return ((endTime - startTime - fgMs).coerceAtLeast(0L) / 60_000L).toInt()
    }
}
