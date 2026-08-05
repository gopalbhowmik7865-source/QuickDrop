import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum OrderStatus {
  pending,
  accepted,
  packed,
  outForDelivery,
  delivered,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.packed:
        return 'Packed';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class AdminOrderDetailsPage extends StatelessWidget {
  const AdminOrderDetailsPage({super.key, required this.orderId});

  final String orderId;

  OrderStatus _orderStatusFromValue(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';

    switch (normalized) {
      case 'accepted':
      case 'confirmed':
        return OrderStatus.accepted;
      case 'packed':
        return OrderStatus.packed;
      case 'out for delivery':
      case 'outfordelivery':
      case 'out_for_delivery':
        return OrderStatus.outForDelivery;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
      case 'canceled':
        return OrderStatus.cancelled;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.packed:
        return Colors.deepPurple;
      case OrderStatus.outForDelivery:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.hourglass_top_outlined;
      case OrderStatus.accepted:
        return Icons.verified_outlined;
      case OrderStatus.packed:
        return Icons.inventory_2_outlined;
      case OrderStatus.outForDelivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.done_all_outlined;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  String _displayValue(dynamic value) {
    if (value == null) {
      return '-';
    }

    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _displayAmount(dynamic value) {
    if (value == null) {
      return '-';
    }

    if (value is num) {
      return value.toStringAsFixed(2);
    }

    return _displayValue(value);
  }

  double _amountValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(
          value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '',
        ) ??
        0;
  }

  String _currency(dynamic value) {
    return '₹${_amountValue(value).toStringAsFixed(2)}';
  }

  String _formatOrderDate(dynamic createdAt) {
    if (createdAt is Timestamp) {
      final date = createdAt.toDate();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();

      var hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final meridiem = hour >= 12 ? 'PM' : 'AM';
      if (hour == 0) {
        hour = 12;
      } else if (hour > 12) {
        hour -= 12;
      }

      return '$day/$month/$year $hour:$minute $meridiem';
    }
    return 'N/A';
  }

  Widget _statusBadge(OrderStatus status) {
    final label = status == OrderStatus.cancelled
        ? 'Order Cancelled'
        : status.label;
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _detailCard({required String label, required String value}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5F0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2A44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderItemsCard(List<dynamic> items) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5F0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ordered Items',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < items.length; index++) ...[
            if (items[index] is Map)
              Builder(
                builder: (context) {
                  final item = Map<String, dynamic>.from(items[index] as Map);
                  final image = _displayValue(
                    item['image'] ?? item['imageUrl'],
                  );
                  final brand = item['brand']?.toString().trim() ?? '';
                  final weight = item['weight']?.toString().trim() ?? '';
                  final unit = item['unit']?.toString().trim() ?? '';
                  final description =
                      item['shortDescription']?.toString().trim() ?? '';
                  final quantity = _amountValue(item['quantity']).toInt();
                  final price = _amountValue(item['price']);
                  final oldPrice = _amountValue(item['oldPrice']);
                  final discount = _amountValue(item['discountPercent']);
                  final weightUnit = [
                    weight,
                    unit,
                  ].where((value) => value.isNotEmpty).join(' ');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: image == '-'
                              ? Container(
                                  width: 72,
                                  height: 72,
                                  color: const Color(0xFFF1F6FD),
                                  child: const Icon(Icons.image_not_supported_outlined),
                                )
                              : Image.network(
                                  image,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 72,
                                    height: 72,
                                    color: const Color(0xFFF1F6FD),
                                    child: const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayValue(
                                  item['name'] ?? item['productName'],
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2A44),
                                ),
                              ),
                              if (brand.isNotEmpty) Text('Brand: $brand'),
                              if (weightUnit.isNotEmpty) Text(weightUnit),
                              if (description.isNotEmpty)
                                Text(
                                  description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text('Quantity: $quantity'),
                              Text('Price: ${_currency(price)}'),
                              if (oldPrice > 0)
                                Row(
                                  children: [
                                    const Text('Old Price: '),
                                    Text(
                                      _currency(oldPrice),
                                      style: const TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                ),
                              if (discount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE84141),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${discount.toStringAsFixed(0)}% OFF',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              Text(
                                'Item Total: ${_currency(price * quantity)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (index < items.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }

  Widget _historyCard(List<dynamic> history) {
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5F0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status History',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final entry in history)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.brightness_1,
                    size: 10,
                    color: Color(0xFF0B6DFF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (entry is Map<String, dynamic>
                              ? entry['status']?.toString()
                              : entry.toString()) ??
                          '-',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('orderId', isEqualTo: orderId)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Details')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load order details.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final doc = snapshot.data?.docs.isNotEmpty == true
            ? snapshot.data!.docs.first
            : null;
        if (doc == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Order Details')),
            body: const Center(child: Text('Order not found.')),
          );
        }

        final data = doc.data();
        final status = _orderStatusFromValue(data['status']);
        final customerName = _displayValue(
          data['customerName'] ?? data['name'] ?? data['ownerName'],
        );
        final phone = _displayValue(
          data['phoneNumber'] ?? data['phone'] ?? data['ownerPhone'],
        );
        final address = _displayValue(
          data['deliveryAddress'] ?? data['address'],
        );
        final paymentMethod = _displayValue(data['paymentMethod']);
        final paymentStatus = _displayValue(data['paymentStatus']);
        final paymentIdValue = data['paymentId']?.toString().trim() ?? '';
        final paymentId = paymentIdValue.isEmpty ? null : paymentIdValue;
        final totalAmount = _displayAmount(data['totalAmount']);
        final createdAt = _formatOrderDate(data['createdAt']);
        final history = (data['statusHistory'] as List<dynamic>?) ?? const [];
        final items = (data['items'] as List<dynamic>?) ?? const [];

        return Scaffold(
          appBar: AppBar(title: const Text('Order Details')),
          body: Container(
            color: const Color(0xFFF7FAFF),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0B6DFF), Color(0xFF4DA3FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order ID',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          orderId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _statusBadge(status),
                  const SizedBox(height: 16),
                  _detailCard(label: 'Customer', value: customerName),
                  _detailCard(label: 'Phone', value: phone),
                  _detailCard(label: 'Address', value: address),
                  _detailCard(label: 'Payment Method', value: paymentMethod),
                  _detailCard(label: 'Payment Status', value: paymentStatus),
                  if (paymentId != null)
                    _detailCard(label: 'Payment ID', value: paymentId),
                  _detailCard(
                    label: 'Order Status',
                    value: status == OrderStatus.cancelled
                        ? 'Order Cancelled'
                        : status.label,
                  ),
                  _orderItemsCard(items),
                  _detailCard(
                    label: 'Subtotal',
                    value: _displayAmount(data['subtotal']),
                  ),
                  _detailCard(
                    label: 'Delivery Charge',
                    value: _displayAmount(data['deliveryCharge']),
                  ),
                  _detailCard(label: 'Total Amount', value: totalAmount),
                  _detailCard(label: 'Order Date', value: createdAt),
                  _historyCard(history),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
