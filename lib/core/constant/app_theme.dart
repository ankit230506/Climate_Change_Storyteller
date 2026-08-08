import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColorScheme {
  final Color bg0;
  final Color bg1;
  final Color bg2;
  final Color bg3;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color cardBorder;

  const AppColorScheme({
    required this.bg0,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.cardBorder,
  });

  factory AppColorScheme.dark() => const AppColorScheme(
    bg0: Color(0xFF07080F),
    bg1: Color(0xFF0E1018),
    bg2: Color(0xFF161824),
    bg3: Color(0xFF1E2030),
    textPrimary: Color(0xFFF0F4FF),
    textSecondary: Color(0xFF8892AA),
    textMuted: Color(0xFF727D9A),
    cardBorder: Color(0xFF1E2235),
  );

  factory AppColorScheme.light() => const AppColorScheme(
    bg0: Color(0xFFF4F6FA),
    bg1: Color(0xFFFFFFFF),
    bg2: Color(0xFFEBF0F7),
    bg3: Color(0xFFE2E8F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textMuted: Color(0xFF64748B),
    cardBorder: Color(0xFFCBD5E1),
  );
}

class AppColors {
  // Dark palette constants
  static const darkBg0 = Color(0xFF07080F);
  static const darkBg1 = Color(0xFF0E1018);
  static const darkBg2 = Color(0xFF161824);
  static const darkBg3 = Color(0xFF1E2030);
  static const darkTextPrimary = Color(0xFFF0F4FF);
  static const darkTextSecondary = Color(0xFF8892AA);
  static const darkTextMuted = Color(0xFF727D9A);
  static const darkCardBorder = Color(0xFF1E2235);

  // Light palette constants
  static const lightBg0 = Color(0xFFF4F6FA);
  static const lightBg1 = Color(0xFFFFFFFF);
  static const lightBg2 = Color(0xFFEBF0F7);
  static const lightBg3 = Color(0xFFE2E8F0);
  static const lightTextPrimary = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF334155);
  static const lightTextMuted = Color(0xFF64748B);
  static const lightCardBorder = Color(0xFFCBD5E1);

  // Static constants for backward compatibility
  static const bg0 = darkBg0;
  static const bg1 = darkBg1;
  static const bg2 = darkBg2;
  static const bg3 = darkBg3;

  static const textPrimary = darkTextPrimary;
  static const textSecondary = darkTextSecondary;
  static const textMuted = darkTextMuted;
  static const cardBorder = darkCardBorder;

  // Context-aware color accessor for dynamic theme evaluation
  static AppColorScheme of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColorScheme.dark() : AppColorScheme.light();
  }

  // Accent — rich teal-cyan system
  static const primary = Color(0xFF00A884);   // main teal
  static const primaryDim = Color(0xFF00896C); // pressed teal
  static const secondary = Color(0xFF0284C7); // blue-cyan
  static const accent = Color(0xFF00B4D8);    // highlight / glow

  // Semantic
  static const critical = Color(0xFFFF4D4D);
  static const warning = Color(0xFFFFB347);
  static const good = Color(0xFF4CAF50);
  static const ready = Color(0xFF00A884);
  static const loading = Color(0xFF0284C7);

  // KML layer type colors
  static const glacier = Color(0xFF0284C7);
  static const seaLevel = Color(0xFF0097A7);
  static const forest = Color(0xFF388E3C);
  static const heat = Color(0xFFE65100);
}

