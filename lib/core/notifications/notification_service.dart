import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../supabase/supabase_service.dart';

// Canal Android pour les demandes de versement
const _payoutChannel = AndroidNotificationChannel(
  'tiipee_payouts',
  'Versements',
  description: 'Notifications de demandes de versement',
  importance: Importance.high,
);

final _localNotifications = FlutterLocalNotificationsPlugin();

/// Initialise Firebase + FCM + notifications locales.
/// À appeler dans main() après WidgetsFlutterBinding.ensureInitialized().
Future<void> initNotifications() async {
  await Firebase.initializeApp();

  // Crée le canal Android
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_payoutChannel);

  await _localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  // Écoute les messages en foreground
  FirebaseMessaging.onMessage.listen((message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _payoutChannel.id,
          _payoutChannel.name,
          channelDescription: _payoutChannel.description,
          icon: '@drawable/ic_notification',
        ),
      ),
    );
  });
}

/// Demande la permission de notif et sauvegarde le token FCM dans Supabase.
Future<void> saveFCMToken(String userId) async {
  try {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token == null) return;

    await supabase
        .from('users')
        .update({'fcm_token': token})
        .eq('id', userId);

    // Renouvellement automatique du token
    messaging.onTokenRefresh.listen((newToken) async {
      await supabase
          .from('users')
          .update({'fcm_token': newToken})
          .eq('id', userId);
    });
  } catch (e) {
    debugPrint('FCM token error: $e');
  }
}

/// Appelle l'Edge Function pour notifier le parent après une demande de versement.
Future<void> notifyParentPayout({
  required String childId,
  required String childName,
  required int amountCents,
  required String parentId,
}) async {
  try {
    await supabase.functions.invoke(
      'notify-payout-request',
      body: {
        'childId': childId,
        'childName': childName,
        'amountCents': amountCents,
        'parentId': parentId,
      },
    );
  } catch (e) {
    debugPrint('Notification erreur: $e');
  }
}

/// Notifie l'enfant que le parent a validé son versement (push + local notif).
Future<void> notifyChildPayoutValidated({
  required String childId,
  required int amountCents,
}) async {
  try {
    final amount = (amountCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    // Push FCM vers l'enfant
    await supabase.functions.invoke(
      'notify-child-payout-validated',
      body: {
        'childId': childId,
        'amountCents': amountCents,
      },
    );
    debugPrint('Notif enfant envoyée : $amount€');
  } catch (e) {
    debugPrint('Notif enfant erreur: $e');
  }
}
