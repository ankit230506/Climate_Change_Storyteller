import 'package:flutter/material.dart';

class AppColors {
  // Background layers
  static const bg0 = Color(0xFF07080F); // deepest bg
  static const bg1 = Color(0xFF0E1018); // card bg
  static const bg2 = Color(0xFF161824); // elevated card
  static const bg3 = Color(0xFF1E2030); // input / chip bg

  // Accent — teal-cyan system
  static const primary = Color(0xFF00C4A0);   // main teal
  static const primaryDim = Color(0xFF00A086); // pressed teal
  static const secondary = Color(0xFF00B4D8); // blue-cyan (links, active nav)
  static const accent = Color(0xFF64FFDA);    // highlight / glow

  // Semantic
  static const critical = Color(0xFFFF4D4D);
  static const warning = Color(0xFFFFB347);
  static const good = Color(0xFF4CAF50);
  static const ready = Color(0xFF00C4A0);
  static const loading = Color(0xFF90CAF9);

  // Text
  static const textPrimary = Color(0xFFF0F4FF);
  static const textSecondary = Color(0xFF8892AA);
  static const textMuted = Color(0xFF505870);

  // KML layer type colors
  static const glacier = Color(0xFF64B5F6);
  static const seaLevel = Color(0xFF4FC3F7);
  static const forest = Color(0xFF81C784);
  static const heat = Color(0xFFFF8A65);
}

class AppTypography {
  static const fontDisplay = 'Sora';    // headings (add to pubspec)
  static const fontBody = 'DM Sans';   // body (add to pubspec)
  static const fontMono = 'JetBrains Mono'; // data values

  static const heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static const heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static const heading3 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    color: AppColors.textMuted,
  );

  static const dataValue = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    color: AppColors.textPrimary,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
  );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg0,
      primaryColor: AppColors.primary,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.bg1,
        onSurface: AppColors.textPrimary,
        error: AppColors.critical,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg0,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.heading2,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bg1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Cards
      cardTheme: const CardThemeData(
        color: AppColors.bg1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFF1E2235), width: 1),
        ),
        margin: EdgeInsets.symmetric(vertical: 6),
      ),

      // Elevated button — primary CTA
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.bg0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          elevation: 0,
        ),
      ),

      // Outlined button — secondary
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(double.infinity, 54),
          side: const BorderSide(color: AppColors.bg3, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF252840), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: AppTypography.bodySmall,
        labelStyle: AppTypography.bodySmall,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bg3,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        selectedColor: AppColors.primary.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF252840)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Slider
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.bg3,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2200C4A0),
        trackHeight: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1A1E2E),
        thickness: 1,
        space: 1,
      ),
    );
  }
}