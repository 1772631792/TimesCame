import 'package:flutter/material.dart';

/// 全局配色：深色玻璃感底 + 蓝紫渐变强调色。
class Palette {
  const Palette._();

  static const bg = Color(0xFF05080E);
  static const bgTop = Color(0xFF0B1220);
  static const card = Color(0xFF101828);
  static const cardSoft = Color(0xFF0C1421);
  static const stroke = Color(0x1FFFFFFF);
  static const text = Color(0xFFF3F7FF);
  static const textDim = Color(0xFF8B99AE);
  static const accent = Color(0xFF4F8CFF);
  static const accent2 = Color(0xFF9B6BFF);
  static const ok = Color(0xFF35D07F);
  static const warn = Color(0xFFFFB020);
  static const err = Color(0xFFFF5F6D);

  static const grad = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const cardGrad = LinearGradient(
    colors: [Color(0xFF131C2E), Color(0xFF0C1421)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Palette.accent,
    secondary: Palette.accent2,
    surface: Palette.card,
    onSurface: Palette.text,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    splashFactory: InkSparkle.splashFactory,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF182133),
      contentTextStyle: const TextStyle(color: Palette.text, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Color(0xCC05080E),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF8493A8),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.accent : const Color(0xFF243044),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Palette.accent,
      selectionColor: Color(0x554F8CFF),
      selectionHandleColor: Palette.accent,
    ),
  );
}

const kBgGradient = LinearGradient(
  colors: [Palette.bgTop, Palette.bg, Color(0xFF04060B)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.0, 0.45, 1.0],
);
