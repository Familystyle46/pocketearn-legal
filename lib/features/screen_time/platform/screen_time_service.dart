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

  /// Récupère et vide la file des sessions enregistrées par le service natif
  /// (écran éteint→allumé), même quand l'app n'était pas ouverte. Android only.
  /// Chaque entrée : {"start": millisEpoch, "end": millisEpoch}.
  static Future<List<Map<String, dynamic>>> getAndClearPendingSessions() async {
    if (!Platform.isAndroid) return const [];
    final raw =
        await _channel.invokeMethod<List<dynamic>>('getAndClearPendingSessions');
    if (raw == null) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ── Screen Time iOS (Family Controls) ─────────────────────────
  // Méthodes spécifiques iOS, additives. Sur Android elles sont neutres.
  // Le module natif iOS mesure les minutes d'usage via une extension
  // DeviceActivityMonitor et les écrit dans un App Group ; iOS doit donc
  // 1) demander l'autorisation, 2) choisir les apps à suivre, 3) démarrer
  // le monitoring. Les minutes sont ensuite lues via getDailyScreenOnMinutes.

  /// Présente le sélecteur d'apps Apple (FamilyActivityPicker). iOS only.
  /// Renvoie le nombre d'éléments sélectionnés, -1 si annulé, false→0 sinon.
  static Future<int> presentAppPicker() async {
    if (!Platform.isIOS) return 0;
    final res = await _channel.invokeMethod<int>('presentAppPicker');
    return res ?? 0;
  }

  /// Vrai si une sélection d'apps à suivre a déjà été enregistrée. iOS only.
  static Future<bool> hasAppSelection() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('hasAppSelection') ?? false;
  }

  /// Démarre le monitoring Screen Time (planning quotidien + seuils). iOS only.
  /// Renvoie vrai si le monitoring a bien démarré (nécessite une sélection).
  static Future<bool> startScreenTimeMonitoring() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('startMonitoring') ?? false;
  }

  /// Arrête le monitoring Screen Time. iOS only.
  static Future<void> stopScreenTimeMonitoring() async {
    if (Platform.isIOS) await _channel.invokeMethod('stopMonitoring');
  }

  // ── Optimisation batterie (Android) ───────────────────────────
  // Indispensable pour que le service survive en arrière-plan sur MIUI/Oppo.

  /// Vrai si l'app est déjà exemptée d'optimisation batterie.
  /// Renvoie true hors Android (rien à faire).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        true;
  }

  /// Ouvre la demande système d'exemption d'optimisation batterie.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    }
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

  /// Temps d'écran (minutes d'usage) par jour calendaire local, sur les
  /// [days] derniers jours (aujourd'hui inclus). Android uniquement.
  /// Nécessite la permission "Accès à l'usage" (cf. hasPermission()).
  /// Chaque entrée : {"day": "yyyy-MM-dd", "minutes": int}.
  static Future<List<Map<String, dynamic>>> getDailyScreenOnMinutes({
    int days = 7,
  }) async {
    if (!Platform.isAndroid) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'getDailyScreenOnMinutes', {'days': days},
    );
    if (raw == null) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
