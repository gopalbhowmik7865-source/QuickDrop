import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class QuickDropColors {
  static const primary = Color(0xFFFFC107);
  static const primaryDark = Color(0xFFFFA000);
  static const primaryLight = Color(0xFFFFECB3);
  static const mint = Color(0xFFEAF7F1);
  static const background = Color(0xFFFAF7F2);
  static const card = Color(0xFFFFFFFF);
  static const beige = Color(0xFFF3EBDD);
  static const lightGreen = Color(0xFFCFEBDD);
  static const text = Color(0xFF1F302B);
  static const secondaryText = Color(0xFF6F7C76);
  static const border = Color(0xFFE8E3DA);
  static const offer = Color(0xFFF6D98B);
  static const commerceGreen = Color(0xFF16803C);
  static const darkText = Color(0xFF1D1D1B);
}

ThemeData quickDropTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: QuickDropColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: Colors.black,
    onPrimary: Colors.white,
    primaryContainer: Colors.black,
    onPrimaryContainer: Colors.white,
    secondary: QuickDropColors.mint,
    onSecondary: QuickDropColors.text,
    surface: QuickDropColors.card,
    onSurface: QuickDropColors.text,
    outline: QuickDropColors.border,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: QuickDropColors.background,
    canvasColor: QuickDropColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: QuickDropColors.background,
      foregroundColor: Colors.black,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: QuickDropColors.background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      color: QuickDropColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: QuickDropColors.card,
      prefixIconColor: Colors.black,
      labelStyle: const TextStyle(color: QuickDropColors.secondaryText),
      hintStyle: const TextStyle(color: QuickDropColors.secondaryText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: QuickDropColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: QuickDropColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Colors.black, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: QuickDropColors.primaryDark,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: QuickDropColors.border),
  );
}
