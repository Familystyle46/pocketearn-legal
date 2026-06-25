package com.tiipee.tiipee

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel

class ScreenMonitorService : Service() {

    companion object {
        const val CHANNEL_ID = "tiipee_monitor"
        const val NOTIFICATION_ID = 42

        // Sink partagé avec MainActivity via l'EventChannel
        var eventSink: EventChannel.EventSink? = null
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    val ts = System.currentTimeMillis()
                    // Persiste le début de session côté natif : survit à la
                    // mort du moteur Flutter (l'app n'a pas besoin d'être ouverte).
                    prefs().edit().putLong("pending_start", ts).apply()
                    eventSink?.success(mapOf("type" to "screen_off", "ts" to ts))
                    updateNotification(screenOff = true)
                }
                Intent.ACTION_SCREEN_ON -> {
                    val end = System.currentTimeMillis()
                    val start = prefs().getLong("pending_start", 0L)
                    if (start > 0L) {
                        recordSession(start, end)
                        prefs().edit().remove("pending_start").apply()
                    }
                    eventSink?.success(mapOf("type" to "screen_on", "ts" to end))
                    updateNotification(screenOff = false)
                }
            }
        }
    }

    private fun prefs() =
        getSharedPreferences("tiipee_sessions", Context.MODE_PRIVATE)

    /** Ajoute une session terminée à la file locale (lue ensuite par Flutter). */
    private fun recordSession(start: Long, end: Long) {
        val dur = end - start
        // Ignore les sessions < 1 min ou aberrantes (> 12h) — cohérent avec saveSession.
        if (dur < 60_000L || dur > 12L * 3_600_000L) return
        try {
            val arr = org.json.JSONArray(prefs().getString("sessions", "[]"))
            arr.put(org.json.JSONObject().put("start", start).put("end", end))
            prefs().edit().putString("sessions", arr.toString()).apply()
        } catch (e: Exception) { /* ignoré : ne jamais crasher le service */ }
    }

    // Évite unregisterReceiver sur un receiver jamais enregistré (si on s'arrête
    // tôt parce que startForeground a échoué).
    private var receiverRegistered = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        // Android 12+ : démarrer un foreground service depuis l'arrière-plan peut
        // être interdit (ForegroundServiceStartNotAllowedException) ou échouer. On
        // protège l'appel : en cas d'échec on s'arrête proprement plutôt que de
        // laisser le système tuer l'app ("ForegroundServiceDidNotStartInTime").
        try {
            startForeground(NOTIFICATION_ID, buildNotification(screenOff = false))
        } catch (e: Exception) {
            stopSelf()
            return
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        // Sur Android 13+, le receiver doit être déclaré non-exporté
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(screenReceiver, filter)
        }
        receiverRegistered = true
    }

    // START_NOT_STICKY : on ne laisse PAS Android relancer le service en
    // arrière-plan (interdit sur Android 12+ → crash). Il repart quand l'app
    // revient au premier plan (EventChannel / startMonitoring).
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(screenReceiver)
            } catch (e: Exception) { /* ignoré : ne jamais crasher à l'arrêt */ }
            receiverRegistered = false
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun updateNotification(screenOff: Boolean) {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(screenOff))
    }

    private fun buildNotification(screenOff: Boolean): Notification {
        val text = if (screenOff)
            "💰 En pause – tu gagnes de l'argent !"
        else
            "Éteins l'écran pour commencer à gagner"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Tiipee")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Suivi pause écran",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Indique quand l'écran est éteint pour calculer les gains"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }
}
