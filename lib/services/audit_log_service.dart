// ─────────────────────────────────────────────────────────────────────────────
//  services/audit_log_service.dart
//
//  Writes a row to the audit_logs table (created by V3 migration).
//  All writes are fire-and-forget — a failure never blocks the UI.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class AuditLogService {
  AuditLogService._();

  static const String create = 'CREATE';
  static const String update = 'UPDATE';
  static const String delete = 'DELETE';
  static const String view   = 'VIEW';

  /// Log an action. Safe to call with unawaited() — catches its own errors.
  static Future<void> log({
    required String shopId,
    required String userId,
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic> details = const {},
  }) async {
    try {
      final logId = 'log-${DateTime.now().millisecondsSinceEpoch}';
      await SupabaseService.instance.client.from('audit_logs').insert({
        'logId'    : logId,
        'shopId'   : shopId,
        'userId'   : userId,
        'action'   : action,
        'entity'   : entity,
        'entityId' : entityId,
        'details'  : details,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Audit failures must never crash the app
      debugPrint('⚠️ AuditLogService.log failed: $e');
    }
  }
}
