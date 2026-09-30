import 'package:flutter/material.dart';
import 'app_theme.dart';

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
  primary: QuickDropColors.primary,
  background: QuickDropColors.primaryLight,
);
const vegetablesCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.lightGreen,
);
const fruitsCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.mint,
);
const foodCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.beige,
);
const giftsCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.primaryLight,
);
const giftsSurprisesCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.beige,
);
const cosmeticsCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.mint,
);
const electronicsCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.beige,
);
const homeServiceCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.primaryLight,
);
const parcelDeliveryCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.mint,
);
const fallbackCategoryTheme = CategoryTheme(
  primary: QuickDropColors.primary,
  background: QuickDropColors.mint,
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
