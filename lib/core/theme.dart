import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF4CAF82);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceContainer = Color(0xFF16213E);
  static const Color onSurface = Color(0xFFECECEC);
  static const Color onSurfaceMuted = Color(0xFF9E9E9E);
  static const Color error = Color(0xFFCF6679);

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        surfaceContainerHighest: surfaceContainer,
        onSurface: onSurface,
        error: error,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(160, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
