// ─────────────────────────────────────────────────────────────────────────────
//  services/customer_stats_service.dart
//
//  Recomputes a customer's repairsCount, openJobs, completedJobs, totalSpend
//  and lastVisit by querying the jobs table, then updates both Supabase
//  and the local customersProvider.
//
//  Call this after any job creation, status change, or deletion.
//  It is designed to be fire-and-forget (wrap in _unawaited()).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/providers.dart';
import 'supabase_service.dart';

class CustomerStatsService {
  CustomerStatsService._();

  /// Recalculates stats for [customerId] and persists them.
  static Future<void> refresh({
    required WidgetRef ref,
    required String customerId,
    required String shopId,
  }) async {
    try {
      // Fetch all jobs for this customer
      final rows = await SupabaseService.instance.client
          .from('jobs')
          .select('status, totalAmount, createdAt')
          .eq('shopId', shopId)
          .eq('customerId', customerId);

      final jobs = rows as List;

      final totalRepairs  = jobs.length;
      final openJobs      = jobs.where((j) {
        final s = (j['status'] as String?) ?? '';
        return s != 'Delivered' && s != 'Cancelled' && s != 'Completed';
      }).length;
      final completedJobs = jobs.where((j) {
        final s = (j['status'] as String?) ?? '';
        return s == 'Delivered' || s == 'Completed';
      }).length;
      final totalSpend    = jobs.fold<double>(0, (sum, j) =>
          sum + ((j['totalAmount'] as num?)?.toDouble() ?? 0));

      // Most recent job date
      String lastVisit = '';
      if (jobs.isNotEmpty) {
        final dates = jobs
            .map((j) => (j['createdAt'] as String?) ?? '')
            .where((d) => d.isNotEmpty)
            .toList()
          ..sort((a, b) => b.compareTo(a));
        lastVisit = dates.isNotEmpty ? dates.first : '';
      }

      // Persist to Supabase
      await SupabaseService.instance.client.from('customers').update({
        'repairsCount' : totalRepairs,
        'openJobs'     : openJobs,
        'completedJobs': completedJobs,
        'totalSpend'   : totalSpend,
        'lastVisit'    : lastVisit,
        'updatedAt'    : DateTime.now().toIso8601String(),
      }).eq('customerId', customerId);

      // Update local provider so UI reflects changes immediately
      final existing = ref.read(customersProvider);
      final idx = existing.indexWhere((c) => c.customerId == customerId);
      if (idx >= 0) {
        final updated = existing[idx].copyWith(
          repairsCount: totalRepairs,
          totalSpend  : totalSpend,
          updatedAt   : DateTime.now().toIso8601String(),
        );
        ref.read(customersProvider.notifier).update(updated);
      }

      debugPrint('✅ CustomerStatsService: refreshed $customerId '
          '(repairs=$totalRepairs spend=$totalSpend)');
    } catch (e) {
      debugPrint('⚠️ CustomerStatsService.refresh failed: $e');
    }
  }
}
