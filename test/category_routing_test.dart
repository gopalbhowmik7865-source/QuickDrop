import 'package:flutter_test/flutter_test.dart';
import 'package:quickdrop/category_routing.dart';

void main() {
  group('category routing helpers', () {
    test('matches grocery products by category and subcategory', () {
      final data = {
        'category': 'Grocery',
        'subcategory': 'Atta, Rice & Dal',
      };

      expect(
        matchesCategoryAndSubcategory(
          data,
          firestoreCategory: 'Grocery',
          selectedSubcategory: 'Atta, Rice & Dal',
        ),
        isTrue,
      );
    });

    test('returns subcategory options for the requested category', () {
      expect(
        buildSubcategoryOptions('Beauty & Personal Care'),
        containsAll([
          'Bath & Body',
          'Hair Care',
          'Skin Care',
          'Cosmetics',
          'Baby Care',
          'Health',
        ]),
      );
    });

    test('returns child category options for dairy subcategory', () {
      expect(
        buildChildCategoryOptions('Dairy & Eggs'),
        contains('Milk'),
      );
    });

    test('builds distinct subcategory tabs from Firestore product data', () {
      final products = [
        {'category': 'Gifts', 'subcategory': 'Birthday'},
        {'category': 'Gifts', 'subcategory': 'Flowers'},
        {'category': 'Gifts', 'subcategory': 'Birthday'},
        {'category': 'Gifts', 'subcategory': 'Anniversary'},
      ];

      expect(
        buildSubcategoriesForCategory(products, firestoreCategory: 'Gifts'),
        ['Birthday', 'Flowers', 'Anniversary'],
      );
    });

    test('filters products by subcategory using the Firestore value', () {
      final birthdayData = {
        'category': 'Gifts',
        'subcategory': 'Birthday',
      };
      final flowersData = {
        'category': 'Gifts',
        'subcategory': 'Flowers',
      };

      expect(
        matchesCategoryAndSubcategory(
          birthdayData,
          firestoreCategory: 'Gifts',
          selectedSubcategory: 'Birthday',
        ),
        isTrue,
      );
      expect(
        matchesCategoryAndSubcategory(
          flowersData,
          firestoreCategory: 'Gifts',
          selectedSubcategory: 'Birthday',
        ),
        isFalse,
      );
    });

    test('matches grocery products by child category', () {
      final data = {
        'category': 'Grocery',
        'subcategory': 'Dairy, Bread & Eggs',
        'childCategory': 'Milk',
      };

      expect(
        matchesCategoryAndSubcategory(
          data,
          firestoreCategory: 'Grocery',
          selectedSubcategory: 'Dairy, Bread & Eggs',
          selectedChildCategory: 'Milk',
        ),
        isTrue,
      );
    });
  });
}
