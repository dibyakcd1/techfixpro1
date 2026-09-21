// ─────────────────────────────────────────────────────────────────────────────
//  services/job_number_service.dart
//
//  Generates collision-safe, sequential job numbers using the
//  shop_counters table + increment_counter() RPC (created by the V3 migration).
//
//  Falls back to a timestamp-based number if the RPC is unavailable,
//  so the app never blocks job creation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class JobNumberService {
  JobNumberService._();

  /// Returns the next formatted job number for [shopId], e.g. "JOB-2026-0042".
  static Future<String> nextJobNumber({
    required String shopId,
    required String prefix,
  }) async {
    final year = DateTime.now().year;
    try {
      // increment_counter is an RPC created by the V3 SQL migration
      final result = await SupabaseService.instance.client
          .rpc('increment_counter', params: {
            'p_shop_id': shopId,
            'p_field':   'nextJobNumber',
          });
      final seq = (result as int?) ?? 1;
      return '$prefix-$year-${seq.toString().padLeft(4, '0')}';
    } catch (e) {
      debugPrint('⚠️ increment_counter RPC failed, using timestamp fallback: $e');
      // Fallback: timestamp-based — unique but not sequential
      final ts = DateTime.now().millisecondsSinceEpoch % 100000;
      return '$prefix-$year-T$ts';
    }
  }
}
