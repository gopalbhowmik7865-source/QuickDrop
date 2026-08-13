import 'package:flutter_test/flutter_test.dart';
import 'package:quickdrop/models/delivery_settings.dart';

void main() {
  group('DeliverySettings', () {
    test('uses safe defaults for missing or invalid values', () {
      final settings = DeliverySettings.fromMap({
        'deliveryRadiusKm': -1,
        'deliveryCharge': -5,
        'freeDeliveryMinimum': -10,
        'storeOpenTime': 'invalid',
        'storeCloseTime': '25:00',
      });

      expect(settings.deliveryRadiusKm, 5);
      expect(settings.deliveryCharge, 30);
      expect(settings.freeDeliveryMinimum, 299);
      expect(settings.storeOpenTime, '07:00');
      expect(settings.storeCloseTime, '22:00');
      expect(settings.hasHubLocation, isFalse);
    });

    test('applies configured charge below the free delivery minimum', () {
      const settings = DeliverySettings(
        deliveryCharge: 30,
        freeDeliveryMinimum: 299,
      );

      expect(settings.chargeFor(298), 30);
      expect(settings.chargeFor(299), 0);
      expect(settings.chargeFor(500), 0);
    });

    test('calculates open and closed status from configured times', () {
      const settings = DeliverySettings(
        storeOpenTime: '07:00',
        storeCloseTime: '22:00',
      );

      expect(settings.isStoreOpenAt(DateTime(2026, 8, 8, 7)), isTrue);
      expect(settings.isStoreOpenAt(DateTime(2026, 8, 8, 21, 59)), isTrue);
      expect(settings.isStoreOpenAt(DateTime(2026, 8, 8, 22)), isFalse);
      expect(settings.formattedOpeningTime, '7:00 AM');
    });

    test('supports store hours that cross midnight', () {
      const settings = DeliverySettings(
        storeOpenTime: '22:00',
        storeCloseTime: '07:00',
      );

      expect(settings.isStoreOpenAt(DateTime(2026, 8, 8, 23)), isTrue);
      expect(settings.isStoreOpenAt(DateTime(2026, 8, 9, 6, 59)), isTrue);
      expect(settings.isStoreOpenAt(DateTime(2026, 8, 9, 12)), isFalse);
    });

    test('validates actual distance from the configured hub', () {
      const settings = DeliverySettings(
        hubLatitude: 23.8315,
        hubLongitude: 91.2868,
        deliveryRadiusKm: 5,
      );

      expect(settings.containsLocation(23.8515, 91.2868), isTrue);
      expect(settings.containsLocation(23.9315, 91.2868), isFalse);
    });
  });
}
