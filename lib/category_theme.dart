import 'package:flutter/material.dart';

class CategoryTheme {
  const CategoryTheme({
    required this.primary,
    required this.background,
  });

  final Color primary;
  final Color background;

  factory CategoryTheme.fromMap(
    Map<String, dynamic> data, {
    required CategoryTheme fallback,
  }) {
    return CategoryTheme(
      primary: _colorFromValue(data['primaryColor']) ?? fallback.primary,
      background:
          _colorFromValue(data['backgroundColor']) ?? fallback.background,
    );
  }

  static Color? _colorFromValue(dynamic value) {
    if (value is int) {
      return Color(value);
    }

    final hex = value?.toString().replaceFirst('#', '').trim() ?? '';
    if (hex.length != 6 && hex.length != 8) {
      return null;
    }

    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) {
      return null;
    }
    return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
  }
}

const groceryCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const vegetablesCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const fruitsCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const foodCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const giftsCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const giftsSurprisesCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const cosmeticsCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const electronicsCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const homeServiceCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const parcelDeliveryCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);
const fallbackCategoryTheme = CategoryTheme(
  primary: Color(0xFF2E7D32),
  background: Color(0xFFF8F9FA),
);

const defaultCategoryThemes = <String, CategoryTheme>{
  'Grocery': groceryCategoryTheme,
  'Vegetables': vegetablesCategoryTheme,
  'Fruits': fruitsCategoryTheme,
  'Food': foodCategoryTheme,
  'Gifts': giftsCategoryTheme,
  'Gifts & Surprises': giftsSurprisesCategoryTheme,
  'Cosmetics': cosmeticsCategoryTheme,
  'Beauty & Personal Care': cosmeticsCategoryTheme,
  'Electronics': electronicsCategoryTheme,
  'Home Service': homeServiceCategoryTheme,
  'Parcel Delivery': parcelDeliveryCategoryTheme,
};

CategoryTheme categoryThemeFor(String category) {
  return defaultCategoryThemes[category.trim()] ?? fallbackCategoryTheme;
}
