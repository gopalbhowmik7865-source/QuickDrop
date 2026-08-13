import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_settings.dart';

class DeliverySettingsService {
  DeliverySettingsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _document => _firestore
      .collection(DeliverySettings.collectionName)
      .doc(DeliverySettings.documentId);

  Stream<DeliverySettings> watch() {
    return _document
        .snapshots()
        .map((snapshot) => DeliverySettings.fromMap(snapshot.data()))
        .asBroadcastStream();
  }

  Future<DeliverySettings> getLatest() async {
    final snapshot = await _document.get().timeout(const Duration(seconds: 10));
    return DeliverySettings.fromMap(snapshot.data());
  }
}
