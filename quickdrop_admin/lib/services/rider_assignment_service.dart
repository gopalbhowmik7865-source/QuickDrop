import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Maximum age of a rider location fix that is still considered usable.
const Duration kRiderLocationMaxAge = Duration(minutes: 5);

class RiderAssignmentException implements Exception {
  RiderAssignmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when no rider currently satisfies the automatic assignment rules.
class NoRiderAvailableException extends RiderAssignmentException {
  NoRiderAvailableException([
    super.message = 'No available rider found nearby.',
  ]);
}

class RiderCandidate {
  const RiderCandidate({
    required this.id,
    required this.name,
    required this.distanceKm,
  });

  final String id;
  final String name;
  final double distanceKm;
}

/// Order statuses after which a rider must no longer hold `currentOrderId`.
const Set<String> kTerminalOrderStatuses = {
  'delivered',
  'cancelled',
  'canceled',
  'rejected',
  'returned',
  'completed',
  'failed',
};

enum RiderLockState {
  /// Rider holds no order.
  free,

  /// `currentOrderId` points at an order that is still in progress.
  blockedByActiveOrder,

  /// `currentOrderId` points at a terminal or missing order.
  stale,
}

class RiderLockDiagnosis {
  const RiderLockDiagnosis({
    required this.riderId,
    required this.riderName,
    required this.state,
    required this.isActive,
    required this.isOnDuty,
    required this.availabilityStatus,
    this.currentOrderId,
    this.currentOrderStatus,
  });

  final String riderId;
  final String riderName;
  final RiderLockState state;
  final bool isActive;
  final bool isOnDuty;
  final String availabilityStatus;
  final String? currentOrderId;
  final String? currentOrderStatus;

  bool get isStale => state == RiderLockState.stale;

  String get description {
    switch (state) {
      case RiderLockState.free:
        return '$riderName holds no order '
            '(on duty: $isOnDuty, status: $availabilityStatus).';
      case RiderLockState.blockedByActiveOrder:
        return '$riderName is busy with active order $currentOrderId '
            '(${currentOrderStatus ?? 'unknown status'}).';
      case RiderLockState.stale:
        return '$riderName is locked by stale order $currentOrderId '
            '(${currentOrderStatus ?? 'order missing'}).';
    }
  }
}

class RiderAssignmentService {
  RiderAssignmentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Reserves the nearest eligible rider inside a transaction so two admins
  /// cannot grab the same order or rider. Rider acceptance remains a separate
  /// action in the Delivery App, so the order stays Pending here.
  Future<RiderCandidate> assignNearestRider({
    required DocumentReference<Map<String, dynamic>> orderRef,
  }) async {
    final storeLocation = await _loadOrderPickupLocation(orderRef);
    final candidates = await _findCandidates(storeLocation);

    if (candidates.isEmpty) {
      throw NoRiderAvailableException();
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        await _assignInTransaction(
          orderRef: orderRef,
          candidate: candidate,
        );
        return candidate;
      } on NoRiderAvailableException catch (error) {
        // Rider was taken by another admin in the meantime; try the next one.
        lastError = error;
      }
    }

    throw lastError is RiderAssignmentException
        ? lastError
        : NoRiderAvailableException();
  }

  /// Inspects a rider and the order its `currentOrderId` points at.
  Future<RiderLockDiagnosis> diagnoseRider(String riderId) async {
    final snapshot = await _firestore
        .collection('delivery_partners')
        .doc(riderId)
        .get();
    final data = snapshot.data();

    if (data == null) {
      throw RiderAssignmentException('Rider $riderId no longer exists.');
    }

    return _diagnose(riderId, data);
  }

