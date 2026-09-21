// ─────────────────────────────────────────────────────────────────────────────
//  services/phone_normalizer.dart
//
//  Normalises phone numbers before storage and lookup so that
//  "+91 98765 43210", "9876543210", "091-98765-43210" all match each other.
// ─────────────────────────────────────────────────────────────────────────────

class PhoneNormalizer {
  PhoneNormalizer._();

  /// Strip everything except digits and a leading +.
  /// "+91 98765 43210" → "+919876543210"
  /// "091-9876543210"  → "0919876543210"
  static String normalize(String raw) {
    if (raw.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '+' && i == 0) {
        buf.write('+');
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// Returns true if two phone strings refer to the same subscriber.
  /// Compares last 10 digits (works for Indian numbers with/without country code).
  static bool isSamePhone(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final na = normalize(a);
    final nb = normalize(b);
    if (na == nb) return true;
    // Last-10 comparison (handles +91 prefix vs plain 10-digit)
    final la = na.length >= 10 ? na.substring(na.length - 10) : na;
    final lb = nb.length >= 10 ? nb.substring(nb.length - 10) : nb;
    return la == lb;
  }
}
