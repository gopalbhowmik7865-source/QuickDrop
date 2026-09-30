import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'services/rider_assignment_service.dart';

enum OrderStatus {
  pending,
  accepted,
  packed,
  goingToStore,
  reachedStore,
  orderCollected,
  outForDelivery,
  delivered,
  rejected,
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
      case OrderStatus.goingToStore:
        return 'Going to Store';
      case OrderStatus.reachedStore:
        return 'Reached Store';
      case OrderStatus.orderCollected:
        return 'Order Collected';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.rejected:
        return 'Rejected';
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
      case 'going to store':
      case 'going_to_store':
        return OrderStatus.goingToStore;
      case 'reached store':
      case 'reached_store':
        return OrderStatus.reachedStore;
      case 'order collected':
      case 'order_collected':
        return OrderStatus.orderCollected;
      case 'out for delivery':
      case 'outfordelivery':
      case 'out_for_delivery':
        return OrderStatus.outForDelivery;
      case 'delivered':
        return OrderStatus.delivered;
      case 'rejected':
        return OrderStatus.rejected;
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
      case OrderStatus.goingToStore:
      case OrderStatus.reachedStore:
      case OrderStatus.orderCollected:
        return Colors.indigo;
      case OrderStatus.outForDelivery:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.rejected:
        return Colors.red;
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
      case OrderStatus.goingToStore:
        return Icons.storefront_outlined;
      case OrderStatus.reachedStore:
        return Icons.location_on_outlined;
      case OrderStatus.orderCollected:
        return Icons.shopping_bag_outlined;
      case OrderStatus.outForDelivery:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.done_all_outlined;
      case OrderStatus.rejected:
        return Icons.cancel_outlined;
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

