import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.area,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.isActive,
    required this.imageUrl,
    this.extraFields = const <String, dynamic>{},
  });

  factory Shop.fromDocument(DocumentSnapshot<Map<String, dynamic>> document) {
    return Shop.fromMap(document.id, document.data() ?? const {});
  }

  factory Shop.fromMap(String id, Map<String, dynamic> data) {
    return Shop(
      id: id,
      name: data['name']?.toString().trim() ?? '',
      address: data['address']?.toString().trim() ?? '',
      area: data['area']?.toString().trim() ?? '',
      phone: data['phone']?.toString().trim() ?? '',
      latitude: _doubleValue(data['latitude']),
      longitude: _doubleValue(data['longitude']),
      isActive: data['isActive'] as bool? ?? false,
      imageUrl: data['imageUrl']?.toString().trim() ?? '',
      extraFields: Map<String, dynamic>.unmodifiable(data),
    );
  }

  final String id;
  final String name;
  final String address;
  final String area;
  final String phone;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final String imageUrl;
  final Map<String, dynamic> extraFields;

  String get displayAddress {
    if (area.isEmpty) return address;
    if (address.isEmpty) return area;
    if (address.toLowerCase().contains(area.toLowerCase())) return address;
    return '$area, $address';
  }

  double? distanceFrom(double latitude, double longitude) {
    if (this.latitude == null || this.longitude == null) return null;
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _radians(this.latitude! - latitude);
    final longitudeDelta = _radians(this.longitude! - longitude);
    final startLatitude = _radians(latitude);
    final endLatitude = _radians(this.latitude!);
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

  static double _radians(double degrees) => degrees * math.pi / 180;

  static double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '');
  }
}

class ShopInventoryItem {
  const ShopInventoryItem({
    required this.productId,
    required this.available,
    required this.stock,
    required this.fields,
  });

  factory ShopInventoryItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ShopInventoryItem(
      productId: data['productId']?.toString().trim().isNotEmpty == true
          ? data['productId'].toString().trim()
          : document.id,
      available: data['available'] as bool? ?? false,
      stock: _stockValue(data['stock']),
      fields: Map<String, dynamic>.unmodifiable(data),
    );
  }

  final String productId;
  final bool available;
  final int stock;
  final Map<String, dynamic> fields;

  bool get isOrderable => available && stock > 0;

  static int _stockValue(dynamic value) {
    if (value is num) return value.toInt().clamp(0, 9999999);
    return int.tryParse(value?.toString().trim() ?? '')?.clamp(0, 9999999) ?? 0;
  }
}
