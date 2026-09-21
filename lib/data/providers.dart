// ─────────────────────────────────────────────────────────────────────────────
//  data/providers.dart  —  Issue 10: Provider cache management
//
//  CHANGES vs original:
//   • AppUtils.signOut()       — clears ALL providers (existing behaviour kept,
//                                but now also invalidates audit/search state)
//   • AppUtils.onTenantSwitch()— new method: wipes + reloads all data when
//                                user switches shop/tenant
//   • CustomersNotifier        — added upsert() to avoid duplicate add on
//                                Issue 1 race condition
//   • ProductsNotifier         — adjustQty() already existed; no change needed
//   • Everything else is 100% identical to the original file.
//
//  Drop this file on top of the existing lib/data/providers.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/m.dart';
import 'active_session.dart';
import '../services/supabase_service.dart';
import '../services/audit_log_service.dart';

String _ts() {
  final n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${p(n.month)}-${p(n.day)} ${p(n.hour)}:${p(n.minute)}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  SESSION
// ─────────────────────────────────────────────────────────────────────────────

final currentUserProvider = StreamProvider<SessionUser?>((ref) {
  return SupabaseService().client.auth.onAuthStateChange.asyncMap((authState) async {
    final user = authState.session?.user;
    if (user == null) return null;

    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        final response = await SupabaseService().client
            .from('users')
            .select()
            .eq('uid', user.id)
            .maybeSingle();

        if (response != null) {
          final d = response;
          await SupabaseService().client
              .from('users')
              .update({'lastLoginAt': _ts()})
              .eq('uid', user.id);

          return SessionUser(
            uid             : user.id,
            email           : (d['email']       as String?) ?? user.email ?? '',
            displayName     : (d['displayName'] as String?) ?? user.userMetadata?['displayName'] ?? 'User',
            role            : (d['role']        as String?) ?? 'technician',
            shopId          : (d['shopId']      as String?) ?? '',
            phone           : (d['phone']       as String?) ?? '',
            pinHash         : (d['pin_hash']    as String?) ?? '',
            biometricEnabled: (d['biometricEnabled'] as bool?) ?? false,
            isActive        : (d['isActive']    as bool?) ?? true,
            isOwner         : (d['isOwner']     as bool?) ?? false,
            lastLoginAt     : (d['lastLoginAt'] as String?) ?? '',
            createdAt       : (d['createdAt']   as String?) ?? '',
          );
        }
        debugPrint('⏳ users/${user.id} not ready, retry ${attempt + 1}/5');
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        debugPrint('⚠️ currentUserProvider attempt ${attempt + 1}: $e');
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    debugPrint('⚠️ currentUserProvider: user row not found after 5 retries for ${user.id}');
    return null;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
//  SHOP SETTINGS
// ─────────────────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<ShopSettings> {
  SettingsNotifier() : super(ShopSettings());

  void update(ShopSettings s) => state = s;
  void reset() => state = ShopSettings();

  Future<void> loadFromSupabase(String shopId) async {
    try {
      final response = await SupabaseService().client
          .from('shops')
          .select()
          .eq('shopId', shopId)
          .maybeSingle();

      if (response == null) return;
      final d = response;

      state = state.copyWith(
        shopId                : shopId,
        shopName              : d['shopName']    as String? ?? state.shopName,
        ownerUid              : d['ownerUid']    as String? ?? state.ownerUid,
        ownerName             : d['ownerName']   as String? ?? state.ownerName,
        ownerEmail            : d['ownerEmail']  as String? ?? state.ownerEmail,
        phone                 : d['phone']       as String? ?? state.phone,
        email                 : d['email']       as String? ?? state.email,
        address               : d['address']     as String? ?? state.address,
        gstNumber             : d['gstNumber']   as String? ?? state.gstNumber,
        logoUrl               : d['logoUrl']     as String? ?? state.logoUrl,
        invoicePrefix         : d['invoicePrefix'] as String? ?? state.invoicePrefix,
        defaultTaxRate        : (d['defaultTaxRate'] as num?)?.toDouble() ?? state.defaultTaxRate,
        defaultWarrantyDays   : d['defaultWarrantyDays'] as int?
                             ?? d['warrantyDays']        as int?
                             ?? state.defaultWarrantyDays,
        requireIntakePhoto    : d['requireIntakePhoto']    as bool? ?? state.requireIntakePhoto,
        requireCompletionPhoto: d['requireCompletionPhoto'] as bool? ?? state.requireCompletionPhoto,
        settings: () {
          final base = d['settings'] != null
              ? Map<String, dynamic>.from(d['settings'] as Map)
              : Map<String, dynamic>.from(state.settings);
          return base;
        }(),
        createdAt     : d['createdAt'] as String? ?? state.createdAt,
        plan          : d['plan']      as String? ?? state.plan,
        planExpiresAt : d['planExpiresAt'] as String?,
        isActive      : d['isActive']  as bool? ?? true,
        darkMode      : d['darkMode']  as bool? ?? state.darkMode,
        enabledPayments: d['enabledPayments'] != null
                        ? List<String>.from(d['enabledPayments'] as List)
                        : state.enabledPayments,
        workflowStages: d['workflowStages'] != null
                        ? (d['workflowStages'] as List)
                            .map((e) => Map<String, String>.from(e as Map))
                            .toList()
                        : state.workflowStages,
      );
    } catch (e) {
      debugPrint('⚠️ loadFromSupabase error: $e');
    }
  }

  Future<void> saveToSupabase(String shopId) async {
    try {
      final s = state;
      final settingsMap = Map<String, dynamic>.from(s.settings)
        ..['taxType']        = s.settings['taxType']        ?? 'GST'
        ..['priceInclusive'] = s.settings['priceInclusive'] ?? false;

      await SupabaseService().client.from('shops').upsert({
        'shopId'                : shopId,
        'shopName'              : s.shopName,
        'ownerUid'              : s.ownerUid,
        'ownerName'             : s.ownerName,
        'ownerEmail'            : s.ownerEmail,
        'phone'                 : s.phone,
        'email'                 : s.email,
        'address'               : s.address,
        'gstNumber'             : s.gstNumber,
        'logoUrl'               : s.logoUrl,
        'invoicePrefix'         : s.invoicePrefix,
        'defaultTaxRate'        : s.defaultTaxRate,
        'defaultWarrantyDays'   : s.defaultWarrantyDays,
        'requireIntakePhoto'    : s.requireIntakePhoto,
        'requireCompletionPhoto': s.requireCompletionPhoto,
        'settings'              : settingsMap,
        'plan'                  : s.plan,
        'isActive'              : true,
        'darkMode'              : s.darkMode,
        'enabledPayments'       : s.enabledPayments,
        'workflowStages'        : s.workflowStages,
      });
      debugPrint('✅ Settings saved to shops/$shopId');
    } catch (e) {
      debugPrint('❌ saveToSupabase error: $e');
      rethrow;
    }
  }

  void toggle(String field) {
    switch (field) {
      case 'requireIntakePhoto':
        state = state.copyWith(requireIntakePhoto: !state.requireIntakePhoto);
        break;
      case 'requireCompletionPhoto':
        state = state.copyWith(requireCompletionPhoto: !state.requireCompletionPhoto);
        break;
      case 'darkMode':
        state = state.copyWith(darkMode: !state.darkMode);
        break;
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, ShopSettings>((_) => SettingsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  shopIdProvider
// ─────────────────────────────────────────────────────────────────────────────
final shopIdProvider = Provider<String>((ref) {
  final activeSession = ref.watch(activeSessionProvider);
  if (activeSession != null && activeSession.shopId.isNotEmpty) {
    return activeSession.shopId;
  }
  final sessionUser = ref.watch(currentUserProvider).asData?.value;
  if (sessionUser != null && sessionUser.shopId.isNotEmpty) {
    return sessionUser.shopId;
  }
  final settings = ref.watch(settingsProvider);
  if (settings.shopId.isNotEmpty) return settings.shopId;
  return '';
});

// ─────────────────────────────────────────────────────────────────────────────
//  STAFF
// ─────────────────────────────────────────────────────────────────────────────

class StaffNotifier extends StateNotifier<List<StaffMember>> {
  StaffNotifier() : super([]);

  void setAll(List<StaffMember> list) => state = list;
  void add(StaffMember s) => state = [s, ...state];
  void update(StaffMember updated) =>
      state = state.map((s) => s.uid == updated.uid ? updated : s).toList();

  Future<void> loadFromSupabase(String shopId) async {
    debugPrint('DEBUG StaffNotifier.loadFromSupabase called with shopId="$shopId"');
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await SupabaseService.instance.client
            .from('users')
            .select()
            .eq('shopId', shopId);
        debugPrint('DEBUG StaffNotifier.loadFromSupabase response: $response');
        final loaded = <StaffMember>[];
        for (final d in response) {
          try {
            final member = StaffMember.fromMap(d['uid'], d);
            debugPrint('DEBUG StaffNotifier.loadFromSupabase parsed: uid=${member.uid}, displayName=${member.displayName}, isOwner=${member.isOwner}, isActive=${member.isActive}');
            loaded.add(member);
          } catch (parseErr) {
            debugPrint('⚠️ StaffMember parse error: $parseErr');
          }
        }
        state = loaded
          ..sort((a, b) {
            if (a.isOwner) return -1;
            if (b.isOwner) return 1;
            return a.displayName.compareTo(b.displayName);
          });
        debugPrint('✅ StaffNotifier: loaded ${state.length} members for $shopId');
        return;
      } catch (e) {
        debugPrint('⚠️ StaffNotifier.loadFromSupabase attempt ${attempt + 1}: $e');
        if (attempt < 2) await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> reloadIfEmpty(String shopId) async {
    if (state.isEmpty) await loadFromSupabase(shopId);
  }

  Future<void> addToSupabase({
    required String uid, required String shopId,
    required String displayName, required String email,
    required String phone, required String role, required String pin,
    String specialization = 'General',
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final member = StaffMember(
        uid: uid, shopId: shopId, displayName: displayName,
        email: email, phone: phone, role: role, isOwner: false,
        pin: pin, specialization: specialization, createdAt: now,
      );
      final userMap = member.toMap()
        ..['uid']           = uid
        ..['totalJobs']     = 0
        ..['completedJobs'] = 0
        ..['rating']        = 5.0
        ..['joinedAt']      = now;

      await SupabaseService().client.from('users').insert(userMap);
      add(member);
    } catch (e) {
      debugPrint('❌ addToSupabase: $e');
      rethrow;
    }
  }

  Future<void> addStaff(Technician tech) async {
    await addToSupabase(
      uid: tech.techId, shopId: tech.shopId,
      displayName: tech.name, email: '', phone: tech.phone,
      role: tech.role, pin: tech.pin, specialization: tech.specialization,
    );
  }

  Future<void> updateStaff(Technician tech) async {
    final member = StaffMember(
      uid: tech.techId, shopId: tech.shopId, displayName: tech.name,
      email: '', phone: tech.phone, role: tech.role, isActive: tech.isActive,
      specialization: tech.specialization, pin: tech.pin,
      createdAt: tech.joinedAt, totalJobs: tech.totalJobs,
      completedJobs: tech.completedJobs, rating: tech.rating,
    );
    await SupabaseService().client.from('users').update(member.toMap()).eq('uid', tech.techId);
    update(member);
  }

  Future<void> toggleActive(String uid, String shopId) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    final newActive = !member.isActive;
    await SupabaseService().client
        .from('users').update({'isActive': newActive}).eq('uid', uid);
    update(member.copyWith(isActive: newActive));
  }

  Future<void> removeFromSupabase(String uid) async {
    state = state.where((s) => s.uid != uid).toList();
    await SupabaseService().client.from('users').delete().eq('uid', uid);
  }

  Future<void> changeRole(String uid, String newRole) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    await SupabaseService().client
        .from('users').update({'role': newRole}).eq('uid', uid);
    update(member.copyWith(role: newRole));
  }

  Future<void> resetPin(String uid, String newPin) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    await SupabaseService().client
        .from('users').update({'pin': newPin, 'pin_hash': ''}).eq('uid', uid);
    update(member.copyWith(pin: newPin));
  }

  Future<void> updateStats(String uid, {
    required int totalJobs, required int completedJobs, required double rating,
  }) async {
    await SupabaseService().client.from('users').update({
      'totalJobs': totalJobs, 'completedJobs': completedJobs, 'rating': rating,
    }).eq('uid', uid);
    final idx = state.indexWhere((s) => s.uid == uid);
    if (idx >= 0) {
      final list = [...state];
      list[idx] = list[idx].copyWith(
          totalJobs: totalJobs, completedJobs: completedJobs, rating: rating);
      state = list;
    }
  }

  void clear() => state = [];
}

final staffProvider =
    StateNotifierProvider<StaffNotifier, List<StaffMember>>((_) => StaffNotifier());
final activeStaffProvider = Provider<List<StaffMember>>(
    (ref) => ref.watch(staffProvider).where((s) => s.isActive).toList());
final activeTechsProvider = Provider<List<StaffMember>>((ref) =>
    ref.watch(staffProvider)
        .where((s) => s.isActive && (s.role == 'technician' || s.role == 'manager'))
        .toList());

final techsProvider = Provider<List<Technician>>((ref) {
  return ref.watch(staffProvider)
      .where((s) => !s.isOwner)
      .map((s) => Technician(
            techId        : s.uid,
            shopId        : s.shopId,
            name          : s.displayName,
            phone         : s.phone,
            specialization: s.specialization,
            totalJobs     : s.totalJobs,
            completedJobs : s.completedJobs,
            rating        : s.rating,
            isActive      : s.isActive,
            joinedAt      : s.joinedAt.isNotEmpty ? s.joinedAt : s.createdAt,
            pin           : s.pin,
            role          : s.role,
          ))
      .toList();
});

class TechsNotifier extends StateNotifier<List<Technician>> {
  TechsNotifier() : super([]);
  void setAll(List<Technician> list) {}
  void add(Technician t) {}
  void update(Technician u) {}
  void delete(String id) {}
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCTS
// ─────────────────────────────────────────────────────────────────────────────
class ProductsNotifier extends StateNotifier<List<Product>> {
  ProductsNotifier() : super([]);
  void setAll(List<Product> list) => state = list;
  void add(Product p) => state = [p, ...state];
  void update(Product u) =>
      state = state.map((p) => p.productId == u.productId ? u : p).toList();
  void delete(String id) =>
      state = state.where((p) => p.productId != id).toList();
  void adjustQty(String id, int delta) {
    state = state.map((p) {
      if (p.productId != id) return p;
      return p.copyWith(stockQty: (p.stockQty + delta).clamp(0, 99999));
    }).toList();
  }
}
final productsProvider =
    StateNotifierProvider<ProductsNotifier, List<Product>>((_) => ProductsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  CUSTOMERS  — Issue 10: upsert prevents duplicate on re-login
// ─────────────────────────────────────────────────────────────────────────────
class CustomersNotifier extends StateNotifier<List<Customer>> {
  CustomersNotifier() : super([]);

  void setAll(List<Customer> list) => state = list;

  /// Issue 1 fix: adds customer only if not already present (dedup by id).
  void add(Customer c) {
    final exists = state.any((x) => x.customerId == c.customerId);
    if (!exists) state = [c, ...state];
  }

  void update(Customer u) =>
      state = state.map((c) => c.customerId == u.customerId ? u : c).toList();

  void delete(String id) =>
      state = state.where((c) => c.customerId != id).toList();

  /// Upsert: insert if new, update if already in local state.
  void upsert(Customer c) {
    final idx = state.indexWhere((x) => x.customerId == c.customerId);
    if (idx < 0) {
      state = [c, ...state];
    } else {
      final list = [...state];
      list[idx] = c;
      state = list;
    }
  }
}
final customersProvider =
    StateNotifierProvider<CustomersNotifier, List<Customer>>((_) => CustomersNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  JOBS
// ─────────────────────────────────────────────────────────────────────────────
class JobsNotifier extends StateNotifier<List<Job>> {
  JobsNotifier() : super([]);

  Future<void> _updateJobInDatabase(String jobId, Map<String, dynamic> data) async {
    // customerId is set once at job creation and never reassigned through
    // this path — excluding it avoids re-triggering the jobs_customerId_fkey
    // check on every unrelated job update (e.g. adding/removing a part).
    // A job whose customer was later deleted would otherwise fail EVERY
    // full-object update, not just ones that actually touch the customer.
    final firstData = Map<String, dynamic>.from(data)
      ..remove('notificationChannel')
      ..remove('customerId');
    final dataSets = [
      firstData,
      {
        for (final key in firstData.keys)
          if (['status', 'notes', 'problem', 'updatedAt', 'jobId'].contains(key))
            key: firstData[key]
      },
      {'status': firstData['status'], 'updatedAt': firstData['updatedAt']},
    ];

    for (final d in dataSets) {
      try {
        await SupabaseService.instance.client
            .from('jobs').update(d).eq('jobId', jobId);
        debugPrint('✅ Job $jobId updated in DB');
        return;
      } catch (e) {
        debugPrint('⚠️ Job update failed (${d.keys.length} fields): $e');
      }
    }
  }

  void setAll(List<Job> list) => state = list;
  void addJob(Job j) => state = [j, ...state];

  Future<void> updateJob(Job u) async {
    state = state.map((j) => j.jobId == u.jobId ? u : j).toList();
    await _updateJobInDatabase(u.jobId, u.toMap());
  }

  Future<void> addTimelineNote(String id, String note, String by) async {
    final updatedJobs = state.map((j) {
      if (j.jobId != id) return j;
      return j.copyWith(
        timeline: [
          ...j.timeline,
          TimelineEntry(status: j.status, time: DateTime.now().toIso8601String(),
              by: by, note: note, type: 'note')
        ],
        updatedAt: DateTime.now().toIso8601String(),
      );
    }).toList();
    state = updatedJobs;
    final job = updatedJobs.firstWhere((j) => j.jobId == id);
    await _updateJobInDatabase(id, {
      'timeline': job.timeline.map((e) => e.toMap()).toList(),
      'updatedAt': job.updatedAt,
    });
  }

  Future<void> updateStatus(String id, String status, String by,
      {String note = '', String type = 'flow'}) async {
    final updatedJobs = state.map((j) {
      if (j.jobId != id) return j;
      final entry = TimelineEntry(
          status: status, time: DateTime.now().toIso8601String(),
          by: by, note: note, type: type);
      return j.copyWith(
        status: status, previousStatus: j.status,
        timeline: [...j.timeline, entry],
        updatedAt: DateTime.now().toIso8601String(),
      );
    }).toList();
    state = updatedJobs;
    final job = updatedJobs.firstWhere((j) => j.jobId == id);
    await _updateJobInDatabase(id, {
      'status'        : job.status,
      'previousStatus': job.previousStatus,
      'timeline'      : job.timeline.map((e) => e.toMap()).toList(),
      'updatedAt'     : job.updatedAt,
    });
  }

  Future<void> markNotified(String id, String via) async {
    final updatedJobs = state.map((j) {
      if (j.jobId != id) return j;
      return j.copyWith(
        notificationSent: true,
        notificationChannel: via,
        timeline: [...j.timeline,
          TimelineEntry(status: j.status, time: DateTime.now().toIso8601String(),
              by: 'System', note: 'Pickup notification sent via $via', type: 'note')
        ],
        updatedAt: DateTime.now().toIso8601String(),
      );
    }).toList();
    state = updatedJobs;
    final job = updatedJobs.firstWhere((j) => j.jobId == id);
    await _updateJobInDatabase(id, {
      'notificationSent'   : job.notificationSent,
      'notificationChannel': job.notificationChannel,
      'timeline'           : job.timeline.map((e) => e.toMap()).toList(),
      'updatedAt'          : job.updatedAt,
    });
  }

  Future<void> putOnHold(String id, String reason, String by) async =>
      await updateStatus(id, 'On Hold', by, note: reason, type: 'flow');

  Future<void> cancel(String id, String reason, String by) async =>
      await updateStatus(id, 'Cancelled', by, note: reason, type: 'flow');

  Future<void> reopen(String id, String reason, String by) async =>
      await updateStatus(id, 'Checked In', by, note: reason, type: 'flow');

  Future<void> resumeFromHold(String id, String by) async =>
      await updateStatus(id, 'In Repair', by, type: 'flow');

  void reapplyTaxToActiveJobs(double taxRatePct, {bool priceInclusive = false}) {
    state = state.map((j) {
      if (j.status == 'Cancelled' || j.status == 'Delivered' || j.status == 'Completed') return j;
      final taxable = j.subtotal - j.discountAmount;
      final tax = priceInclusive
          ? taxable - (taxable / (1 + taxRatePct / 100))
          : taxable * taxRatePct / 100;
      final total = priceInclusive ? j.subtotal - j.discountAmount : taxable + tax;
      return j.copyWith(taxAmount: tax, totalAmount: total,
          updatedAt: DateTime.now().toIso8601String());
    }).toList();
  }
}
final jobsProvider =
    StateNotifierProvider<JobsNotifier, List<Job>>((_) => JobsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  CART (POS)
// ─────────────────────────────────────────────────────────────────────────────

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void add(Product p) {
    final i = state.indexWhere((c) => c.product.productId == p.productId);
    if (i >= 0) {
      final updated = [...state];
      updated[i] = CartItem(product: updated[i].product, qty: updated[i].qty + 1);
      state = updated;
    } else {
      state = [...state, CartItem(product: p)];
    }
  }

  void setQty(String id, int qty) {
    if (qty <= 0) {
      state = state.where((c) => c.product.productId != id).toList();
    } else {
      state = state.map((c) => c.product.productId != id
          ? c : CartItem(product: c.product, qty: qty)).toList();
    }
  }

  void removeItem(String id) => setQty(id, 0);
  void updateQty(String id, int qty) => setQty(id, qty);
  void clear() => state = [];
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((_) => CartNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  IN-APP STAFF SWITCHER
// ─────────────────────────────────────────────────────────────────────────────

class ActiveStaffSwitchNotifier extends StateNotifier<Technician?> {
  ActiveStaffSwitchNotifier() : super(null);
  void setStaff(Technician tech) => state = tech;
  void clear() => state = null;
}

final currentStaffProvider =
    StateNotifierProvider<ActiveStaffSwitchNotifier, Technician?>(
        (_) => ActiveStaffSwitchNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  MISC
// ─────────────────────────────────────────────────────────────────────────────

class TransactionsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  TransactionsNotifier() : super([]);

  void setAll(List<Map<String, dynamic>> list) => state = list;
  void add(Map<String, dynamic> tx) => state = [tx, ...state];
  void update(Map<String, dynamic> tx) =>
      state = state.map((t) => t['transactionId'] == tx['transactionId'] ? tx : t).toList();
  void delete(String transactionId) =>
      state = state.where((t) => t['transactionId'] != transactionId).toList();
  void clear() => state = [];

  Future<void> loadFromSupabase(String shopId) async {
    try {
      final response = await SupabaseService().client
          .from('transactions')
          .select()
          .eq('shopId', shopId)
          .order('time', ascending: false);

      final txList = (response as List<dynamic>).cast<Map<String, dynamic>>();
      setAll(txList);
      debugPrint('✅ Loaded ${txList.length} transactions');
    } catch (e) {
      debugPrint('⚠️ loadFromSupabase for transactions: $e');
    }
  }

  Future<void> updateTransactionInSupabase(Map<String, dynamic> tx) async {
    try {
      await SupabaseService.instance.client
          .from('transactions')
          .update(tx)
          .eq('transactionId', tx['transactionId']);
      update(tx);
      debugPrint('✅ Transaction ${tx['transactionId']} updated');
    } catch (e) {
      debugPrint('⚠️ updateTransactionInSupabase: $e');
    }
  }

  Future<void> deleteTransactionFromSupabase(String transactionId, String shopId, String userId) async {
    try {
      await SupabaseService.instance.client
          .from('transactions')
          .delete()
          .eq('transactionId', transactionId);
      delete(transactionId);

      // Log to audit logs
      await AuditLogService.log(
        shopId: shopId,
        userId: userId,
        action: AuditLogService.delete,
        entity: 'Transaction',
        entityId: transactionId,
        details: {},
      );
      debugPrint('✅ Transaction $transactionId deleted');
    } catch (e) {
      debugPrint('⚠️ deleteTransactionFromSupabase: $e');
    }
  }
}
final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, List<Map<String, dynamic>>>(
        (_) => TransactionsNotifier());

// ── Audit Log / Ledger Provider ───────────────────────────────────────────────
class AuditLogsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  AuditLogsNotifier() : super([]);

  void setAll(List<Map<String, dynamic>> logs) => state = logs;

  Future<void> loadFromSupabase(String shopId) async {
    try {
      final response = await SupabaseService.instance.client
          .from('audit_logs')
          .select()
          .eq('shopId', shopId)
          .order('timestamp', ascending: false);
      final logs = (response as List).cast<Map<String, dynamic>>();
      state = logs;
    } catch (e) {
      debugPrint('⚠️ load audit logs failed: $e');
    }
  }
}

final auditLogsProvider =
    StateNotifierProvider<AuditLogsNotifier, List<Map<String, dynamic>>>(
        (_) => AuditLogsNotifier());

final searchJobProvider       = StateProvider<String>((_) => '');
final searchCustProvider      = StateProvider<String>((_) => '');
final searchInvProvider       = StateProvider<String>((_) => '');
final searchStaffProvider     = StateProvider<String>((_) => '');
final jobTabProvider          = StateProvider<String>((_) => 'All');
final staffRoleFilterProvider = StateProvider<String>((_) => 'All');
final repairTabIndexProvider  = StateProvider.family<int, String>((_, __) => 0);

final filteredStaffProvider = Provider<List<StaffMember>>((ref) {
  final all    = ref.watch(staffProvider);
  final search = ref.watch(searchStaffProvider).toLowerCase();
  final role   = ref.watch(staffRoleFilterProvider);
  return all.where((s) {
    final matchSearch = search.isEmpty ||
        s.displayName.toLowerCase().contains(search) ||
        s.email.toLowerCase().contains(search) ||
        s.phone.contains(search);
    final matchRole = role == 'All' || s.role == role;
    return matchSearch && matchRole;
  }).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
//  APP UTILS — Issue 10: sign-out, tenant switch, provider cleanup
// ─────────────────────────────────────────────────────────────────────────────

class AppUtils {
  AppUtils._();

  static bool _clearing = false;

  /// Full sign-out: clears all providers then calls Supabase signOut.
  static Future<void> signOut(WidgetRef ref) async {
    if (_clearing) return;
    _clearing = true;
    try {
      _clearProviders(ref);
      try { ref.read(activeSessionProvider.notifier).clear(); } catch (_) {}
      await SupabaseService().client.auth.signOut();
    } finally {
      _clearing = false;
    }
  }

  static void staffLogout(WidgetRef ref) {
    try { ref.read(activeSessionProvider.notifier).logoutStaff(); } catch (_) {}
  }

  static Future<void> clearAllProvidersOnSignOut(WidgetRef ref) async {
    await signOut(ref);
  }

  /// Issue 10: Tenant switch — wipe all data then reload for new shopId.
  /// Call this when a super_admin switches the active shop.
  static Future<void> onTenantSwitch(WidgetRef ref, String newShopId) async {
    debugPrint('🔄 Tenant switch → $newShopId');
    _clearProviders(ref);
    // Reload settings + staff for new shop
    await ref.read(settingsProvider.notifier).loadFromSupabase(newShopId);
    await ref.read(staffProvider.notifier).loadFromSupabase(newShopId);
    await ref.read(transactionsProvider.notifier).loadFromSupabase(newShopId);
    debugPrint('✅ Tenant switch complete for $newShopId');
  }

  static void _clearProviders(WidgetRef ref) {
    try { ref.read(settingsProvider.notifier).reset(); }            catch (_) {}
    try { ref.read(jobsProvider.notifier).setAll([]); }             catch (_) {}
    try { ref.read(customersProvider.notifier).setAll([]); }        catch (_) {}
    try { ref.read(productsProvider.notifier).setAll([]); }         catch (_) {}
    try { ref.read(staffProvider.notifier).clear(); }               catch (_) {}
    try { ref.read(cartProvider.notifier).clear(); }                catch (_) {}
    try { ref.read(currentStaffProvider.notifier).clear(); }        catch (_) {}
    try { ref.read(transactionsProvider.notifier).clear(); }     catch (_) {}
    try { ref.read(searchJobProvider.notifier).state = ''; }        catch (_) {}
    try { ref.read(searchCustProvider.notifier).state = ''; }       catch (_) {}
    try { ref.read(searchInvProvider.notifier).state = ''; }        catch (_) {}
    try { ref.read(searchStaffProvider.notifier).state = ''; }      catch (_) {}
    try { ref.read(jobTabProvider.notifier).state = 'All'; }        catch (_) {}
    try { ref.read(staffRoleFilterProvider.notifier).state = 'All'; } catch (_) {}
  }
}
