import 'package:flutter/material.dart';

/// DtRide pack tokens: ink black + taxi yellow on white.
abstract final class AppColors {
  static const primary = Color(0xFF111111);
  static const primaryDark = Color(0xFF111111);
  static const accent = Color(0xFFFACC15);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
  static const ink = Color(0xFF111111);
  static const muted = Color(0xFF6B7280);
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF4F4F5);
  static const border = Color(0xFFE5E7EB);
}

ThemeData buildAppTheme() {
  const radius = BorderRadius.all(Radius.circular(12));
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: const BorderSide(color: AppColors.ink, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: const ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
    ),
  );
}
