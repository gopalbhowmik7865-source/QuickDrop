import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Order scoped chat between the customer and the assigned delivery partner.
/// Both apps read/write the same `orders/{orderId}/messages` collection.
class OrderChatPage extends StatefulWidget {
  const OrderChatPage({
    super.key,
    required this.orderDocId,
    required this.orderDisplayId,
    this.riderName,
    this.customerName,
  });

  final String orderDocId;
  final String orderDisplayId;
  final String? riderName;
  final String? customerName;

  @override
  State<OrderChatPage> createState() => _OrderChatPageState();
}

class _OrderChatPageState extends State<OrderChatPage>
    with WidgetsBindingObserver {
  static const Color _accent = QuickDropColors.primary;
  static const Color _background = QuickDropColors.background;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _isForeground = true;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderDocId)
          .collection('messages');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  // Marks incoming messages delivered as soon as they arrive, and seen only
  // while this chat screen is actually open and the app is in the foreground.
  Future<void> _updateIncomingStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    var hasUpdates = false;
    for (final doc in docs) {
      final data = doc.data();
      if (data['senderId'] == uid) {
        continue;
      }
      final update = <String, dynamic>{};
      if (data['isDelivered'] != true) {
        update['isDelivered'] = true;
        update['deliveredAt'] = FieldValue.serverTimestamp();
      }
      if (_isForeground && data['isSeen'] != true) {
        update['isSeen'] = true;
        update['seenAt'] = FieldValue.serverTimestamp();
      }
      if (update.isNotEmpty) {
        batch.update(doc.reference, update);
        hasUpdates = true;
      }
    }
    if (!hasUpdates) {
      return;
    }
    try {
      await batch.commit();
    } catch (_) {
      // Ignore; delivery/seen status is non-critical to chat functioning.
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again to send messages.')),
      );
      return;
    }

    final senderName = widget.customerName?.trim().isNotEmpty == true
        ? widget.customerName!.trim()
        : 'Customer';

    setState(() => _isSending = true);
    try {
      await _messagesRef.add({
        'senderId': uid,
        'senderType': 'customer',
        'senderName': senderName,
        'message': text,
        'createdAt': FieldValue.serverTimestamp(),
        'isDelivered': false,
        'isSeen': false,
      });
      _messageController.clear();
      _scrollToLatest();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send message: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatTimestamp(dynamic createdAt) {
    if (createdAt is! Timestamp) {
      return 'Sending...';
    }
    final date = createdAt.toDate();
    var hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final meridiem = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return '$hour:$minute $meridiem';
  }

  Widget _statusIndicator(Map<String, dynamic> data) {
    final seen = data['isSeen'] == true;
    final delivered = data['isDelivered'] == true;
    final color = seen ? QuickDropColors.primary : QuickDropColors.secondaryText;
    final label = seen ? 'Seen' : (delivered ? 'Delivered' : 'Sent');
    final icon = seen || delivered ? Icons.done_all_rounded : Icons.done_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _messageBubble(Map<String, dynamic> data, {required bool isMine}) {
    final message = data['message']?.toString() ?? '';
    final senderType = (data['senderType']?.toString() ?? '').toLowerCase();
    final senderName = data['senderName']?.toString().trim();
    final label = isMine
        ? 'You'
        : (senderName?.isNotEmpty == true
              ? senderName!
              : (senderType == 'customer' ? 'Customer' : 'Delivery Partner'));
    final roleTag = senderType == 'customer' ? 'Customer' : 'Delivery Partner';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: isMine ? 0 : 6,
              right: isMine ? 6 : 0,
              bottom: 2,
            ),
            child: Text(
              isMine ? label : '$label · $roleTag',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9E9E9E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMine ? QuickDropColors.primaryLight : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              border: Border.all(color: QuickDropColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: QuickDropColors.darkText,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTimestamp(data['createdAt']),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMine
                            ? QuickDropColors.darkText
                            : QuickDropColors.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 6),
                      _statusIndicator(data),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderName = widget.riderName?.trim();
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: QuickDropColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: QuickDropColors.darkText),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              riderName == null || riderName.isEmpty
                  ? 'Delivery Partner'
                  : riderName,
              style: const TextStyle(
                color: QuickDropColors.darkText,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              'Order ${widget.orderDisplayId}',
              style: const TextStyle(
                color: QuickDropColors.secondaryText,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _ChatPatternPainter()),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesRef.orderBy('createdAt').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load messages.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
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
                        'No messages yet.\nSay hello to your delivery partner.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                _scrollToLatest();
                _updateIncomingStatus(docs);

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return _messageBubble(
                      data,
                      isMine: data['senderId'] == myUid,
                    );
                  },
                );
              },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed:
                        _messageController.text.trim().isEmpty || _isSending
                        ? null
                        : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    color: Colors.white,
                    disabledColor: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          _messageController.text.trim().isEmpty || _isSending
                          ? const Color(0xFFE0E0E0)
                          : _accent,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint repeating delivery-themed icon pattern for the chat background.
/// Kept extremely low opacity so it never interferes with message text.
class _ChatPatternPainter extends CustomPainter {
  const _ChatPatternPainter();

  static const List<IconData> _icons = [
    Icons.inventory_2_outlined,
    Icons.shopping_bag_outlined,
    Icons.location_on_outlined,
    Icons.bolt_outlined,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 74.0;
    const iconSize = 22.0;
    final color = const Color(0xFF9E9E9E).withValues(alpha: 0.05);

    var row = 0;
    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      final rowOffset = row.isEven ? 0.0 : spacing / 2;
      var col = 0;
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final icon = _icons[(row + col) % _icons.length];
        final textPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x + rowOffset, y));
        col++;
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) => false;
}
