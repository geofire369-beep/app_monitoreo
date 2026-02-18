import 'package:flutter/material.dart';

class AppTheme {
  // Paleta inspirada en chiles morrones (minimalista)
  static const Color pepperGreen = Color(0xFF2E7D32);
  static const Color pepperRed = Color(0xFFC62828);
  static const Color pepperYellow = Color(0xFFF9A825);

  static const Color surface = Color(0xFFF7F7F7);
  static const Color ink = Color(0xFF111111);

  // Neutros para inputs/textos (evita morados por Material3 default)
  static const Color hint = Color(0xFF8A8A8A);
  static const Color label = Color(0xFF444444);
  static const Color body = Color(0xFF333333);

  static ThemeData light() {
    // ✅ Define explícitamente primary/secondary para que nunca “caiga” en morado
    final colorScheme = ColorScheme.fromSeed(
      seedColor: pepperGreen,
      brightness: Brightness.light,
      surface: surface,
      primary: pepperGreen,
      secondary: pepperRed,
      tertiary: pepperYellow,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,

      // ✅ Cursor/selección de texto (evita defaults raros)
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: pepperGreen,
        selectionColor: pepperGreen.withValues(alpha: 0.22),
        selectionHandleColor: pepperGreen,
      ),

      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: body,
        ),
      ),

      // ✅ Inputs: quita morado en label/focus y deja un estilo consistente
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,

        hintStyle: const TextStyle(color: hint),
        labelStyle: const TextStyle(
          color: label,
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: TextStyle(
          color: pepperGreen.withValues(alpha: 0.95),
          fontWeight: FontWeight.w800,
        ),

        prefixIconColor: label,
        suffixIconColor: label,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: pepperGreen.withValues(alpha: 0.75),
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: pepperRed.withValues(alpha: 0.75),
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: pepperRed.withValues(alpha: 0.90),
            width: 1.4,
          ),
        ),

        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: pepperGreen, // ✅ nada morado
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        selectedColor: pepperGreen.withValues(alpha: 0.14),
      ),

      // ✅ Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        surfaceTintColor: Colors.white,
      ),

      // ✅ Switch: evita colores default
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return pepperGreen;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return pepperGreen.withValues(alpha: 0.35);
          }
          return Colors.black.withValues(alpha: 0.18);
        }),
      ),
    );
  }
}
