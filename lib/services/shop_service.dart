import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/shop.dart';

class ShopService {
  ShopService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _shopsRef =>
      _firestore.collection('shops');

  Stream<List<Shop>> watchActiveShops() {
    return _shopsRef
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Shop.fromDocument)
              .where((shop) => shop.isActive)
              .toList(),
        );
  }

  Stream<Shop?> watchShop(String shopId) {
    return _shopsRef.doc(shopId).snapshots().map((document) {
      if (!document.exists) return null;
      final shop = Shop.fromDocument(document);
      return shop.isActive ? shop : null;
    });
  }

  Stream<List<ShopInventoryItem>> watchShopInventory(String shopId) {
    return _shopsRef
        .doc(shopId)
        .collection('inventory')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ShopInventoryItem.fromDocument)
              .where((item) => item.isOrderable)
              .toList(),
        );
  }

  Future<Map<String, dynamic>?> getProduct(String productId) async {
    final document = await _firestore
        .collection('products')
        .doc(productId)
        .get();
    return document.data();
  }
}
