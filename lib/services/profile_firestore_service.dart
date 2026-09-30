import 'dart:developer' as developer;
import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../auth_service.dart';
import '../models/profile_models.dart';

class ProfileFirestoreService {
  ProfileFirestoreService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    AuthService? authService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _authService = authService ?? AuthService();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final AuthService _authService;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _addressesCollection =>
      _firestore.collection('addresses');

  CollectionReference<Map<String, dynamic>> get _wishlistCollection =>
      _firestore.collection('wishlist');

  CollectionReference<Map<String, dynamic>> get _paymentMethodsCollection =>
      _firestore.collection('payment_methods');

  CollectionReference<Map<String, dynamic>>
  get _notificationSettingsCollection =>
      _firestore.collection('notification_settings');

  static const NotificationSettingsModel _defaultNotificationSettings =
      NotificationSettingsModel(
        orderUpdates: true,
        promotions: false,
        systemAlerts: true,
        updatedAt: null,
      );

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'QuickDropProfile',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Stream<T> _broadcast<T>(Stream<T> stream) {
    return stream.asBroadcastStream();
  }

  DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  Future<_ProfileIdentity> _resolveIdentity() async {
    final authUser = _auth.currentUser;
    final localProfile = await _authService.loadCurrentUserProfile();

    final localName = (localProfile?['name'] ?? '').toString().trim();
    final localPhone =
        (localProfile?['phoneNumber'] ?? localProfile?['phone'] ?? '')
            .toString()
            .trim();

    final fallbackUid = localPhone.isNotEmpty
        ? 'guest_${localPhone.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}'
        : 'guest_local_profile';

    return _ProfileIdentity(
      uid: authUser?.uid ?? fallbackUid,
      name: authUser?.displayName?.trim().isNotEmpty == true
          ? authUser!.displayName!.trim()
          : localName,
      phoneNumber: authUser?.phoneNumber?.trim().isNotEmpty == true
          ? authUser!.phoneNumber!.trim()
          : localPhone,
      photoUrl: (authUser?.photoURL ?? '').trim(),
      email: (authUser?.email ?? '').trim(),
      isAuthenticated: authUser != null,
    );
  }

  UserProfileModel _fallbackProfile(_ProfileIdentity identity) {
    return UserProfileModel(
      userId: identity.uid,
      name: identity.name,
      phoneNumber: identity.phoneNumber,
      email: identity.email,
      photoUrl: identity.photoUrl,
      createdAt: null,
      updatedAt: null,
    );
  }

  UserProfileModel _mergeProfile(
    UserProfileModel fallback,
    Map<String, dynamic>? data,
  ) {
    final firestoreProfile = UserProfileModel.fromFirestore(
      fallback.userId,
      data,
    );
    return UserProfileModel(
      userId: fallback.userId,
      name: firestoreProfile.name.isNotEmpty
          ? firestoreProfile.name
          : fallback.name,
      phoneNumber: firestoreProfile.phoneNumber.isNotEmpty
          ? firestoreProfile.phoneNumber
          : fallback.phoneNumber,
      email: firestoreProfile.email.isNotEmpty
          ? firestoreProfile.email
          : fallback.email,
      photoUrl: firestoreProfile.photoUrl.isNotEmpty
          ? firestoreProfile.photoUrl
          : fallback.photoUrl,
      createdAt: firestoreProfile.createdAt,
      updatedAt: firestoreProfile.updatedAt,
    );
  }

