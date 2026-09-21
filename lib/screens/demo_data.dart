
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../services/supabase_service.dart';
import '../services/inventory_repair_service.dart';

class DemoDataPage extends ConsumerStatefulWidget {
  const DemoDataPage({super.key});
  @override
  ConsumerState<DemoDataPage> createState() => _DemoDataState();
}

class _DemoDataState extends ConsumerState<DemoDataPage> {
  bool _busy = false;

  Future<void> _seed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
      if (shopId.isEmpty) return;

      Future<void> insertResilient(String table, List<Map<String, dynamic>> dataSets, String description) async {
        for (final data in dataSets) {
          try {
            await SupabaseService.instance.client.from(table).upsert(data);
            debugPrint('✅ $description inserted with ${data.length} fields');
            return;
          } catch (e) {
            debugPrint('⚠️ $description failed with ${data.length} fields: $e');
          }
        }
        debugPrint('⚠️ Failed to insert $description');
      }

      // Seed shop
      await insertResilient('shops', [
        {
          'shopId': shopId,
          'shopName': 'TechFix Demo Shop',
          'ownerName': 'Demo Owner',
          'phone': '+91 90000 00000',
          'email': 'demo@techfixpro.app',
          'address': 'MG Road, Bangalore',
          'gstNumber': '29ABCDE1234F1Z5',
          'defaultTaxRate': 18.0,
          'invoicePrefix': 'INV',
          'requireIntakePhoto': true,
          'requireCompletionPhoto': false,
          'defaultWarrantyDays': 30,
          'darkMode': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        {
          'shopId': shopId,
          'shopName': 'TechFix Demo Shop',
        },
      ], 'Demo shop');

      // Seed staff
      await insertResilient('users', [
        {
          'userId': 'demo_${shopId}_tech_1',
          'uid': 'demo_${shopId}_tech_1', // Support both userId and uid
          'displayName': 'Demo Technician',
          'phone': '+91 91111 11111',
          'email': 'tech@demo.com',
          'role': 'technician',
          'shopId': shopId,
          'specialization': 'Screen Repair',
          'isActive': true,
          'totalJobs': 5,
          'rating': 4.7,
          'demo': true,
          'createdAt': DateTime.now().toIso8601String(),
        },
        {
          'uid': 'demo_${shopId}_tech_1',
          'shopId': shopId,
          'displayName': 'Demo Technician',
          'role': 'technician',
          'isActive': true,
        },
      ], 'Demo tech staff');

      await insertResilient('users', [
        {
          'userId': 'demo_${shopId}_reception_1',
          'uid': 'demo_${shopId}_reception_1',
          'displayName': 'Demo Reception',
          'phone': '+91 92222 22222',
          'email': 'reception@demo.com',
          'role': 'reception',
          'shopId': shopId,
          'specialization': 'Front Desk',
          'isActive': true,
          'totalJobs': 0,
          'rating': 4.5,
          'demo': true,
          'createdAt': DateTime.now().toIso8601String(),
        },
        {
          'uid': 'demo_${shopId}_reception_1',
          'shopId': shopId,
          'displayName': 'Demo Reception',
          'role': 'reception',
          'isActive': true,
        },
      ], 'Demo reception staff');

      // Seed customer
      await insertResilient('customers', [
        {
          'customerId': 'c_demo_1',
          'name': 'Rajesh Kumar',
          'phone': '+91 98765 43210',
          'email': 'rajesh@example.com',
          'address': 'Bangalore',
          'tier': 'Gold',
          'isVip': true,
          'isBlacklisted': false,
          'points': 1200,
          'repairsCount': 2,
          'totalSpend': 25000.0,
          'shopId': shopId,
          'demo': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        {
          'customerId': 'c_demo_1',
          'shopId': shopId,
          'name': 'Rajesh Kumar',
          'phone': '+91 98765 43210',
        },
      ], 'Demo customer');

      // Seed product
      await insertResilient('products', [
        {
          'productId': 'p_demo_1',
          'sku': 'SCR-SAM-S24',
          'productName': 'Samsung S24 OLED Screen',
          'category': 'Spare Parts',
          'brand': 'Samsung',
          'description': 'OEM quality screen',
          'supplierName': 'Demo Supplier',
          'costPrice': 3200.0,
          'sellingPrice': 4200.0,
          'stockQty': 3,
          'reorderLevel': 5,
          'shopId': shopId,
          'demo': true,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        {
          'productId': 'p_demo_1',
          'shopId': shopId,
          'productName': 'Samsung S24 OLED Screen',
          'stockQty': 3,
        },
      ], 'Demo product');

      // Seed job
      await insertResilient('jobs', [
        {
          'jobId': 'j_demo_1',
          'jobNumber': 'JOB-DEMO-0001',
          'customerId': 'c_demo_1',
          'customerName': 'Rajesh Kumar',
          'customerPhone': '+91 98765 43210',
          'brand': 'Samsung',
          'model': 'Galaxy S24',
          'imei': '352099001761481',
          'color': 'Black',
          'problem': 'Screen cracked',
          'notes': 'Demo job',
          'status': 'In Repair',
          'previousStatus': null,
          'holdReason': null,
          'priority': 'Normal',
          'technicianId': 'demo_${shopId}_tech_1',
          'technicianName': 'Demo Technician',
          'createdAt': DateTime.now().toIso8601String(),
          'estimatedEndDate': '2025-02-27',
          'laborCost': 500.0,
          'partsCost': 3500.0,
          'discountAmount': 0.0,
          'taxAmount': 18.0,
          'totalAmount': 4000.0,
          'notificationSent': false,
          'reopenCount': 0,
          'shopId': shopId,
          'demo': true,
          'timeline': [
            {
              'status': 'Job Created',
              'time': DateTime.now().toIso8601String(),
              'by': 'System',
              'type': 'flow',
              'note': 'Demo job seeded'
            }
          ]
        },
        {
          'jobId': 'j_demo_1',
          'shopId': shopId,
          'jobNumber': 'JOB-DEMO-0001',
          'customerName': 'Rajesh Kumar',
          'status': 'In Repair',
        },
      ], 'Demo job');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Demo data seeded for $shopId',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
      if (shopId.isEmpty) return;

      // First, fetch demo jobs to release their parts
      try {
        final demoJobsData = await SupabaseService.instance.client.from('jobs').select().eq('shopId', shopId).eq('demo', true);
        for (final jobData in demoJobsData) {
          final job = Job.fromMap(jobData);
          await InventoryRepairService.releaseParts(
            ref: ref,
            job: job,
            by: 'System',
          );
        }
      } catch (e) {
        debugPrint('⚠️ Failed to fetch/release demo job parts: $e');
      }

      Future<void> deleteResilient(String table, String column, dynamic value) async {
        try {
          await SupabaseService.instance.client.from(table).delete().eq('shopId', shopId).eq(column, value);
          debugPrint('✅ Deleted demo records from $table');
        } catch (e) {
          debugPrint('⚠️ Failed to delete demo records from $table: $e');
        }
      }

      await deleteResilient('customers', 'demo', true);
      await deleteResilient('products', 'demo', true);
      await deleteResilient('jobs', 'demo', true);
      await deleteResilient('users', 'demo', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Demo data cleared for $shopId',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          title: Text('Demo Data Tools',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _infoBanner(
              'These tools are for testing only. They create or remove demo data '
              'for the current shop without affecting other shops.',
            ),
            const SizedBox(height: 16),
            SCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seed Demo Data',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: C.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Populate sample customers, jobs, products and staff for this shop.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: C.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  PBtn(
                    label: 'Seed demo data',
                    onTap: _busy ? null : _seed,
                    full: true,
                    color: C.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SCard(
              borderColor: C.red,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clear Demo Data',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: C.red)),
                  const SizedBox(height: 6),
                  Text(
                    'Remove demo customers, jobs, products and demo staff for this shop.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: C.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  PBtn(
                    label: 'Clear demo data',
                    onTap: _busy ? null : _clear,
                    full: true,
                    color: C.red,
                    outline: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

Widget _infoBanner(String text) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: C.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  GoogleFonts.inter(fontSize: 12, color: C.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
