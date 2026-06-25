package com.tiipee.tiipee

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
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
                    "getDailyScreenOnMinutes" -> {
                        val days = call.argument<Int>("days") ?: 7
                        result.success(getDailyScreenOnMinutes(days))
                    }
                    "startMonitoring"    -> { startMonitorService(); result.success(null) }
                    "stopMonitoring"     -> {
                        stopService(Intent(this, ScreenMonitorService::class.java))
                        result.success(null)
                    }
                    "getAndClearPendingSessions" ->
                        result.success(getAndClearPendingSessions())
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
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
        // Android 12+ : startForegroundService() lève
        // ForegroundServiceStartNotAllowedException si l'app est en arrière-plan.
        // On protège : si c'est refusé, le service repartira au prochain passage
        // au premier plan — on ne crashe jamais.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) { /* démarrage refusé en arrière-plan : ignoré */ }
    }

    // ── File de sessions enregistrées par le service natif ─────────────────
    // Lue puis vidée par Flutter pour synchroniser vers Supabase. Permet de
    // ne perdre aucune session même si l'app n'était pas ouverte.

    private fun getAndClearPendingSessions(): List<Map<String, Any>> {
        val prefs = getSharedPreferences("tiipee_sessions", Context.MODE_PRIVATE)
        val raw = prefs.getString("sessions", "[]") ?: "[]"
        prefs.edit().remove("sessions").apply()
        val list = ArrayList<Map<String, Any>>()
        try {
            val arr = org.json.JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                list.add(mapOf("start" to o.getLong("start"), "end" to o.getLong("end")))
            }
        } catch (e: Exception) { /* ignoré */ }
        return list
    }

    // ── Optimisation batterie ──────────────────────────────────────────────
    // Permet au service de suivi de survivre en arrière-plan (MIUI/Oppo…).

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Repli : ouvre la liste des réglages d'optimisation batterie
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) { /* ignoré */ }
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

    /**
     * Temps d'écran réel par jour calendaire local, pour les `days` derniers jours
     * (aujourd'hui inclus). Renvoie une liste de maps {"day": "yyyy-MM-dd", "minutes": Int}.
     *
     * Méthode alignée sur Android Digital Wellbeing : on appaire les événements
     * « app au premier plan » → « app en arrière-plan / écran éteint » via queryEvents(),
     * au lieu de totalTimeInForeground (gonflé car il agrège launcher, System UI, services).
     */
    private fun getDailyScreenOnMinutes(days: Int): List<Map<String, Any>> {
        val mgr = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val dayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val result = mutableListOf<Map<String, Any>>()

        for (i in (days - 1) downTo 0) {
            // Début du jour local (minuit) pour le jour courant - i
            val cal = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -i)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dayStart = cal.timeInMillis
            val dayLabel = dayFormat.format(cal.time)

            // Fin de fenêtre : minuit du lendemain, borné à maintenant pour le jour en cours
            cal.add(Calendar.DAY_OF_YEAR, 1)
            val dayEnd = minOf(cal.timeInMillis, System.currentTimeMillis())

            result.add(mapOf(
                "day" to dayLabel,
                "minutes" to (computeForegroundMs(mgr, dayStart, dayEnd) / 60_000L).toInt()
            ))
        }
        return result
    }

    /**
     * Somme du temps réel passé une app à l'écran sur la fenêtre [start, end).
     * Appaire RESUMED (1) → PAUSED (2) ; toute extinction d'écran ou verrouillage
     * (SCREEN_NON_INTERACTIVE=16, KEYGUARD_SHOWN=17) ferme aussi l'intervalle courant.
     * Un seul intervalle ouvert à la fois → pas de double comptage.
     */
    private fun computeForegroundMs(mgr: UsageStatsManager, start: Long, end: Long): Long {
        val events = mgr.queryEvents(start, end)
        val ev = UsageEvents.Event()
        var total = 0L
        var resumeAt = -1L

        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            when (ev.eventType) {
                // MOVE_TO_FOREGROUND / ACTIVITY_RESUMED
                UsageEvents.Event.MOVE_TO_FOREGROUND -> resumeAt = ev.timeStamp
                // MOVE_TO_BACKGROUND / ACTIVITY_PAUSED, écran éteint (16), verrouillage (17)
                UsageEvents.Event.MOVE_TO_BACKGROUND, 16, 17 -> {
                    if (resumeAt > 0L) {
                        total += ev.timeStamp - resumeAt
                        resumeAt = -1L
                    }
                }
            }
        }
        // Si une app est encore au premier plan en fin de fenêtre (jour en cours),
        // on compte jusqu'à la fin de la fenêtre.
        if (resumeAt > 0L) total += end - resumeAt
        return total.coerceAtLeast(0L)
    }
}
