// ─────────────────────────────────────────────────────────────────────────────
//  services/inventory_repair_service.dart  —  Issue 6: Inventory ↔ Repair
//
//  Call InventoryRepairService.applyParts() when parts are added to a job.
//  Call InventoryRepairService.releaseParts() when a job is cancelled.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../services/supabase_service.dart';
import '../services/customer_stats_service.dart';

class InventoryRepairService {
  InventoryRepairService._();

  // Helper: resilient update (multiple data sets)
  static Future<void> updateResilient({
    required String table,
    required Map<String, Object> match,
    required List<Map<String, dynamic>> dataSets,
  }) async {
    for (final data in dataSets) {
      try {
        await SupabaseService.instance.client.from(table).update(data).match(match);
        debugPrint('✅ Resilient update to $table with ${data.keys.length} fields succeeded');
        return;
      } catch (e) {
        debugPrint('⚠️ Resilient update to $table failed with ${data.keys.length} fields: $e');
      }
    }
  }

  // Helper: resilient insert (multiple data sets)
  static Future<void> insertResilient({
    required String table,
    required List<Map<String, dynamic>> dataSets,
  }) async {
    for (final data in dataSets) {
      try {
        await SupabaseService.instance.client.from(table).insert(data);
        debugPrint('✅ Resilient insert to $table with ${data.keys.length} fields succeeded');
        return;
      } catch (e) {
        debugPrint('⚠️ Resilient insert to $table failed with ${data.keys.length} fields: $e');
      }
    }
  }

  // ── Apply parts to a job: deduct stock + update job costs ─────────────────
  static Future<Job> applyParts({
    required WidgetRef ref,
    required Job job,
    required List<PartUsed> parts,
    String by = 'Technician',
  }) async {
    if (parts.isEmpty) return job;
    final shopId   = job.shopId;
    final nowMs    = DateTime.now().millisecondsSinceEpoch;
    final nowIso   = DateTime.now().toIso8601String();

    double totalPartsCost = 0;
    final products = ref.read(productsProvider);

    for (final part in parts) {
      final product = products
          .where((p) => p.productId == part.productId)
          .firstOrNull;
      if (product == null) {
        debugPrint('⚠️ Product ${part.productId} not found in local state');
        continue;
      }

      final newQty = (product.stockQty - part.quantity).clamp(0, 99999);
      totalPartsCost += part.price * part.quantity;

      // ── Supabase: update stock ──────────────────────────────────────────
      await updateResilient(
        table: 'products',
        match: {'productId': part.productId, 'shopId': shopId},
        dataSets: [
          {'stockQty': newQty, 'updatedAt': nowIso},
          {'stockQty': newQty},
        ],
      );

      // ── Supabase: inventory movement log ───────────────────────────────
      await insertResilient(
        table: 'stock_history',
        dataSets: [
          {
            'historyId': 'ih_${nowMs}_${part.productId}',
            'shopId': shopId,
            'productId': part.productId,
            'productName': product.productName,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': -part.quantity,
            'type': 'use_in_job',
            'jobId': job.jobId,
            'time': nowMs,
            'by': by,
          },
          {
            'historyId': 'ih_${nowMs}_${part.productId}',
            'shopId': shopId,
            'productId': part.productId,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': -part.quantity,
            'type': 'use_in_job',
            'jobId': job.jobId,
            'time': nowMs,
          },
        ],
      );

      // ── Local state ─────────────────────────────────────────────────────
      ref.read(productsProvider.notifier).adjustQty(part.productId, -part.quantity);
    }

    // ── Recalculate job costs ────────────────────────────────────────────────
    final settings     = ref.read(settingsProvider);
    final taxRate      = settings.defaultTaxRate;
    final allParts     = [...job.partsUsed, ...parts];
    final partsCost    = allParts.fold<double>(0, (s, p) => s + p.price * p.quantity);
    final taxable      = job.laborCost + partsCost - job.discountAmount;
    final taxAmount    = taxable * taxRate / 100;
    final totalAmount  = taxable + taxAmount;

    final updatedJob = job.copyWith(
      partsUsed    : allParts,
      partsCost    : partsCost,
      taxAmount    : taxAmount,
      totalAmount  : totalAmount,
      updatedAt    : nowIso,
    );

    // ── Persist updated job ─────────────────────────────────────────────────
    await updateResilient(
      table: 'jobs',
      match: {'jobId': job.jobId, 'shopId': shopId} as Map<String, Object>,
      dataSets: [
        {
          'partsUsed': allParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
          'taxAmount': taxAmount,
          'totalAmount': totalAmount,
          'updatedAt': nowIso,
        },
        {
          'partsUsed': allParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
          'totalAmount': totalAmount,
          'updatedAt': nowIso,
        },
        {
          'partsUsed': allParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
        },
      ],
    );

    ref.read(jobsProvider.notifier).updateJob(updatedJob);

    // ── Refresh customer stats ───────────────────────────────────────────────
    if (job.customerId.isNotEmpty) {
      await CustomerStatsService.refresh(
        ref: ref, customerId: job.customerId, shopId: shopId);
    }

    debugPrint('✅ Parts applied to ${job.jobNumber}: ₹$totalPartsCost parts, total ₹$totalAmount');
    return updatedJob;
  }