  /// Diagnoses every active rider that currently holds an order.
  Future<List<RiderLockDiagnosis>> diagnoseLockedRiders() async {
    final snapshot = await _firestore
        .collection('delivery_partners')
        .where('isActive', isEqualTo: true)
        .get();

    final diagnoses = <RiderLockDiagnosis>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if ((data['currentOrderId']?.toString().trim() ?? '').isEmpty) {
        continue;
      }
      diagnoses.add(await _diagnose(doc.id, data));
    }
    return diagnoses;
  }

  /// Releases a rider whose `currentOrderId` points at a terminal or missing
  /// order. Riders holding a genuinely active order are left untouched.
  Future<RiderLockDiagnosis> repairStaleRiderLock(String riderId) async {
    final riderRef = _firestore.collection('delivery_partners').doc(riderId);

    RiderLockDiagnosis? outcome;
    RiderAssignmentException? blocked;

    await _firestore.runTransaction((transaction) async {
      outcome = null;
      blocked = null;

      final riderSnapshot = await transaction.get(riderRef);
      final riderData = riderSnapshot.data();
      if (riderData == null) {
        blocked = RiderAssignmentException('Rider $riderId no longer exists.');
        return;
      }

      final currentOrderId =
          riderData['currentOrderId']?.toString().trim() ?? '';
      if (currentOrderId.isEmpty) {
        outcome = _buildDiagnosis(
          riderId: riderId,
          riderData: riderData,
          state: RiderLockState.free,
          currentOrderId: null,
          currentOrderStatus: null,
        );
        return;
      }

      final orderSnapshot = await transaction.get(
        _firestore.collection('orders').doc(currentOrderId),
      );
      final orderStatus =
          orderSnapshot.data()?['status']?.toString().trim() ?? '';
      final isTerminal =
          !orderSnapshot.exists ||
          kTerminalOrderStatuses.contains(orderStatus.toLowerCase());

      if (!isTerminal) {
        outcome = _buildDiagnosis(
          riderId: riderId,
          riderData: riderData,
          state: RiderLockState.blockedByActiveOrder,
          currentOrderId: currentOrderId,
          currentOrderStatus: orderStatus,
        );
        return;
      }

      transaction.update(riderRef, <String, dynamic>{
        'currentOrderId': null,
        'currentOrderAssignedAt': FieldValue.delete(),
        'isOnDuty': false,
        'availabilityStatus': 'available',
        'currentOrderReleasedAt': FieldValue.serverTimestamp(),
      });

      outcome = _buildDiagnosis(
        riderId: riderId,
        riderData: riderData,
        state: RiderLockState.stale,
        currentOrderId: currentOrderId,
        currentOrderStatus: orderSnapshot.exists ? orderStatus : null,
      );
    });

    final failure = blocked;
    if (failure != null) {
      throw failure;
    }

    final result = outcome;
    if (result == null) {
      throw RiderAssignmentException('Rider repair did not complete.');
    }
    return result;
  }

  Future<RiderLockDiagnosis> _diagnose(
    String riderId,
    Map<String, dynamic> riderData,
  ) async {
    final currentOrderId = riderData['currentOrderId']?.toString().trim() ?? '';
    if (currentOrderId.isEmpty) {
      return _buildDiagnosis(
        riderId: riderId,
        riderData: riderData,
        state: RiderLockState.free,
        currentOrderId: null,
        currentOrderStatus: null,
      );
    }

    final orderSnapshot = await _firestore
        .collection('orders')
        .doc(currentOrderId)
        .get();
    final orderStatus = orderSnapshot.data()?['status']?.toString().trim() ?? '';
    final isTerminal =
        !orderSnapshot.exists ||
        kTerminalOrderStatuses.contains(orderStatus.toLowerCase());

    return _buildDiagnosis(
      riderId: riderId,
      riderData: riderData,
      state: isTerminal
          ? RiderLockState.stale
          : RiderLockState.blockedByActiveOrder,
      currentOrderId: currentOrderId,
      currentOrderStatus: orderSnapshot.exists ? orderStatus : null,
    );
  }

  static RiderLockDiagnosis _buildDiagnosis({
    required String riderId,
    required Map<String, dynamic> riderData,
    required RiderLockState state,
    required String? currentOrderId,
    required String? currentOrderStatus,
  }) {
    final name = riderData['name']?.toString().trim() ?? '';
    return RiderLockDiagnosis(
      riderId: riderId,
      riderName: name.isEmpty ? 'Delivery Partner' : name,
      state: state,
      isActive: riderData['isActive'] == true,
      isOnDuty: riderData['isOnDuty'] == true,
      availabilityStatus:
          riderData['availabilityStatus']?.toString().trim() ?? 'unknown',
      currentOrderId: currentOrderId,
      currentOrderStatus: currentOrderStatus,
    );
  }

  Future<_StoreLocation> _loadStoreLocation() async {
    final snapshot = await _firestore.collection('settings').doc('app').get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final latitude = (data['hubLatitude'] as num?)?.toDouble();
    final longitude = (data['hubLongitude'] as num?)?.toDouble();

    if (latitude == null || longitude == null) {
      throw RiderAssignmentException(
        'Store location is not set. Configure it in Delivery Settings.',
      );
    }

    return _StoreLocation(latitude, longitude);
  }

  /// New orders retain the selected shop's coordinates as a pickup snapshot.
  /// Use that exact location for dispatch; legacy/global-product orders still
  /// fall back to the configured hub.
  Future<_StoreLocation> _loadOrderPickupLocation(
    DocumentReference<Map<String, dynamic>> orderRef,
  ) async {
    final order = await orderRef.get();
    final data = order.data();
    final latitude = (data?['pickupLatitude'] as num?)?.toDouble();
    final longitude = (data?['pickupLongitude'] as num?)?.toDouble();
    if (latitude != null && longitude != null) {
      return _StoreLocation(latitude, longitude);
    }
    return _loadStoreLocation();
  }

  Future<List<RiderCandidate>> _findCandidates(_StoreLocation store) async {
    final snapshot = await _firestore
        .collection('delivery_partners')
        .where('isActive', isEqualTo: true)
        .where('isOnDuty', isEqualTo: true)
        .where('availabilityStatus', isEqualTo: 'available')
        .get();

    final now = DateTime.now();
    final candidates = <RiderCandidate>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final currentOrderId = data['currentOrderId']?.toString().trim() ?? '';
      if (currentOrderId.isNotEmpty) {
        continue;
      }

      final position = _riderPosition(data);
      if (position == null) {
        continue;
      }

      final updatedAt = _riderLocationUpdatedAt(data);
      if (updatedAt == null ||
          now.difference(updatedAt).abs() > kRiderLocationMaxAge) {
        continue;
      }

      candidates.add(
        RiderCandidate(
          id: doc.id,
          name: data['name']?.toString().trim().isNotEmpty == true
              ? data['name'].toString().trim()
              : 'Delivery Partner',
          distanceKm: _distanceKm(
            store.latitude,
            store.longitude,
            position.latitude,
            position.longitude,
          ),
        ),
      );
    }

    candidates.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return candidates;
  }

  Future<void> _assignInTransaction({
    required DocumentReference<Map<String, dynamic>> orderRef,
    required RiderCandidate candidate,
  }) async {
    final riderRef = _firestore
        .collection('delivery_partners')
        .doc(candidate.id);

    // On web the JS interop boxes exceptions thrown inside the transaction
    // callback, so blocking reasons are collected and rethrown afterwards.
    RiderAssignmentException? blocked;

    await _firestore.runTransaction((transaction) async {
      blocked = null;
      final orderSnapshot = await transaction.get(orderRef);
      final riderSnapshot = await transaction.get(riderRef);

      final orderData = orderSnapshot.data();
      if (!orderSnapshot.exists || orderData == null) {
        blocked = RiderAssignmentException('Order no longer exists.');
        return;
      }

      final status = orderData['status']?.toString().trim().toLowerCase() ?? '';
      if (status != 'pending') {
        blocked = RiderAssignmentException(
          'Order is no longer pending. It may have been updated by another admin.',
        );
        return;
      }

      final alreadyAssigned =
          orderData['assignedPartnerId']?.toString().trim() ?? '';
      if (alreadyAssigned.isNotEmpty) {
        blocked = RiderAssignmentException(
          'Order already has a rider assigned.',
        );
        return;
      }

      final riderData = riderSnapshot.data();
      if (!riderSnapshot.exists || riderData == null) {
        blocked = NoRiderAvailableException('Rider is no longer available.');
        return;
      }

      final riderOrderId = riderData['currentOrderId']?.toString().trim() ?? '';
      final riderStatus =
          riderData['availabilityStatus']?.toString().trim().toLowerCase() ?? '';
      if (riderData['isActive'] != true ||
          riderData['isOnDuty'] != true ||
          riderStatus != 'available' ||
          riderOrderId.isNotEmpty) {
        blocked = NoRiderAvailableException('Rider is no longer available.');
        return;
      }

      transaction.update(orderRef, <String, dynamic>{
        'assignedPartnerId': candidate.id,
        'assignedAt': FieldValue.serverTimestamp(),
        'assignmentType': 'automatic',
      });

      transaction.update(riderRef, <String, dynamic>{
        'availabilityStatus': 'assigned',
        'currentOrderId': orderRef.id,
        'currentOrderAssignedAt': FieldValue.serverTimestamp(),
      });
    });

    final reason = blocked;
    if (reason != null) {
      throw reason;
    }
  }

  static _LatLng? _riderPosition(Map<String, dynamic> data) {
    for (final key in const ['location', 'currentLocation', 'lastLocation']) {
      final value = data[key];
      if (value is GeoPoint) {
        return _LatLng(value.latitude, value.longitude);
      }
      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);
        final latitude = _numField(nested, const ['latitude', 'lat']);
        final longitude = _numField(nested, const [
          'longitude',
          'lng',
          'lon',
        ]);
        if (latitude != null && longitude != null) {
          return _LatLng(latitude, longitude);
        }
      }
    }

    final latitude = _numField(data, const [
      'latitude',
      'currentLatitude',
      'lat',
    ]);
    final longitude = _numField(data, const [
      'longitude',
      'currentLongitude',
      'lng',
      'lon',
    ]);
    if (latitude != null && longitude != null) {
      return _LatLng(latitude, longitude);
    }

    return null;
  }

  static DateTime? _riderLocationUpdatedAt(Map<String, dynamic> data) {
    const keys = [
      'locationUpdatedAt',
      'lastLocationUpdatedAt',
      'lastLocationAt',
      'locationTimestamp',
      'lastSeenAt',
    ];

    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is DateTime) {
        return value;
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    for (final key in const ['location', 'currentLocation', 'lastLocation']) {
      final value = data[key];
      if (value is Map) {
        final nested = Map<String, dynamic>.from(value);
        for (final nestedKey in const ['updatedAt', 'timestamp', 'time']) {
          final nestedValue = nested[nestedKey];
          if (nestedValue is Timestamp) {
            return nestedValue.toDate();
          }
          if (nestedValue is int) {
            return DateTime.fromMillisecondsSinceEpoch(nestedValue);
          }
        }
      }
    }

    return null;
  }

  static double? _numField(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static double _distanceKm(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _radians(endLatitude - startLatitude);
    final longitudeDelta = _radians(endLongitude - startLongitude);

    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(startLatitude)) *
            math.cos(_radians(endLatitude)) *
            math.pow(math.sin(longitudeDelta / 2), 2);

    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

class _StoreLocation {
  const _StoreLocation(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class _LatLng {
  const _LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}
