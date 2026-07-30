import 'package:flutter_test/flutter_test.dart';
import 'package:quickdrop/main.dart';

void main() {
  group('product image extraction', () {
    test('extracts image URLs from nested maps and common field names', () {
      final data = <String, dynamic>{
        'name': 'Tea',
        'image': {
          'downloadURL': 'https://firebasestorage.googleapis.com/v0/b/example/o/tea.jpg?alt=media',
        },
      };

      expect(extractProductImageUrl(data),
          'https://firebasestorage.googleapis.com/v0/b/example/o/tea.jpg?alt=media');
    });

    test('converts Firebase Storage gs paths into a valid download URL', () {
      final data = <String, dynamic>{
        'name': 'Coffee',
        'imageUrl': 'gs://quickdrop-cbf49.appspot.com/product_images/coffee.png',
      };

      expect(
        extractProductImageUrl(data),
        'https://firebasestorage.googleapis.com/v0/b/quickdrop-cbf49.appspot.com/o/product_images%2Fcoffee.png?alt=media',
      );
    });
  });
}
