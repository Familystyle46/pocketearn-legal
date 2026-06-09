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
                    eventSink?.success(mapOf("type" to "screen_off", "ts" to System.currentTimeMillis()))
                    updateNotification(screenOff = true)
                }
                Intent.ACTION_SCREEN_ON -> {
                    eventSink?.success(mapOf("type" to "screen_on", "ts" to System.currentTimeMillis()))
                    updateNotification(screenOff = false)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(screenOff = false))

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
    }

    // START_STICKY : Android relance le service s'il est tué
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        unregisterReceiver(screenReceiver)
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
