import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers.dart';

// Global Option 2 theme: premium repair desk.
// Navy gives the app authority, amber adds a service/repair accent, and the
// soft gray background avoids the flat pure-white look.
//
// Fonts: Plus Jakarta Sans for headings/actions and Inter for body text.
//
// NOTE on C.white: this identifier is used app-wide for high-emphasis text in
// the light theme. Use Colors.white directly when literal white is required.

class C {
  // Backgrounds
  static const bgLight = Color(0xFFF4F6F8); // page background (light)
  static const bgCardLight = Color(0xFFFFFFFF); // card surface (light)
  static const bgElevatedLight = Color(0xFFFBFCFE); // app bar / sheets / menus (light)
  static const bgInputLight = Color(0xFFF8FAFC); // input fill (light)
  static const bgDark = Color(0xFF0F172A); // page background (dark)
  static const bgCardDark = Color(0xFF1E293B); // card surface (dark)
  static const bgElevatedDark = Color(0xFF1E293B); // app bar / sheets / menus (dark)
  static const bgInputDark = Color(0xFF334155); // input fill (dark)

  // Borders
  static const borderLight = Color(0xFFE2E8F0);
  static const borderLightLight = Color(0xFFF1F5F9);
  static const borderDark = Color(0xFF334155);
  static const borderDarkLight = Color(0xFF475569);

  // Brand
  static const primary = Color(0xFF1E3A8A); // premium navy
  static const primaryDark = Color(0xFF172554);
  static const accent = Color(0xFFD97706); // repair/service amber

  // Status
  static const green = Color(0xFF16A34A);
  static const greenDark = Color(0xFF15803D);
  static const yellow = Color(0xFFD97706);
  static const red = Color(0xFFDC2626);
  static const purple = Color(0xFF7C3AED);

  // Text
  static const textLight = Color(0xFF1E293B); // primary body text (light)
  static const textMutedLight = Color(0xFF64748B); // secondary text (light)
  static const textDimLight = Color(0xFF94A3B8); // hints / placeholders (light)
  static const whiteLight = Color(0xFF0F172A); // high-emphasis text (light)
  static const textDark = Color(0xFFF8FAFC); // primary body text (dark)
  static const textMutedDark = Color(0xFF94A3B8); // secondary text (dark)
  static const textDimDark = Color(0xFF64748B); // hints / placeholders (dark)
  static const whiteDark = Color(0xFFFFFFFF); // high-emphasis text (dark)

  // Backward compatibility (defaults to light theme)
  static const bg = bgLight;
  static const bgCard = bgCardLight;
  static const bgElevated = bgElevatedLight;
  static const bgInput = bgInputLight;
  static const border = borderLight;
  static const borderLightAlt = borderLightLight;
  static const text = textLight;
  static const textMuted = textMutedLight;
  static const textDim = textDimLight;
  static const white = whiteLight;

  // ── Status / tier / timeline helpers ──────────────────────────
  // These are called throughout the app as C.statusColor(...), C.tierColor(...),
  // etc. (see w.dart, repair_detail.dart, repairs.dart, customers.dart,
  // customer_detail.dart, dash.dart, settings.dart). They previously lived on
  // AppTheme, which none of the screens actually reference, so every call
  // site was failing to resolve. Moved here to match real usage.

  static Color statusColor(String status) {
    const map = {
      'Checked In':       Color(0xFF0EA5E9),
      'Diagnosed':        Color(0xFF7C3AED),
      'Awaiting Approval':Color(0xFFD97706),
      'Waiting for Parts':Color(0xFFF97316),
      'In Repair':        Color(0xFF1E3A8A),
      'Testing':          Color(0xFF06B6D4),
      'QC Passed':        Color(0xFF22C55E),
      'Ready for Pickup': Color(0xFF10B981),
      'Completed':        Color(0xFF16A34A),
      'On Hold':          Color(0xFFEAB308),
      'Cancelled':        Color(0xFFDC2626),
      'Warranty Claim':   Color(0xFFF43F5E),
    };
    return map[status] ?? const Color(0xFF64748B);
  }

