import 'dart:io';
import 'package:flutter/services.dart';

class ScreenTimeService {
  static const _channel      = MethodChannel('com.tiipee/screen_time');
  static const _eventChannel = EventChannel('com.tiipee/screen_events');

  /// Sur Android, la détection est automatique via BroadcastReceiver.
  /// Sur iOS, on reste en mode timer manuel jusqu'à l'entitlement FamilyControls.
  static bool get supportsAutoDetection => Platform.isAndroid;

  // ── Permissions ──────────────────────────────────────────────

  static Future<bool> hasPermission() async {
    if (Platform.isIOS) return true;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  static Future<void> requestPermission() async {
    if (Platform.isAndroid) await _channel.invokeMethod('requestPermission');
  }

  // ── Service de surveillance ───────────────────────────────────

  static Future<void> startMonitoring() async {
    if (Platform.isAndroid) await _channel.invokeMethod('startMonitoring');
  }

  static Future<void> stopMonitoring() async {
    if (Platform.isAndroid) await _channel.invokeMethod('stopMonitoring');
  }

  /// Stream d'événements écran (Android uniquement).
  /// Chaque événement : {"type": "screen_off"|"screen_on", "ts": millisEpoch}
  static Stream<Map<String, dynamic>> get screenEventStream {
    if (!Platform.isAndroid) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
  }

  // ── Stats historiques (fallback / iOS) ───────────────────────

  static Future<int> getScreenOffMinutes({int hours = 24}) async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<int>(
        'getScreenOffMinutes', {'hours': hours},
      ) ?? 0;
    }
    return 0;
  }
}