  Future<void> bootstrapUserProfile() async {
    final identity = await _resolveIdentity();

    try {
      await _usersCollection.doc(identity.uid).set({
        'uid': identity.uid,
        'name': identity.name,
        'phoneNumber': identity.phoneNumber,
        'photoUrl': identity.photoUrl,
        'email': identity.email,
        'authType': identity.isAuthenticated ? 'firebase_auth' : 'guest',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _notificationSettingsCollection.doc(identity.uid).set({
        'ownerId': identity.uid,
        'orderUpdates': true,
        'promotions': false,
        'systemAlerts': true,
        'fcmReady': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      _log(
        'bootstrapUserProfile: Firestore bootstrap skipped.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Stream<UserProfileModel> userProfileStream() {
    return _broadcast(
      (() async* {
        final identity = await _resolveIdentity();
        final fallback = _fallbackProfile(identity);
        yield fallback;

        try {
          await for (final snapshot
              in _usersCollection.doc(identity.uid).snapshots()) {
            yield _mergeProfile(fallback, snapshot.data());
          }
        } catch (error, stackTrace) {
          _log(
            'userProfileStream: returning fallback profile due to stream error.',
            error: error,
            stackTrace: stackTrace,
          );
          yield fallback;
        }
      })(),
    );
  }

  Future<void> updateUserProfile({
    required String name,
    required String phoneNumber,
  }) async {
    final identity = await _resolveIdentity();
    await _usersCollection.doc(identity.uid).set({
      'name': name,
      'phoneNumber': phoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> uploadProfilePhoto(String filePath) async {
    final identity = await _resolveIdentity();
    final ext = filePath.split('.').last.toLowerCase();
    final path =
        'user_profiles/${identity.uid}/avatar/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';

    final ref = _storage.ref().child(path);
    final snapshot = await ref.putFile(File(filePath));
    final url = await snapshot.ref.getDownloadURL();

    await _usersCollection.doc(identity.uid).set({
      'photoUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return url;
  }

  Stream<List<AddressModel>> addressStream() {
    return _broadcast(
      (() async* {
        final identity = await _resolveIdentity();
        yield const <AddressModel>[];

        try {
          await for (final snapshot
              in _addressesCollection
                  .where('ownerId', isEqualTo: identity.uid)
                  .snapshots()) {
            final addresses =
                snapshot.docs
                    .map(
                      (doc) => AddressModel.fromFirestore(doc.id, doc.data()),
                    )
                    .toList()
                  ..sort((a, b) {
                    final aTime = a.updatedAt ?? a.createdAt;
                    final bTime = b.updatedAt ?? b.createdAt;
                    if (aTime == null && bTime == null) {
                      return 0;
                    }
                    if (aTime == null) {
                      return 1;
                    }
                    if (bTime == null) {
                      return -1;
                    }
                    return bTime.compareTo(aTime);
                  });

            yield addresses;
          }
        } catch (error, stackTrace) {
          _log('addressStream failed.', error: error, stackTrace: stackTrace);
          yield const <AddressModel>[];
        }
      })(),
    );
  }

  Future<void> addAddress({
    required String label,
    required String recipientName,
    required String phoneNumber,
    required String line1,
    required String line2,
    required String city,
    required String state,
    required String pincode,
    required String landmark,
    required bool isDefault,
  }) async {
    final identity = await _resolveIdentity();
    final batch = _firestore.batch();

    if (isDefault) {
      final current = await _addressesCollection
          .where('ownerId', isEqualTo: identity.uid)
          .get();
      for (final doc in current.docs) {
        batch.update(doc.reference, {'isDefault': false});
      }
    }

    final docRef = _addressesCollection.doc();
    batch.set(docRef, {
      'ownerId': identity.uid,
      'ownerPhone': identity.phoneNumber,
      'label': label,
      'recipientName': recipientName,
      'phoneNumber': phoneNumber,
      'line1': line1,
      'line2': line2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'landmark': landmark,
      'isDefault': isDefault,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> updateAddress(
    String addressId, {
    required String label,
    required String recipientName,
    required String phoneNumber,
    required String line1,
    required String line2,
    required String city,
    required String state,
    required String pincode,
    required String landmark,
    required bool isDefault,
  }) async {
    final identity = await _resolveIdentity();
    final batch = _firestore.batch();

    if (isDefault) {
      final current = await _addressesCollection
          .where('ownerId', isEqualTo: identity.uid)
          .get();
      for (final doc in current.docs) {
        if (doc.id != addressId) {
          batch.update(doc.reference, {'isDefault': false});
        }
      }
    }

    final docRef = _addressesCollection.doc(addressId);
    batch.set(docRef, {
      'ownerId': identity.uid,
      'ownerPhone': identity.phoneNumber,
      'label': label,
      'recipientName': recipientName,
      'phoneNumber': phoneNumber,
      'line1': line1,
      'line2': line2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'landmark': landmark,
      'isDefault': isDefault,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> deleteAddress(String addressId) {
    return _addressesCollection.doc(addressId).delete();
  }

  Stream<List<WishlistItemModel>> wishlistStream() {
    return _broadcast(
      (() async* {
        final identity = await _resolveIdentity();
        yield const <WishlistItemModel>[];

        try {
          await for (final snapshot
              in _wishlistCollection
                  .where('ownerId', isEqualTo: identity.uid)
                  .snapshots()) {
            final items =
                snapshot.docs
                    .map(
                      (doc) =>
                          WishlistItemModel.fromFirestore(doc.id, doc.data()),
                    )
                    .toList()
                  ..sort((a, b) {
                    if (a.addedAt == null && b.addedAt == null) {
                      return 0;
                    }
                    if (a.addedAt == null) {
                      return 1;
                    }
                    if (b.addedAt == null) {
                      return -1;
                    }
                    return b.addedAt!.compareTo(a.addedAt!);
                  });
            yield items;
          }
        } catch (error, stackTrace) {
          _log('wishlistStream failed.', error: error, stackTrace: stackTrace);
          yield const <WishlistItemModel>[];
        }
      })(),
    );
  }

  Future<void> addToWishlist(String productId) async {
    final identity = await _resolveIdentity();
    final docId = '${identity.uid}_$productId';
    await _wishlistCollection.doc(docId).set({
      'ownerId': identity.uid,
      'productId': productId,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFromWishlist(String productId) async {
    final identity = await _resolveIdentity();
    final docId = '${identity.uid}_$productId';
    await _wishlistCollection.doc(docId).delete();
  }

  Future<Map<String, dynamic>?> getProduct(String productId) async {
    final snapshot = await _firestore
        .collection('products')
        .doc(productId)
        .get();
    return snapshot.data();
  }

  Stream<List<PaymentMethodModel>> paymentMethodStream() {
    return _broadcast(
      (() async* {
        final identity = await _resolveIdentity();
        yield const <PaymentMethodModel>[];

        try {
          await for (final snapshot
              in _paymentMethodsCollection
                  .where('ownerId', isEqualTo: identity.uid)
                  .snapshots()) {
            final methods =
                snapshot.docs
                    .map(
                      (doc) =>
                          PaymentMethodModel.fromFirestore(doc.id, doc.data()),
                    )
                    .toList()
                  ..sort((a, b) {
                    if (a.updatedAt == null && b.updatedAt == null) {
                      return 0;
                    }
                    if (a.updatedAt == null) {
                      return 1;
                    }
                    if (b.updatedAt == null) {
                      return -1;
                    }
                    return b.updatedAt!.compareTo(a.updatedAt!);
                  });

            yield methods;
          }
        } catch (error, stackTrace) {
          _log(
            'paymentMethodStream failed.',
            error: error,
            stackTrace: stackTrace,
          );
          yield const <PaymentMethodModel>[];
        }
      })(),
    );
  }

  Future<void> savePaymentMethod({
    required String type,
    required String provider,
    required String reference,
    required bool isDefault,
    String status = 'active',
    String source = 'profile',
  }) async {
    final identity = await _resolveIdentity();
    final normalizedProvider = provider.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    final normalizedRef = reference.hashCode.abs();
    final docId =
        '${identity.uid}_${type.toLowerCase()}_${normalizedProvider}_$normalizedRef';
    final batch = _firestore.batch();

    if (isDefault) {
      final current = await _paymentMethodsCollection
          .where('ownerId', isEqualTo: identity.uid)
          .get();
      for (final doc in current.docs) {
        batch.update(doc.reference, {'isDefault': false});
      }
    }

    batch.set(_paymentMethodsCollection.doc(docId), {
      'ownerId': identity.uid,
      'type': type,
      'provider': provider,
      'reference': reference,
      'status': status,
      'source': source,
      'isDefault': isDefault,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> removePaymentMethod(String paymentMethodId) {
    return _paymentMethodsCollection.doc(paymentMethodId).delete();
  }

  Stream<List<PaymentMethodModel>> recentPaymentMethodsFromOrders() {
    return _broadcast(
      (() async* {
        final ownerUid = _auth.currentUser?.uid ?? '';
        if (ownerUid.isEmpty) {
          yield const <PaymentMethodModel>[];
          return;
        }

        try {
          await for (final snapshot
              in _firestore
                  .collection('orders')
                  .where('ownerUid', isEqualTo: ownerUid)
                  .snapshots()) {
            final methods = <PaymentMethodModel>[];
            final seen = <String>{};

            final docs = [...snapshot.docs]
              ..sort((a, b) {
                final aDate = _timestampToDateTime(a.data()['createdAt']);
                final bDate = _timestampToDateTime(b.data()['createdAt']);
                if (aDate == null && bDate == null) {
                  return 0;
                }
                if (aDate == null) {
                  return 1;
                }
                if (bDate == null) {
                  return -1;
                }
                return bDate.compareTo(aDate);
              });

            for (final doc in docs.take(20)) {
              final data = doc.data();
              final method = (data['paymentMethod'] ?? '').toString().trim();
              if (method.isEmpty) {
                continue;
              }

              final paymentId = (data['paymentId'] ?? '').toString().trim();
              final key = '$method:$paymentId';
              if (!seen.add(key)) {
                continue;
              }

              methods.add(
                PaymentMethodModel(
                  id: doc.id,
                  type: 'order',
                  provider: method,
                  reference: paymentId,
                  status: (data['paymentStatus'] ?? '').toString().trim(),
                  isDefault: false,
                  updatedAt: _timestampToDateTime(data['createdAt']),
                  source: 'orders',
                ),
              );
            }

            yield methods;
          }
        } catch (error, stackTrace) {
          _log(
            'recentPaymentMethodsFromOrders failed.',
            error: error,
            stackTrace: stackTrace,
          );
          yield const <PaymentMethodModel>[];
        }
      })(),
    );
  }

  Stream<List<CouponModel>> activeCouponsStream() {
    return _broadcast(
      _firestore
          .collection('coupons')
          .snapshots()
          .map((snapshot) {
            final now = DateTime.now();
            return snapshot.docs
                .map((doc) => CouponModel.fromFirestore(doc.id, doc.data()))
                .where((coupon) {
                  final notExpired =
                      coupon.expiresAt == null ||
                      coupon.expiresAt!.isAfter(now);
                  return coupon.isActive && notExpired;
                })
                .toList();
          })
          .handleError((Object error, StackTrace stackTrace) {
            _log(
              'activeCouponsStream failed.',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  Stream<NotificationSettingsModel> notificationSettingsStream() {
    return _broadcast(
      (() async* {
        final identity = await _resolveIdentity();
        const fallback = NotificationSettingsModel(
          orderUpdates: true,
          promotions: false,
          systemAlerts: true,
          updatedAt: null,
        );
        yield fallback;

        try {
          await for (final snapshot
              in _notificationSettingsCollection
                  .doc(identity.uid)
                  .snapshots()) {
            yield NotificationSettingsModel.fromFirestore(snapshot.data());
          }
        } catch (error, stackTrace) {
          _log(
            'notificationSettingsStream failed.',
            error: error,
            stackTrace: stackTrace,
          );
          yield fallback;
        }
      })(),
    );
  }

  Future<NotificationSettingsModel> getOrCreateNotificationSettings({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final identity = await _resolveIdentity();
    final docRef = _notificationSettingsCollection.doc(identity.uid);

    try {
      final snapshot = await docRef.get().timeout(timeout);
      if (!snapshot.exists) {
        await docRef
            .set({
              'ownerId': identity.uid,
              'orderUpdates': true,
              'promotions': false,
              'systemAlerts': true,
              'fcmReady': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(timeout);
        return _defaultNotificationSettings;
      }

      return NotificationSettingsModel.fromFirestore(snapshot.data());
    } on FirebaseException catch (error, stackTrace) {
      _log(
        'getOrCreateNotificationSettings failed for notification_settings/${identity.uid}.',
        error: error,
        stackTrace: stackTrace,
      );
      return _defaultNotificationSettings;
    } on TimeoutException catch (error, stackTrace) {
      _log(
        'getOrCreateNotificationSettings timed out for notification_settings/${identity.uid}.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      _log(
        'getOrCreateNotificationSettings failed unexpectedly for notification_settings/${identity.uid}.',
        error: error,
        stackTrace: stackTrace,
      );
      return _defaultNotificationSettings;
    }
  }

  Future<void> saveNotificationSettings({
    required bool orderUpdates,
    required bool promotions,
    required bool systemAlerts,
  }) async {
    final identity = await _resolveIdentity();
    try {
      await _notificationSettingsCollection.doc(identity.uid).set({
        'ownerId': identity.uid,
        'orderUpdates': orderUpdates,
        'promotions': promotions,
        'systemAlerts': systemAlerts,
        'fcmReady': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error, stackTrace) {
      _log(
        'saveNotificationSettings failed for notification_settings/${identity.uid}.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      _log(
        'saveNotificationSettings failed unexpectedly for notification_settings/${identity.uid}.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Stream<SupportInfoModel?> supportInfoStream() {
    return _broadcast(
      _firestore
          .collection('app_support')
          .doc('customer_support')
          .snapshots()
          .map((doc) {
            if (!doc.exists) {
              return null;
            }
            return SupportInfoModel.fromFirestore(doc.data());
          })
          .handleError((Object error, StackTrace stackTrace) {
            _log(
              'supportInfoStream failed.',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  Stream<Map<String, dynamic>?> appContentStream(String docId) {
    return _broadcast(
      _firestore
          .collection('app_content')
          .doc(docId)
          .snapshots()
          .map((doc) => doc.data())
          .handleError((Object error, StackTrace stackTrace) {
            _log(
              'appContentStream($docId) failed.',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }
}

class _ProfileIdentity {
  const _ProfileIdentity({
    required this.uid,
    required this.name,
    required this.phoneNumber,
    required this.photoUrl,
    required this.email,
    required this.isAuthenticated,
  });

  final String uid;
  final String name;
  final String phoneNumber;
  final String photoUrl;
  final String email;
  final bool isAuthenticated;
}