class AppTypography {
  // Bold, rounded display typography (Outfit) & readable body typography (Nunito)
  static TextStyle heading1 = GoogleFonts.outfit(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static TextStyle heading2 = GoogleFonts.outfit(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle heading3 = GoogleFonts.outfit(
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  static TextStyle bodyLarge = GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static TextStyle bodySmall = GoogleFonts.nunito(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static TextStyle caption = GoogleFonts.nunito(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  static TextStyle dataValue = GoogleFonts.outfit(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
  );

  static TextStyle label = GoogleFonts.outfit(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}

class AppTheme {
  static ThemeData get light {
    final baseTextTheme = ThemeData.light().textTheme;
    final outfitTextTheme = GoogleFonts.outfitTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg0,
      primaryColor: AppColors.primary,
      fontFamily: GoogleFonts.outfit().fontFamily,

      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.lightBg1,
        onSurface: AppColors.lightTextPrimary,
        error: AppColors.critical,
      ),

      textTheme: outfitTextTheme.copyWith(
        displayLarge: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.nunito(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500),
        bodyMedium: GoogleFonts.nunito(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500),
        bodySmall: GoogleFonts.nunito(color: AppColors.lightTextSecondary, fontWeight: FontWeight.w500),
        labelLarge: GoogleFonts.outfit(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
        labelMedium: GoogleFonts.outfit(color: AppColors.lightTextSecondary, fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.nunito(color: AppColors.lightTextMuted, fontWeight: FontWeight.w600),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBg0,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
          color: AppColors.lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightBg1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.lightTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Cards
      cardTheme: const CardThemeData(
        color: AppColors.lightBg1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.lightCardBorder, width: 1),
        ),
        margin: EdgeInsets.symmetric(vertical: 6),
      ),

      // Elevated button — primary CTA
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.outfit(
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
          foregroundColor: AppColors.lightTextPrimary,
          minimumSize: const Size(double.infinity, 54),
          side: const BorderSide(color: AppColors.lightCardBorder, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightBg3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightCardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: GoogleFonts.nunito(fontSize: 13, color: AppColors.lightTextMuted),
        labelStyle: GoogleFonts.nunito(fontSize: 13, color: AppColors.lightTextSecondary),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightBg3,
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.lightTextSecondary,
        ),
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.lightCardBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Slider
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.lightBg3,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2200A884),
        trackHeight: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.lightCardBorder,
        thickness: 1,
        space: 1,
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightBg1,
        surfaceTintColor: Colors.transparent,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightBg1,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.lightTextPrimary,
        ),
        contentTextStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  static ThemeData get dark {
    final baseTextTheme = ThemeData.dark().textTheme;
    final outfitTextTheme = GoogleFonts.outfitTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg0,
      primaryColor: AppColors.primary,
      fontFamily: GoogleFonts.outfit().fontFamily,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.darkBg1,
        onSurface: AppColors.darkTextPrimary,
        error: AppColors.critical,
      ),

      textTheme: outfitTextTheme.copyWith(
        displayLarge: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        headlineLarge: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        headlineSmall: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.nunito(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500),
        bodyMedium: GoogleFonts.nunito(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500),
        bodySmall: GoogleFonts.nunito(color: AppColors.darkTextSecondary, fontWeight: FontWeight.w500),
        labelLarge: GoogleFonts.outfit(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
        labelMedium: GoogleFonts.outfit(color: AppColors.darkTextSecondary, fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.nunito(color: AppColors.darkTextMuted, fontWeight: FontWeight.w600),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBg0,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
          color: AppColors.darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      ),

      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkBg1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.darkTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Cards
      cardTheme: const CardThemeData(
        color: AppColors.darkBg1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.darkCardBorder, width: 1),
        ),
        margin: EdgeInsets.symmetric(vertical: 6),
      ),

      // Elevated button — primary CTA
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.outfit(
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
          foregroundColor: AppColors.darkTextPrimary,
          minimumSize: const Size(double.infinity, 54),
          side: const BorderSide(color: AppColors.darkBg3, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkBg3,
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
        hintStyle: GoogleFonts.nunito(fontSize: 13, color: AppColors.darkTextMuted),
        labelStyle: GoogleFonts.nunito(fontSize: 13, color: AppColors.darkTextSecondary),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkBg3,
        labelStyle: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.darkTextSecondary,
        ),
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF252840)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Slider
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.darkBg3,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x2200A884),
        trackHeight: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1A1E2E),
        thickness: 1,
        space: 1,
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkBg1,
        surfaceTintColor: Colors.transparent,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkBg1,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.darkTextPrimary,
        ),
        contentTextStyle: GoogleFonts.nunito(
          fontSize: 14,
          color: AppColors.darkTextSecondary,
        ),
      ),
    );
  }
}
