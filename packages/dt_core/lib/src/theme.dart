import 'package:flutter/material.dart';

/// Shared DT Ride brand: deep navy + ride orange (matches the dtRide logo).
/// All copy lives in strings.dart (English now, Hindi later via the same keys).
abstract final class AppColors {
  static const primary = Color(0xFF0B3D91);
  static const primaryDark = Color(0xFF071F52);
  static const accent = Color(0xFFFF8A00);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const canvas = Color(0xFFF1F5F9);
}

ThemeData buildAppTheme() {
  const radius = BorderRadius.all(Radius.circular(14));
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.grey.shade300)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
