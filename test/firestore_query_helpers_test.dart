import 'package:flutter_test/flutter_test.dart';
import 'package:quickdrop/firestore_query_helpers.dart';

void main() {
  group('firestore query compatibility helpers', () {
    test('matches orders across common phone fields', () {
      expect(
        orderMatchesSessionPhone(
          {'ownerPhone': '+919999999999'},
          '+919999999999',
        ),
        isTrue,
      );

      expect(
        orderMatchesSessionPhone(
          {'phoneNumber': '+919999999999'},
          '+919999999999',
        ),
        isTrue,
      );

      expect(
        orderMatchesSessionPhone(
          {'phone': '9999999999'},
          '9999999999',
        ),
        isTrue,
      );

      expect(
        orderMatchesSessionPhone(
          {'customerPhone': '+919999999999'},
          '+919999999999',
        ),
        isTrue,
      );

      expect(
        orderMatchesSessionPhone(
          {'ownerPhone': '+919888888888'},
          '+919999999999',
        ),
        isFalse,
      );
    });

    test('legacy ownership accepts only the ownerPhone field', () {
      expect(
        orderMatchesVerifiedOwnerPhone(
          {'ownerPhone': '9999999999'},
          '+919999999999',
        ),
        isTrue,
      );

      expect(
        orderMatchesVerifiedOwnerPhone(
          {'phoneNumber': '+919999999999'},
          '+919999999999',
        ),
        isFalse,
      );

      expect(
        orderMatchesVerifiedOwnerPhone(
          {'ownerPhone': '+919888888888'},
          '+919999999999',
        ),
        isFalse,
      );
    });

    test('falls back to showing products when category filters produce no matches', () {
      final docs = [
        {'name': 'Milk', 'category': 'Grocery'},
        {'name': 'Burger', 'category': 'Food'},
      ];

      expect(
        shouldUseFallbackProducts(
          docs,
          firestoreCategory: 'Vegetables',
        ),
        isTrue,
      );

      expect(
        shouldUseFallbackProducts(
          [
            {'name': 'Milk', 'category': 'Vegetables'},
          ],
          firestoreCategory: 'Vegetables',
        ),
        isFalse,
      );
    });
  });
}
