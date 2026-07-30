import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> quickDropAdminMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class QuickDropAdminNotificationService {
  QuickDropAdminNotificationService({
    required this.onOrderTap,
  });

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'quickdrop_admin_high_importance',
    'QuickDrop admin notifications',
    description: 'Admin order alerts',
    importance: Importance.high,
  );

  final Future<void> Function(String orderId) onOrderTap;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    await _requestPermissions();
    await _initializeLocalNotifications();
    await _syncCurrentToken();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      unawaited(_syncCurrentToken());
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleMessageTap(initialMessage));
      });
    }

    _initialized = true;
  }

  Future<void> refreshToken() async {
    if (kIsWeb) {
      return;
    }

    await _syncCurrentToken();
  }

  Future<void> _requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotificationsPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) {
          return;
        }

        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          unawaited(_handlePayload(decoded));
        }
      },
    );

    final androidImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(_channel);
  }

  Future<void> _syncCurrentToken() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final adminId = currentUser?.uid;
    if (adminId == null || adminId.isEmpty) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await _firestore.collection('notification_tokens').doc('admin_$adminId').set(
      {
        'userType': 'admin',
        'userId': adminId,
        'fcmToken': token,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? _titleFromData(message.data);
    final body = message.notification?.body ?? _bodyFromData(message.data);
    final payload = jsonEncode(_stringifyData(message.data));

    await _localNotificationsPlugin.show(
      _notificationIdFromData(message.data),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _handleMessageTap(RemoteMessage message) async {
    await _handlePayload(message.data);
  }

  Future<void> _handlePayload(Map<String, dynamic> data) async {
    final orderId = data['orderId']?.toString().trim() ?? '';
    if (orderId.isEmpty) {
      return;
    }

    await onOrderTap(orderId);
  }

  String _titleFromData(Map<String, dynamic> data) {
    final kind = data['kind']?.toString().trim().toLowerCase() ?? '';
    if (kind == 'new_order') {
      return 'New Order Received';
    }

    return 'QuickDrop admin notification';
  }

  String _bodyFromData(Map<String, dynamic> data) {
    final kind = data['kind']?.toString().trim().toLowerCase() ?? '';
    if (kind == 'new_order') {
      final orderId = data['orderId']?.toString().trim() ?? '';
      return orderId.isEmpty
          ? 'A new order has been received.'
          : 'Order $orderId has been received.';
    }

    return 'You have a new notification from QuickDrop.';
  }

  int _notificationIdFromData(Map<String, dynamic> data) {
    final seed = data['orderId']?.toString() ?? data['kind']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return seed.hashCode & 0x7fffffff;
  }

  Map<String, String> _stringifyData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }
}