  static Future<Job> removePart({
    required WidgetRef ref,
    required Job job,
    required PartUsed part,
    String by = 'Technician',
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();
    final products = ref.read(productsProvider);

    final newParts = List<PartUsed>.from(job.partsUsed);
    final idx = newParts.indexWhere((p) =>
        p.productId == part.productId &&
        p.name == part.name &&
        p.quantity == part.quantity &&
        p.price == part.price);
    if (idx < 0) return job;
    newParts.removeAt(idx);

    final partsCost =
        newParts.fold<double>(0, (sum, p) => sum + p.price * p.quantity);
    final taxRate = ref.read(settingsProvider).defaultTaxRate;
    final taxable = job.laborCost + partsCost - job.discountAmount;
    final taxAmount = taxable * taxRate / 100;
    final totalAmount = taxable + taxAmount;

    final updatedJob = job.copyWith(
      partsUsed: newParts,
      partsCost: partsCost,
      taxAmount: taxAmount,
      totalAmount: totalAmount,
      updatedAt: nowIso,
    );

    // Resilient update job
    await updateResilient(
      table: 'jobs',
      match: {'jobId': job.jobId, 'shopId': job.shopId},
      dataSets: [
        {
          'partsUsed': newParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
          'taxAmount': taxAmount,
          'totalAmount': totalAmount,
          'updatedAt': nowIso,
        },
        {
          'partsUsed': newParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
          'totalAmount': totalAmount,
          'updatedAt': nowIso,
        },
        {
          'partsUsed': newParts.map((p) => p.toMap()).toList(),
          'partsCost': partsCost,
        },
      ],
    );

    final product = products.where((p) => p.productId == part.productId).firstOrNull;
    if (product != null) {
      final newQty = product.stockQty + part.quantity;
      // Resilient update product stock
      await updateResilient(
        table: 'products',
        match: {'productId': part.productId, 'shopId': job.shopId} as Map<String, Object>,
        dataSets: [
          {'stockQty': newQty, 'updatedAt': nowIso},
          {'stockQty': newQty},
        ],
      );

      // Resilient insert stock history
      await insertResilient(
        table: 'stock_history',
        dataSets: [
          {
            'historyId': 'ir_${nowMs}_${part.productId}',
            'shopId': job.shopId,
            'productId': part.productId,
            'productName': product.productName,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': part.quantity,
            'type': 'return_from_job',
            'jobId': job.jobId,
            'time': nowMs,
            'by': by,
          },
          {
            'historyId': 'ir_${nowMs}_${part.productId}',
            'shopId': job.shopId,
            'productId': part.productId,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': part.quantity,
            'type': 'return_from_job',
            'jobId': job.jobId,
            'time': nowMs,
          },
        ],
      );

      ref.read(productsProvider.notifier).adjustQty(part.productId, part.quantity);
    }

    ref.read(jobsProvider.notifier).updateJob(updatedJob);
    return updatedJob;
  }

  // ── Release parts back to inventory when a job is cancelled ───────────────
  static Future<void> releaseParts({
    required WidgetRef ref,
    required Job job,
    String by = 'System',
  }) async {
    if (job.partsUsed.isEmpty) return;
    final nowMs    = DateTime.now().millisecondsSinceEpoch;
    final nowIso   = DateTime.now().toIso8601String();

    final products = ref.read(productsProvider);

    for (final part in job.partsUsed) {
      final product = products
          .where((p) => p.productId == part.productId)
          .firstOrNull;
      if (product == null) continue;

      final newQty = product.stockQty + part.quantity;

      // Resilient update product stock
      await updateResilient(
        table: 'products',
        match: {'productId': part.productId, 'shopId': job.shopId} as Map<String, Object>,
        dataSets: [
          {'stockQty': newQty, 'updatedAt': nowIso},
          {'stockQty': newQty},
        ],
      );

      // Resilient insert stock history
      await insertResilient(
        table: 'stock_history',
        dataSets: [
          {
            'historyId': 'ir_${nowMs}_${part.productId}',
            'shopId': job.shopId,
            'productId': part.productId,
            'productName': product.productName,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': part.quantity,
            'type': 'return_from_job',
            'jobId': job.jobId,
            'time': nowMs,
            'by': by,
          },
          {
            'historyId': 'ir_${nowMs}_${part.productId}',
            'shopId': job.shopId,
            'productId': part.productId,
            'oldQty': product.stockQty,
            'newQty': newQty,
            'delta': part.quantity,
            'type': 'return_from_job',
            'jobId': job.jobId,
            'time': nowMs,
          },
        ],
      );

      ref.read(productsProvider.notifier).adjustQty(part.productId, part.quantity);
    }

    debugPrint('✅ Parts released for cancelled job ${job.jobNumber}');
  }
}