  static String statusIcon(String status) {
    const map = {
      'Checked In':       '📥',
      'Diagnosed':        '🔍',
      'Awaiting Approval':'⏳',
      'Waiting for Parts':'📦',
      'In Repair':        '🔧',
      'Testing':          '🧪',
      'QC Passed':        '✅',
      'Ready for Pickup': '🎉',
      'Completed':        '🏁',
      'On Hold':          '⏸️',
      'Cancelled':        '❌',
      'Warranty Claim':   '🛡️',
    };
    return map[status] ?? '•';
  }

  static String? statusNext(String status) {
    const map = {
      'Checked In':       'Diagnosed',
      'Diagnosed':        'Awaiting Approval',
      'Awaiting Approval':'In Repair',
      'Waiting for Parts':'In Repair',
      'In Repair':        'Testing',
      'Testing':          'QC Passed',
      'QC Passed':        'Ready for Pickup',
      'Ready for Pickup': 'Completed',
    };
    return map[status];
  }

  static Color tierColor(String tier) {
    const map = {
      'Gold':     Color(0xFFD97706),
      'Silver':   Color(0xFF64748B),
      'Platinum': Color(0xFF7C3AED),
      'Bronze':   Color(0xFF92400E),
    };
    return map[tier] ?? const Color(0xFF64748B);
  }

  static Color timelineTypeColor(String type) {
    const map = {
      'flow':   Color(0xFF1E3A8A),
      'note':   Color(0xFF64748B),
      'hold':   Color(0xFFD97706),
      'cancel': Color(0xFFDC2626),
      'reopen': Color(0xFF22C55E),
    };
    return map[type] ?? const Color(0xFF64748B);
  }
}

// Theme colors for use with Riverpod
class AppTheme {
  final bool isDark;
  AppTheme(this.isDark);

  Color get bg => isDark ? C.bgDark : C.bgLight;
  Color get bgCard => isDark ? C.bgCardDark : C.bgCardLight;
  Color get bgElevated => isDark ? C.bgElevatedDark : C.bgElevatedLight;
  Color get bgInput => isDark ? C.bgInputDark : C.bgInputLight;

  Color get border => isDark ? C.borderDark : C.borderLight;
  Color get borderLight => isDark ? C.borderDarkLight : C.borderLightLight;

  Color get text => isDark ? C.textDark : C.textLight;
  Color get textMuted => isDark ? C.textMutedDark : C.textMutedLight;
  Color get textDim => isDark ? C.textDimDark : C.textDimLight;
  Color get white => isDark ? C.whiteDark : C.whiteLight;
  static const primary = C.primary;
  static const primaryDark = C.primaryDark;
  static const accent = C.accent;
  static const green = C.green;
  static const greenDark = C.greenDark;
  static const yellow = C.yellow;
  static const red = C.red;
  static const purple = C.purple;
}

ThemeData buildTheme(bool isDark) {
  final base = isDark ? ThemeData.dark() : ThemeData.light();
  final t = AppTheme(isDark);

  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: C.primary, secondary: C.accent, surface: C.bgCardDark, error: C.red)
      : const ColorScheme.light(
          primary: C.primary, secondary: C.accent, surface: C.bgCardLight, error: C.red);

  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    colorScheme: colorScheme,
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: t.text, displayColor: t.white),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bgElevated, foregroundColor: t.white, elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: t.white),
      iconTheme: IconThemeData(color: t.white),
      shape: Border(bottom: BorderSide(color: t.border, width: 1)),
    ),
    cardTheme: CardThemeData(
      color: t.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: t.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: t.bgInput,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.primary, width: 2)),
      labelStyle: TextStyle(color: t.textMuted, fontSize: 12),
      hintStyle: TextStyle(color: t.textDim, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    dividerColor: t.border,
    dividerTheme: DividerThemeData(color: t.border, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : t.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary.withValues(alpha: 0.4) : t.border),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : Colors.transparent),
      side: BorderSide(color: t.border, width: 2),
    ),
  );
}

// Provider to get current theme colors
final appThemeProvider = Provider<AppTheme>((ref) {
  final settings = ref.watch(settingsProvider);
  return AppTheme(settings.darkMode);
});
