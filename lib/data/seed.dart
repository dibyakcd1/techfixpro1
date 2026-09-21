import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ShopOnboarding (Supabase version)
//
//  FIXES:
//    1. role was 'admin' → must be 'super_admin' (matches DB CHECK constraint)
//    2. All inserts use upsert (onConflict) so re-running after a partial
//       failure doesn't throw a duplicate-key error
//    3. Removed the fallback "try smaller payloads" loop — if the full insert
//       fails we now surface the real error instead of silently eating it
// ─────────────────────────────────────────────────────────────────────────────

class ShopOnboarding {
  static Future<void> initialize({
    required String shopId,
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String shopName,
    required String ownerPin,
    String plan = 'free',
  }) async {
    final now = DateTime.now().toIso8601String();

    // ── STEP 1 — registrations ────────────────────────────────────────────
    try {
      await SupabaseService().client.from('registrations').upsert(
        {
          'uid':          ownerUid,
          'shopId':       shopId,
          'email':        ownerEmail,
          'shopName':     shopName,
          'status':       'active',
          'registeredAt': now,
        },
        onConflict: 'uid',   // safe to re-run
      );
      debugPrint('✅ Step 1 — registrations written');
    } catch (e) {
      // Non-fatal — app works without this row
      debugPrint('⚠️ Step 1 (registrations) skipped: $e');
    }

    // ── STEP 2 — shops ────────────────────────────────────────────────────
    try {
      await SupabaseService().client.from('shops').upsert(
        _buildShopDoc(
          shopId:     shopId,
          shopName:   shopName,
          ownerUid:   ownerUid,
          ownerName:  ownerName,
          ownerEmail: ownerEmail,
          ownerPhone: ownerPhone,
          plan:       plan,
          now:        now,
        ),
        onConflict: 'shopId',
      );
      debugPrint('✅ Step 2 — shops written');
    } catch (e) {
      debugPrint('❌ Step 2 (shops) failed: $e');
      rethrow;
    }

    // ── STEP 3 — users (owner row) ────────────────────────────────────────
    // FIX: role MUST be 'super_admin' — the DB CHECK constraint rejects 'admin'
    try {
      await SupabaseService().client.from('users').upsert(
        {
          'uid':              ownerUid,
          'shopId':           shopId,
          'displayName':      ownerName,
          'email':            ownerEmail,
          'phone':            ownerPhone,
          'role':             'super_admin',   // ← was 'admin' — FIXED
          'isOwner':          true,
          'isActive':         true,
          'biometricEnabled': false,
          'specialization':   'Management',
          'pin':              ownerPin,
          'pin_hash':         '',
          'totalJobs':        0,
          'completedJobs':    0,
          'rating':           5.0,
          'joinedAt':         now,
          'lastLoginAt':      now,
          'createdAt':        now,
          'updatedAt':        now,
        },
        onConflict: 'uid',   // safe to re-run
      );
      debugPrint('✅ Step 3 — users (owner) written');
    } catch (e) {
      debugPrint('❌ Step 3 (users) failed: $e');
      rethrow;
    }

    debugPrint('🎉 Onboarding complete — shopId: $shopId  owner: $ownerUid');
  }

  // ── Build the shop document ───────────────────────────────────────────────
  static Map<String, dynamic> _buildShopDoc({
    required String shopId,
    required String shopName,
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String plan,
    required String now,
  }) {
    return {
      'shopId':                 shopId,
      'shopName':               shopName,
      'ownerUid':               ownerUid,
      'ownerName':              ownerName,
      'ownerEmail':             ownerEmail,
      'phone':                  ownerPhone,
      'email':                  ownerEmail,
      'address':                '',
      'gstNumber':              '',
      'logoUrl':                '',
      'plan':                   plan,          // 'free' | 'pro' | 'enterprise'
      'isActive':               true,
      'darkMode':               false,
      'requireIntakePhoto':     false,
      'requireCompletionPhoto': false,
      'invoicePrefix':          'INV',
      'defaultTaxRate':         18.0,
      'defaultWarrantyDays':    30,
      'enabledPayments':        ['Cash', 'UPI (GPay/PhonePe)', 'Card', 'Wallet'],
      'workflowStages':         _defaultWorkflowStages(),
      'createdAt':              now,
      'settings': {
        'taxType':        'GST',
        'priceInclusive': false,
      },
    };
  }

  // ── Add a staff member ────────────────────────────────────────────────────
  static Future<void> addStaffMember({
    required String uid,
    required String shopId,
    required String displayName,
    required String email,
    required String phone,
    required String role,
    required String pin,
    String specialization = 'General',
  }) async {
    // Validate role against DB constraint before hitting the server
    const validRoles = {
      'super_admin', 'manager', 'technician',
      'cashier', 'reception', 'qc_staff', 'read_only',
    };
    if (!validRoles.contains(role)) {
      throw ArgumentError(
        'Invalid role "$role". Must be one of: ${validRoles.join(', ')}',
      );
    }

    final now = DateTime.now().toIso8601String();
    try {
      await SupabaseService().client.from('users').upsert(
        {
          'uid':              uid,
          'shopId':           shopId,
          'displayName':      displayName,
          'email':            email,
          'phone':            phone,
          'role':             role,
          'isOwner':          false,
          'isActive':         true,
          'biometricEnabled': false,
          'specialization':   specialization,
          'pin':              pin,
          'pin_hash':         '',
          'totalJobs':        0,
          'completedJobs':    0,
          'rating':           5.0,
          'joinedAt':         now,
          'lastLoginAt':      '',
          'createdAt':        now,
          'updatedAt':        now,
        },
        onConflict: 'uid',
      );
      debugPrint('✅ Staff added: $displayName ($role) → shop $shopId');
    } catch (e) {
      debugPrint('❌ Add staff failed: $e');
      rethrow;
    }
  }

  // ── Default workflow stages ───────────────────────────────────────────────
  static List<Map<String, String>> _defaultWorkflowStages() => [
    {'icon': '📥', 'title': 'Checked In',        'desc': 'Device received at counter'},
    {'icon': '🔍', 'title': 'Diagnosed',          'desc': 'Issue identified by technician'},
    {'icon': '⏳', 'title': 'Awaiting Approval',  'desc': 'Waiting for customer quote approval'},
    {'icon': '⚙️', 'title': 'In Repair',          'desc': 'Work currently being performed'},
    {'icon': '📦', 'title': 'Awaiting Parts',     'desc': 'Waiting for spare parts to arrive'},
    {'icon': '🧪', 'title': 'Quality Check',      'desc': 'Testing device after repair'},
    {'icon': '✅', 'title': 'Ready for Pickup',   'desc': 'Customer notified, device ready'},
    {'icon': '🎉', 'title': 'Delivered',           'desc': 'Device handed over to customer'},
    {'icon': '🚫', 'title': 'Cancelled',           'desc': 'Repair cancelled or rejected'},
  ];
}
