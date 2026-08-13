import 'dart:math' as math;

class DeliverySettings {
  static const String collectionName = 'settings';
  static const String documentId = 'app';

  final double? hubLatitude;
  final double? hubLongitude;
  final double deliveryRadiusKm;
  final double deliveryCharge;
  final double freeDeliveryMinimum;
  final bool deliveryEnabled;
  final String storeOpenTime;
  final String storeCloseTime;

  const DeliverySettings({
    this.hubLatitude,
    this.hubLongitude,
    this.deliveryRadiusKm = 5,
    this.deliveryCharge = 30,
    this.freeDeliveryMinimum = 299,
    this.deliveryEnabled = false,
    this.storeOpenTime = '07:00',
    this.storeCloseTime = '22:00',
  });

  factory DeliverySettings.fromMap(Map<String, dynamic>? data) {
    final radius = (data?['deliveryRadiusKm'] as num?)?.toDouble();
    final charge = (data?['deliveryCharge'] as num?)?.toDouble();
    final freeMinimum = (data?['freeDeliveryMinimum'] as num?)?.toDouble();
    final openTime = _validTime(data?['storeOpenTime']?.toString());
    final closeTime = _validTime(data?['storeCloseTime']?.toString());

    return DeliverySettings(
      hubLatitude: (data?['hubLatitude'] as num?)?.toDouble(),
      hubLongitude: (data?['hubLongitude'] as num?)?.toDouble(),
      deliveryRadiusKm: radius != null && radius > 0 ? radius : 5,
      deliveryCharge: charge != null && charge >= 0 ? charge : 30,
      freeDeliveryMinimum: freeMinimum != null && freeMinimum >= 0
          ? freeMinimum
          : 299,
      deliveryEnabled: data?['deliveryEnabled'] as bool? ?? false,
      storeOpenTime: openTime ?? '07:00',
      storeCloseTime: closeTime ?? '22:00',
    );
  }

  bool get hasHubLocation => hubLatitude != null && hubLongitude != null;

  double chargeFor(double subtotal) {
    return subtotal >= freeDeliveryMinimum ? 0 : deliveryCharge;
  }

  bool isStoreOpenAt(DateTime dateTime) {
    final open = _minutes(storeOpenTime);
    final close = _minutes(storeCloseTime);
    final current = dateTime.hour * 60 + dateTime.minute;

    if (open == close) return true;
    if (open < close) return current >= open && current < close;
    return current >= open || current < close;
  }

  double distanceFromHubKm(double latitude, double longitude) {
    if (!hasHubLocation) return double.infinity;

    const earthRadiusKm = 6371.0;
    final latitudeDelta = _radians(latitude - hubLatitude!);
    final longitudeDelta = _radians(longitude - hubLongitude!);
    final startLatitude = _radians(hubLatitude!);
    final endLatitude = _radians(latitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(startLatitude) *
            math.cos(endLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);

    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  bool containsLocation(double latitude, double longitude) {
    return distanceFromHubKm(latitude, longitude) <= deliveryRadiusKm;
  }

  String get formattedOpeningTime => _formatTime(storeOpenTime);

  static int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String? _validTime(String? value) {
    if (value == null || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return null;
    }
    return value;
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static String _formatTime(String value) {
    final parts = value.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}
