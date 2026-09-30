import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';
import 'app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final AuthService _authService = AuthService();
  late final Future<String?> _phoneFuture;

  @override
  void initState() {
    super.initState();
    _phoneFuture = _authService.getCurrentUserPhone();
  }

  DateTime _createdAtFrom(Map<String, dynamic> data) {
    final timestamp = data['createdAt'];
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  IconData _iconFromKind(String kind) {
    switch (kind) {
      case 'order_created':
        return Icons.receipt_long_rounded;
      case 'order_status':
        return Icons.local_shipping_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatTime(DateTime createdAt) {
    if (createdAt.millisecondsSinceEpoch == 0) {
      return 'Just now';
    }

    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) {
      return 'Just now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: QuickDropColors.background,
        foregroundColor: QuickDropColors.darkText,
      ),
      body: FutureBuilder<String?>(
        future: _phoneFuture,
        builder: (context, phoneSnapshot) {
          if (phoneSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final phone = phoneSnapshot.data?.trim() ?? '';
          if (phone.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No notifications yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                      color: QuickDropColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('notification_history')
                .where('recipientType', isEqualTo: 'customer')
                .where('recipientId', isEqualTo: phone)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load notifications.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: QuickDropColors.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No notifications yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }

              final sortedDocs = docs.toList()
                ..sort((a, b) {
                  final aCreatedAt = _createdAtFrom(a.data());
                  final bCreatedAt = _createdAtFrom(b.data());
                  return bCreatedAt.compareTo(aCreatedAt);
                });

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: sortedDocs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = sortedDocs[index].data();
                  final title = data['title']?.toString().trim();
                  final body = data['body']?.toString().trim();
                  final kind = data['data'] is Map
                      ? (data['data']['kind']?.toString().trim() ?? '')
                      : '';
                  final createdAt = _createdAtFrom(data);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: QuickDropColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: QuickDropColors.mint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            _iconFromKind(kind),
                            color: QuickDropColors.primaryDark,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (title == null || title.isEmpty)
                                    ? 'Notification'
                                    : title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: QuickDropColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (body == null || body.isEmpty)
                                    ? 'You have a new update.'
                                    : body,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: QuickDropColors.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatTime(createdAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: QuickDropColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
