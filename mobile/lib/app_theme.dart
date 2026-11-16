import 'package:flutter/material.dart';

class AppTheme {
  static const canvas = Color(0xFF111214);
  static const surface = Color(0xFF1B1C1F);
  static const ink = Color(0xFFE6EEE8);
  static const muted = Color(0xFFA4B2A9);
  static const line = Color(0xFF35373B);
  static const green = Color(0xFF719B78);
  static const lime = Color(0xFFC9EB87);
  static const error = Color(0xFFF0A29B);

  static ThemeData get dark {
    final scheme = const ColorScheme.dark(
      primary: green,
      onPrimary: Color(0xFF101511),
      secondary: lime,
      onSecondary: Color(0xFF171B10),
      surface: surface,
      onSurface: ink,
      error: error,
      onError: Color(0xFF240A08),
      outline: line,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvas,
      colorScheme: scheme,
      textTheme: Typography.material2021().white.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: const TextStyle(color: muted),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: line),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: lime, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: error),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: error, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