  Widget _assignedRiderCard({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> orderRef,
    required String? assignedPartnerId,
  }) {
    const labelStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey,
      fontWeight: FontWeight.w600,
    );
    const valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1F2A44),
    );

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
          const Text('Assigned Rider', style: labelStyle),
          const SizedBox(height: 6),
          if (assignedPartnerId == null)
            const Text('Not Assigned', style: valueStyle)
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              key: ValueKey(assignedPartnerId),
              stream: FirebaseFirestore.instance
                  .collection('delivery_partners')
                  .doc(assignedPartnerId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Assigned Rider unavailable',
                    style: valueStyle,
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                final rider = snapshot.data?.data();
                if (rider == null) {
                  return const Text(
                    'Assigned Rider unavailable',
                    style: valueStyle,
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayValue(rider['name']), style: valueStyle),
                    const SizedBox(height: 2),
                    Text(_displayValue(rider['phone'])),
                  ],
                );
              },
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  _showRiderPicker(context, orderRef, assignedPartnerId),
              icon: const Icon(Icons.delivery_dining_outlined, size: 18),
              label: Text(
                assignedPartnerId == null ? 'Assign Rider' : 'Reassign Rider',
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0B6DFF),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRiderPicker(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> orderRef,
    String? currentPartnerId,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select Rider'),
          content: SizedBox(
            width: 360,
            height: 340,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('delivery_partners')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load riders.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final riders = snapshot.data?.docs ?? const [];
                if (riders.isEmpty) {
                  return const Center(
                    child: Text('No active riders available.'),
                  );
                }

                return ListView.separated(
                  itemCount: riders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final riderDoc = riders[index];
                    final rider = riderDoc.data();
                    final isCurrent = riderDoc.id == currentPartnerId;
                    final heldOrderId =
                        rider['currentOrderId']?.toString().trim() ?? '';

                    return ListTile(
                      leading: const Icon(
                        Icons.delivery_dining_outlined,
                        color: Color(0xFF0B6DFF),
                      ),
                      title: Text(_displayValue(rider['name'])),
                      subtitle: Text(
                        '${_displayValue(rider['phone'])}\n'
                        'on duty: ${rider['isOnDuty'] == true}, '
                        'status: ${_displayValue(rider['availabilityStatus'])}'
                        '${heldOrderId.isEmpty ? '' : ', order: $heldOrderId'}',
                      ),
                      isThreeLine: true,
                      trailing: isCurrent
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF0B6DFF),
                            )
                          : heldOrderId.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Check held order / release stale lock',
                              icon: const Icon(Icons.healing_outlined),
                              onPressed: () => _repairRiderLock(
                                dialogContext,
                                riderDoc.id,
                              ),
                            ),
                      onTap: isCurrent
                          ? null
                          : () => _assignRider(
                              dialogContext,
                              orderRef,
                              riderDoc.id,
                            ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _repairRiderLock(
    BuildContext dialogContext,
    String riderId,
  ) async {
    final messenger = ScaffoldMessenger.of(dialogContext);

    try {
      final diagnosis = await RiderAssignmentService().repairStaleRiderLock(
        riderId,
      );
      final message = diagnosis.isStale
          ? 'Released stale lock: ${diagnosis.description} '
                'The rider must go on duty again to receive orders.'
          : diagnosis.description;
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
      );
    } on RiderAssignmentException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to check rider: ${error.code} ${error.message ?? ''}'
                .trim(),
          ),
        ),
      );
    }
  }

  Future<void> _assignRider(
    BuildContext dialogContext,
    DocumentReference<Map<String, dynamic>> orderRef,
    String partnerId,
  ) async {
    final messenger = ScaffoldMessenger.of(dialogContext);
    Navigator.of(dialogContext).pop();

    try {
      final riderRef = FirebaseFirestore.instance
          .collection('delivery_partners')
          .doc(partnerId);
      // On web the JS interop boxes exceptions thrown inside the transaction
      // callback, so the reason is returned instead of thrown.
      String? blockedReason;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        blockedReason = null;
        final orderSnapshot = await transaction.get(orderRef);
        final riderSnapshot = await transaction.get(riderRef);
        final order = orderSnapshot.data();
        final rider = riderSnapshot.data();

        if (order == null || rider == null) {
          blockedReason = 'Order or rider is no longer available.';
          return;
        }
        final status = (order['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'pending' && status != 'rejected') {
          blockedReason =
              'Only pending or rider-rejected orders can be assigned.';
          return;
        }
        final previousPartnerId =
            (order['assignedPartnerId'] ?? '').toString().trim();
        if (previousPartnerId == partnerId) {
          blockedReason = 'This rider is already assigned to the order.';
          return;
        }
        if (rider['isActive'] != true ||
            rider['isOnDuty'] != true ||
            (rider['availabilityStatus'] ?? '').toString().trim() !=
                'available' ||
            (rider['currentOrderId'] ?? '').toString().trim().isNotEmpty) {
          blockedReason =
              'This rider is not available '
              '(on duty: ${rider['isOnDuty'] == true}, '
              'status: ${_displayValue(rider['availabilityStatus'])}, '
              'current order: ${_displayValue(rider['currentOrderId'])}).';
          return;
        }

        DocumentSnapshot<Map<String, dynamic>>? previousRiderSnapshot;
        if (previousPartnerId.isNotEmpty) {
          previousRiderSnapshot = await transaction.get(
            FirebaseFirestore.instance
                .collection('delivery_partners')
                .doc(previousPartnerId),
          );
          final previousRider = previousRiderSnapshot.data();
          final previousOrderId =
              (previousRider?['currentOrderId'] ?? '').toString().trim();
          if (previousOrderId.isNotEmpty && previousOrderId != orderRef.id) {
            blockedReason =
                'The previous rider now holds a different order. Refresh before reassigning.';
            return;
          }
        }

        final orderUpdate = <String, dynamic>{
          'assignedPartnerId': partnerId,
          'assignedAt': FieldValue.serverTimestamp(),
          'assignmentType': 'manual',
        };
        if (status == 'rejected') {
          orderUpdate.addAll({
            'status': 'Pending',
            'statusUpdatedAt': FieldValue.serverTimestamp(),
            'statusHistory': FieldValue.arrayUnion([
              {'status': 'Pending', 'updatedAt': Timestamp.now()},
            ]),
          });
        }
        transaction.update(orderRef, orderUpdate);

        final previousRider = previousRiderSnapshot?.data();
        if (previousRider != null &&
            (previousRider['currentOrderId'] ?? '').toString().trim() ==
                orderRef.id) {
          transaction.update(previousRiderSnapshot!.reference, {
            'currentOrderId': '',
            'currentOrderAssignedAt': FieldValue.delete(),
            'availabilityStatus': previousRider['isOnDuty'] == true
                ? 'available'
                : 'offline',
            'currentOrderReleasedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.update(riderRef, {
          'availabilityStatus': 'assigned',
          'currentOrderId': orderRef.id,
          'currentOrderAssignedAt': FieldValue.serverTimestamp(),
        });
      });

      final reason = blockedReason;
      if (reason != null) {
        messenger.showSnackBar(SnackBar(content: Text(reason)));
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Rider reserved. Waiting for rider acceptance.'),
        ),
      );
    } on FirebaseException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to assign rider: ${error.code} ${error.message ?? ''}'
                .trim(),
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Manual rider assignment failed: $error\n$stackTrace');
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to assign rider: $error')),
      );
    }
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
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
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
        final pickupName = _displayValue(
          data['pickupName'] ?? data['shopNameSnapshot'],
        );
        final pickupAddress = _displayValue(
          data['pickupAddress'] ?? data['shopAddressSnapshot'],
        );
        final paymentMethod = _displayValue(data['paymentMethod']);
        final paymentStatus = _displayValue(data['paymentStatus']);
        final paymentIdValue = data['paymentId']?.toString().trim() ?? '';
        final paymentId = paymentIdValue.isEmpty ? null : paymentIdValue;
        final totalAmount = _displayAmount(data['totalAmount']);
        final createdAt = _formatOrderDate(data['createdAt']);
        final history = (data['statusHistory'] as List<dynamic>?) ?? const [];
        final items = (data['items'] as List<dynamic>?) ?? const [];
        final assignedPartnerIdValue =
            data['assignedPartnerId']?.toString().trim() ?? '';
        final assignedPartnerId = assignedPartnerIdValue.isEmpty
            ? null
            : assignedPartnerIdValue;

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
                  if (pickupName != '-' || pickupAddress != '-')
                    _detailCard(
                      label: 'Pickup Store',
                      value: pickupName == '-'
                          ? pickupAddress
                          : pickupAddress == '-'
                          ? pickupName
                          : '$pickupName\n$pickupAddress',
                    ),
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
                  _assignedRiderCard(
                    context: context,
                    orderRef: doc.reference,
                    assignedPartnerId: assignedPartnerId,
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
