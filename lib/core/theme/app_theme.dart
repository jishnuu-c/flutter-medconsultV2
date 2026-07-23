import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors from Angular styles.css
  static const Color primaryTeal = Color(0xFF1D9E75);
  static const Color primaryDarkTeal = Color(0xFF0F6E56);
  static const Color primaryLightTeal = Color(0xFFE1F5EE);
  static const Color darkSidebar = Color(0xFF0A1F15);
  static const Color darkSidebarItem = Color(0xFF112B1E);
  
  static const Color backgroundApp = Color(0xFFF8FAF9);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderGray = Color(0xFFE5E7EB);

  static const Color textMain = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color successGreen = Color(0xFF22C55E);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color infoBlue = Color(0xFF3B82F6);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        primary: primaryTeal,
        onPrimary: Colors.white,
        secondary: successGreen,
        surface: surfaceWhite,
        error: dangerRed,
      ),
      scaffoldBackgroundColor: backgroundApp,
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        bodyLarge: const TextStyle(color: textMain),
        bodyMedium: const TextStyle(color: textSecondary),
        bodySmall: const TextStyle(color: textMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textMain),
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderGray,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: borderGray),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTeal,
          side: const BorderSide(color: primaryTeal),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryTeal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: dangerRed),
        ),
      ),
    );
  }
}
