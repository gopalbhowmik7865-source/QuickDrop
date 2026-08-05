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
  primary: Color(0xFF4CAF50),
  background: Color(0xFFE8F5E9),
);
const vegetablesCategoryTheme = CategoryTheme(
  primary: Color(0xFF2ECC71),
  background: Color(0xFFEAFBF1),
);
const fruitsCategoryTheme = CategoryTheme(
  primary: Color(0xFFFF9800),
  background: Color(0xFFFFF3E0),
);
const foodCategoryTheme = CategoryTheme(
  primary: Color(0xFFF44336),
  background: Color(0xFFFFEBEE),
);
const giftsCategoryTheme = CategoryTheme(
  primary: Color(0xFFEC407A),
  background: Color(0xFFFCE4EC),
);
const giftsSurprisesCategoryTheme = CategoryTheme(
  primary: Color(0xFF8E44AD),
  background: Color(0xFFF3E5F5),
);
const cosmeticsCategoryTheme = CategoryTheme(
  primary: Color(0xFFAB47BC),
  background: Color(0xFFF3E5F5),
);
const electronicsCategoryTheme = CategoryTheme(
  primary: Color(0xFF2196F3),
  background: Color(0xFFE3F2FD),
);
const homeServiceCategoryTheme = CategoryTheme(
  primary: Color(0xFF00897B),
  background: Color(0xFFE0F2F1),
);
const parcelDeliveryCategoryTheme = CategoryTheme(
  primary: Color(0xFFEF6C00),
  background: Color(0xFFFFF3E0),
);
const fallbackCategoryTheme = CategoryTheme(
  primary: Color(0xFF2196F3),
  background: Color(0xFFE3F2FD),
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
