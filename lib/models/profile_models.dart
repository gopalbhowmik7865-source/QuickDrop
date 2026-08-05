import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _asDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  return null;
}

class UserProfileModel {
  const UserProfileModel({
    required this.userId,
    required this.name,
    required this.phoneNumber,
    required this.email,
    required this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String name;
  final String phoneNumber;
  final String email;
  final String photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UserProfileModel.fromFirestore(String userId, Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return UserProfileModel(
      userId: userId,
      name: (raw['name'] ?? '').toString().trim(),
      phoneNumber: (raw['phoneNumber'] ?? '').toString().trim(),
      email: (raw['email'] ?? '').toString().trim(),
      photoUrl: (raw['photoUrl'] ?? '').toString().trim(),
      createdAt: _asDateTime(raw['createdAt']),
      updatedAt: _asDateTime(raw['updatedAt']),
    );
  }
}

class AddressModel {
  const AddressModel({
    required this.id,
    required this.label,
    required this.recipientName,
    required this.phoneNumber,
    required this.line1,
    required this.line2,
    required this.city,
    required this.state,
    required this.pincode,
    required this.landmark,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String label;
  final String recipientName;
  final String phoneNumber;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String landmark;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AddressModel.fromFirestore(String id, Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return AddressModel(
      id: id,
      label: (raw['label'] ?? '').toString().trim(),
      recipientName: (raw['recipientName'] ?? '').toString().trim(),
      phoneNumber: (raw['phoneNumber'] ?? '').toString().trim(),
      line1: (raw['line1'] ?? '').toString().trim(),
      line2: (raw['line2'] ?? '').toString().trim(),
      city: (raw['city'] ?? '').toString().trim(),
      state: (raw['state'] ?? '').toString().trim(),
      pincode: (raw['pincode'] ?? '').toString().trim(),
      landmark: (raw['landmark'] ?? '').toString().trim(),
      isDefault: raw['isDefault'] == true,
      createdAt: _asDateTime(raw['createdAt']),
      updatedAt: _asDateTime(raw['updatedAt']),
    );
  }

  String get fullAddress {
    final parts = [line1, line2, landmark, city, state, pincode]
        .where((value) => value.isNotEmpty)
        .toList();
    return parts.join(', ');
  }
}

class WishlistItemModel {
  const WishlistItemModel({
    required this.id,
    required this.productId,
    required this.addedAt,
  });

  final String id;
  final String productId;
  final DateTime? addedAt;

  factory WishlistItemModel.fromFirestore(String id, Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return WishlistItemModel(
      id: id,
      productId: (raw['productId'] ?? '').toString().trim(),
      addedAt: _asDateTime(raw['addedAt']),
    );
  }
}

class PaymentMethodModel {
  const PaymentMethodModel({
    required this.id,
    required this.type,
    required this.provider,
    required this.reference,
    required this.status,
    required this.isDefault,
    required this.updatedAt,
    required this.source,
  });

  final String id;
  final String type;
  final String provider;
  final String reference;
  final String status;
  final bool isDefault;
  final DateTime? updatedAt;
  final String source;

  factory PaymentMethodModel.fromFirestore(String id, Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return PaymentMethodModel(
      id: id,
      type: (raw['type'] ?? '').toString().trim(),
      provider: (raw['provider'] ?? '').toString().trim(),
      reference: (raw['reference'] ?? '').toString().trim(),
      status: (raw['status'] ?? '').toString().trim(),
      isDefault: raw['isDefault'] == true,
      updatedAt: _asDateTime(raw['updatedAt']),
      source: (raw['source'] ?? '').toString().trim(),
    );
  }
}

class CouponModel {
  const CouponModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.maxDiscount,
    required this.isActive,
    required this.expiresAt,
  });

  final String id;
  final String code;
  final String title;
  final String description;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final double maxDiscount;
  final bool isActive;
  final DateTime? expiresAt;

  factory CouponModel.fromFirestore(String id, Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    final discountValue = raw['discountValue'];
    final minOrderAmount = raw['minOrderAmount'];
    final maxDiscount = raw['maxDiscount'];

    return CouponModel(
      id: id,
      code: (raw['code'] ?? '').toString().trim(),
      title: (raw['title'] ?? '').toString().trim(),
      description: (raw['description'] ?? '').toString().trim(),
      discountType: (raw['discountType'] ?? '').toString().trim(),
      discountValue: discountValue is num
          ? discountValue.toDouble()
          : double.tryParse(discountValue?.toString() ?? '') ?? 0,
      minOrderAmount: minOrderAmount is num
          ? minOrderAmount.toDouble()
          : double.tryParse(minOrderAmount?.toString() ?? '') ?? 0,
      maxDiscount: maxDiscount is num
          ? maxDiscount.toDouble()
          : double.tryParse(maxDiscount?.toString() ?? '') ?? 0,
      isActive: raw['isActive'] == true,
      expiresAt: _asDateTime(raw['expiresAt']),
    );
  }
}

class NotificationSettingsModel {
  const NotificationSettingsModel({
    required this.orderUpdates,
    required this.promotions,
    required this.systemAlerts,
    required this.updatedAt,
  });

  final bool orderUpdates;
  final bool promotions;
  final bool systemAlerts;
  final DateTime? updatedAt;

  factory NotificationSettingsModel.fromFirestore(Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return NotificationSettingsModel(
      orderUpdates: raw['orderUpdates'] != false,
      promotions: raw['promotions'] == true,
      systemAlerts: raw['systemAlerts'] != false,
      updatedAt: _asDateTime(raw['updatedAt']),
    );
  }
}

class SupportInfoModel {
  const SupportInfoModel({
    required this.whatsapp,
    required this.phone,
    required this.email,
    required this.message,
  });

  final String whatsapp;
  final String phone;
  final String email;
  final String message;

  factory SupportInfoModel.fromFirestore(Map<String, dynamic>? data) {
    final raw = data ?? <String, dynamic>{};
    return SupportInfoModel(
      whatsapp: (raw['whatsapp'] ?? '').toString().trim(),
      phone: (raw['phone'] ?? '').toString().trim(),
      email: (raw['email'] ?? '').toString().trim(),
      message: (raw['message'] ?? '').toString().trim(),
    );
  }
}