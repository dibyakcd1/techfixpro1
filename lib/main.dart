// ─────────────────────────────────────────────────────────────────────────────
//  main.dart
//
//  FIX: Added onAuthStateChange listener to _AuthGate.
//  When a new user clicks their verification email and the app opens,
//  AuthChangeEvent.signedIn fires with a real session.
//  PendingOnboardingService.run() then seeds registrations/shops/users
//  with an authenticated token — no more 401.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/t.dart';
import 'data/providers.dart';
import 'widgets/w.dart';
import 'models/m.dart';
import 'screens/dash.dart';
import 'screens/repairs.dart';
import 'screens/customers.dart';
import 'screens/inventory.dart';
import 'screens/pos.dart';
import 'screens/reports.dart';
import 'screens/settings.dart';
import 'screens/repair_detail.dart';
import 'screens/staff_lock_screen.dart';
import 'screens/auth_signup.dart';      // ← for PendingOnboardingService
import 'screens/auth_login.dart';       // ← redirect after seeding
import 'data/active_session.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseService().initialize();
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }
  runApp(const ProviderScope(child: TechFixApp()));
}

class TechFixApp extends ConsumerWidget {
  const TechFixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'TechFix Pro',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(false),  // Light theme
      darkTheme: buildTheme(true), // Dark theme
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _AuthGate
//  Listens to Supabase auth state changes.
//  On signedIn: runs pending onboarding (if any) then navigates.
//  On signedOut: nothing — your app uses the PIN activeSession for nav.
//
//  FIX: ownerUid and ownerShopId are now loaded from SharedPreferences so
//  StaffLockScreen receives real values instead of empty strings. Previously
//  the lock screen could never bootstrap staff or the owner sheet correctly.
// ─────────────────────────────────────────────────────────────────────────────
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  StreamSubscription<AuthState>? _authSub;
  bool _seedingInProgress = false;
  // FIX: store owner identity so StaffLockScreen can bootstrap correctly
  String _ownerUid    = '';
  String _ownerShopId = '';

  @override
  void initState() {
    super.initState();
    _authSub = SupabaseService().client.auth.onAuthStateChange.listen(_onAuthState);
    // Load persisted owner identity on cold start
    _loadOwnerIdentity();
  }

  Future<void> _loadOwnerIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var uid    = prefs.getString('ownerUid') ?? '';
      var shopId = prefs.getString('shopId') ?? '';
      debugPrint('DEBUG _AuthGate _loadOwnerIdentity: from prefs ownerUid="$uid", ownerShopId="$shopId"');
      
      // If prefs are empty but there's an active Supabase session, query users table!
      if ((uid.isEmpty || shopId.isEmpty)) {
        final currentUser = SupabaseService.instance.client.auth.currentUser;
        if (currentUser != null) {
          debugPrint('DEBUG _AuthGate _loadOwnerIdentity: active Supabase user found, querying users table...');
          final response = await SupabaseService.instance.client
              .from('users')
              .select('uid, shopId, isOwner')
              .eq('uid', currentUser.id)
              .maybeSingle();
          debugPrint('DEBUG _AuthGate _loadOwnerIdentity: users response=$response');
          if (response != null) {
            uid = response['uid'] as String? ?? '';
            shopId = response['shopId'] as String? ?? '';
            // Also, store it back to prefs!
            if (uid.isNotEmpty && shopId.isNotEmpty) {
              await prefs.setString('ownerUid', uid);
              await prefs.setString('shopId', shopId);
              debugPrint('DEBUG _AuthGate _loadOwnerIdentity: stored to prefs ownerUid="$uid", ownerShopId="$shopId"');
            }
          }
        }
      }

      if (mounted && (uid != _ownerUid || shopId != _ownerShopId)) {
        setState(() {
          _ownerUid    = uid;
          _ownerShopId = shopId;
        });
      }
    } catch (e) {
      debugPrint('DEBUG _AuthGate _loadOwnerIdentity error: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onAuthState(AuthState event) async {
    if (event.event != AuthChangeEvent.signedIn) return;
    final user = event.session?.user;
    if (user == null) return;

    // Refresh owner identity whenever Supabase fires a sign-in
    await _loadOwnerIdentity();

    final hasPending = await PendingOnboardingService.hasPending();
    if (!hasPending) return;

    if (_seedingInProgress) return;
    _seedingInProgress = true;

    try {
      debugPrint('🌱 Seeding shop data for new owner ${user.id}...');
      await PendingOnboardingService.run(user.id, ref);
      debugPrint('✅ Shop data seeded successfully');

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      debugPrint('❌ Seeding failed: $e');
    } finally {
      _seedingInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = ref.watch(activeSessionProvider);

    // FIX: keep owner identity in sync with activeSession when available
    if (activeSession != null) {
      if (activeSession.uid.isNotEmpty && activeSession.uid != _ownerUid) {
        _ownerUid = activeSession.uid;
      }
      if (activeSession.shopId.isNotEmpty && activeSession.shopId != _ownerShopId) {
        _ownerShopId = activeSession.shopId;
      }
    }

    if (activeSession == null) {
      // FIX: pass real ownerUid and ownerShopId so StaffLockScreen can
      // load staff and the owner access sheet works correctly.
      return StaffLockScreen(
        ownerUid:    _ownerUid,
        ownerShopId: _ownerShopId,
      );
    }
    return const RootShell();
  }
}

// ═══════════════════════════════════════════════════════════════
//  ROOT SHELL – bottom nav + indexed stack
// ═══════════════════════════════════════════════════════════════
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _idx = 0;
  bool _initialized = false;
  String? _cachedShopId;

  @override
  void initState() {
    super.initState();
    _loadCachedShop();
  }

  Future<void> _loadCachedShop() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('shopId');
      if (mounted) setState(() => _cachedShopId = id);
    } catch (_) {}
  }

  static const _navItems = [
    _NavItem(index: 0, icon: Icons.home_outlined,         activeIcon: Icons.home,            label: 'Home'),
    _NavItem(index: 1, icon: Icons.build_outlined,        activeIcon: Icons.build,           label: 'Repairs'),
    _NavItem(index: 2, icon: Icons.people_outline,        activeIcon: Icons.people,          label: 'Customers'),
    _NavItem(index: 4, icon: Icons.point_of_sale_outlined, activeIcon: Icons.point_of_sale,  label: 'POS'),
    _NavItem(index: -1, icon: Icons.menu,                 activeIcon: Icons.menu_open,       label: 'More'),
  ];

  Future<void> _initAppData(String shopId) async {
    if (_initialized) return;
    try {
      final supabase = SupabaseService().client;

      // Real-time settings listener
      supabase.from('shops').stream(primaryKey: ['shopId']).eq('shopId', shopId).listen((event) {
        if (event.isNotEmpty) {
          final data = event.first;
          ref.read(settingsProvider.notifier).update(
            ref.read(settingsProvider).copyWith(
              shopId: shopId,
              shopName: data['shopName'] as String? ?? data['name'] as String? ?? 'TechFix Pro',
              ownerName: data['ownerName'] as String? ?? data['owner'] as String? ?? 'Admin',
              email: data['email'] as String? ?? '',
              phone: data['phone'] as String? ?? '',
              address: data['address'] as String? ?? '',
              gstNumber: data['gstNumber'] as String? ?? '',
              invoicePrefix: data['invoicePrefix'] as String? ?? 'INV',
              defaultTaxRate: (data['defaultTaxRate'] as num?)?.toDouble() ?? 18.0,
              darkMode: data['darkMode'] as bool? ?? true,
              requireIntakePhoto: data['requireIntakePhoto'] as bool? ?? false,
              requireCompletionPhoto: data['requireCompletionPhoto'] as bool? ?? false,
            ),
          );
        }
      });

      // Real-time staff listener
      supabase.from('users').stream(primaryKey: ['uid']).eq('shopId', shopId).listen((event) {
        final techs = <Technician>[];
        for (final data in event) {
          final isOwner = (data['isOwner'] as bool?) ?? false;
          if (isOwner) continue;
          techs.add(Technician(
            techId: data['uid'] as String,
            shopId: shopId,
            name: (data['displayName'] as String?) ?? (data['name'] as String?) ?? '',
            phone: (data['phone'] as String?) ?? '',
            specialization: (data['specialization'] as String?) ?? 'General',
            isActive: (data['isActive'] as bool?) ?? true,
            totalJobs: (data['totalJobs'] as int?) ?? (data['jobs'] as int?) ?? 0,
            rating: (data['rating'] as num?)?.toDouble() ?? 5.0,
            pin: (data['pin'] as String?) ?? '',
            joinedAt: (data['createdAt'] as String?) ?? (data['joinedAt'] as String?) ?? DateTime.now().toIso8601String(),
            role: (data['role'] as String?) ?? 'technician',
          ));
        }
        techs.sort((a, b) => a.name.compareTo(b.name));
        final staff = techs.map((t) => StaffMember(
          uid: t.techId,
          shopId: t.shopId,
          displayName: t.name,
          email: '',
          phone: t.phone,
          role: t.role,
          isOwner: false,
          isActive: t.isActive,
          biometricEnabled: false,
          specialization: t.specialization,
          pin: t.pin,
          lastLoginAt: '',
          createdAt: t.joinedAt,
          joinedAt: t.joinedAt,
          totalJobs: t.totalJobs,
          completedJobs: t.completedJobs,
          rating: t.rating,
        )).toList();
        ref.read(staffProvider.notifier).setAll(staff);
      });

      // Real-time products listener
      supabase.from('products').stream(primaryKey: ['productId']).eq('shopId', shopId).listen((event) {
        final products = <Product>[];
        for (final data in event) {
          products.add(Product(
            productId: data['productId'] as String,
            shopId: shopId,
            sku: (data['sku'] as String?) ?? '',
            productName: (data['productName'] as String?) ?? (data['name'] as String?) ?? '',
            category: (data['category'] as String?) ?? 'Accessories',
            brand: (data['brand'] as String?) ?? '',
            description: (data['description'] as String?) ?? '',
            supplierName: (data['supplierName'] as String?) ?? (data['supplier'] as String?) ?? '',
            costPrice: (data['costPrice'] as num?)?.toDouble() ?? 0,
            sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ?? 0,
            stockQty: (data['stockQty'] as int?) ?? 0,
            reorderLevel: (data['reorderLevel'] as int?) ?? 5,
            isActive: (data['isActive'] as bool?) ?? true,
            imageUrl: (data['imageUrl'] as String?) ?? '',
            createdAt: (data['createdAt'] as String?) ?? '',
            updatedAt: (data['updatedAt'] as String?) ?? '',
          ));
        }
        ref.read(productsProvider.notifier).setAll(products);
      });

      // Real-time jobs listener
      supabase.from('jobs').stream(primaryKey: ['jobId']).eq('shopId', shopId).listen((event) {
        final jobs = <Job>[];
        for (final data in event) {
          jobs.add(Job.fromMap(data));
        }
        jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        ref.read(jobsProvider.notifier).setAll(jobs);
      });

      // Real-time customers listener
      supabase.from('customers').stream(primaryKey: ['customerId']).eq('shopId', shopId).listen((event) {
        final customers = <Customer>[];
        for (final data in event) {
          customers.add(Customer.fromMap(data));
        }
        ref.read(customersProvider.notifier).setAll(customers);
      });

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('Error initializing app data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme     = ref.watch(appThemeProvider);
    final userAsync    = ref.watch(currentUserProvider);
    final session      = userAsync.asData?.value;
    // FIX: watch activeSessionProvider so data loads on staff PIN login too.
    // Previously only currentUserProvider was checked, but staff PIN login
    // does not change Supabase auth — only activeSessionProvider.
    final activeSession = ref.watch(activeSessionProvider);

    if (!_initialized) {
      // Priority: activeSession (PIN login) > Supabase session > cached prefs
      final shopId = activeSession?.shopId.isNotEmpty == true
          ? activeSession!.shopId
          : session?.shopId.isNotEmpty == true
              ? session!.shopId
              : (_cachedShopId ?? '');
      if (shopId.isNotEmpty) {
        _initAppData(shopId);
      }
    }

    final jobs     = ref.watch(jobsProvider);
    final overdue  = jobs.where((j) => j.isOverdue).length;
    final ready    = jobs.where((j) => j.status == 'Ready for Pickup').length;
    final onHold   = jobs.where((j) => j.isOnHold).length;
    final settings = ref.watch(settingsProvider);
    final cart     = ref.watch(cartProvider);
    final cartCount = cart.fold<int>(0, (s, c) => s + c.qty);

    final screens = <Widget>[
      DashScreen(
        onRepairs: () => setState(() => _idx = 1),
        onInventory: () => setState(() => _idx = 3),
        onOpenJob: (jobId) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RepairDetailScreen(jobId: jobId)),
          );
        },
      ),
      const RepairsScreen(),
      const CustomersScreen(),
      const InventoryScreen(),
      const POSScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    final shopName   = settings.shopName.isEmpty ? 'TechFix Pro' : settings.shopName;
    final appBarTitle = switch (_idx) {
      0 => shopName, 1 => 'Repairs', 2 => 'Customers',
      3 => 'Inventory', 4 => 'POS', 5 => 'Reports', 6 => 'Settings',
      _ => shopName,
    };

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [C.primary, C.primaryDark],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('T', style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w900, fontSize: 18, color: C.bg)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(appBarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ]),
        actions: [
          if (overdue > 0)
            _AppBarBadge(icon: '⏰', count: overdue, color: C.red,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'Active';
                }),
          if (onHold > 0)
            _AppBarBadge(icon: '⏸️', count: onHold, color: C.yellow,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'On Hold';
                }),
          if (ready > 0)
            _AppBarBadge(icon: '✅', count: ready, color: C.green,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'Ready';
                }),
          if (_idx == 4)
            _CartAction(count: cartCount, onTap: () => _openCart(cart)),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _idx, children: screens),
      bottomNavigationBar: _buildBottomNav(),
      endDrawer: _CartDrawer(onGoToPos: _goToPosFromCart),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: C.bgElevated,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.map((item) {
              final sel = item.index >= 0
                  ? _idx == item.index
                  : _idx == 3 || _idx == 5 || _idx == 6;
              return GestureDetector(
                onTap: () {
                  if (item.index >= 0) {
                    setState(() => _idx = item.index);
                  } else {
                    _openMoreSheet();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? C.primary.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(sel ? item.activeIcon : item.icon,
                        color: sel ? C.primary : C.textDim, size: 22),
                    const SizedBox(height: 3),
                    Text(item.label, style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                        color: sel ? C.primary : C.textDim,
                        letterSpacing: 0.2)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _openMoreSheet() {
    // Get theme colors here (before builder context)
    final theme = ref.read(appThemeProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.bgElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.inventory_2_outlined, color: theme.text),
              title: Text('Stock', style: TextStyle(color: theme.text)),
              onTap: () { setState(() => _idx = 3); Navigator.of(ctx).pop(); },
            ),
            ListTile(
              leading: Icon(Icons.bar_chart_outlined, color: theme.text),
              title: Text('Reports', style: TextStyle(color: theme.text)),
              onTap: () { setState(() => _idx = 5); Navigator.of(ctx).pop(); },
            ),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: theme.text),
              title: Text('Settings', style: TextStyle(color: theme.text)),
              onTap: () { setState(() => _idx = 6); Navigator.of(ctx).pop(); },
            ),
            Divider(color: theme.border, height: 1),
            ListTile(
              leading: Icon(Icons.settings_outlined, color: theme.textMuted),
              title: Text('Sign out of role', style: GoogleFonts.inter(color: theme.textMuted)),
              subtitle: Text('Go to Settings → Sign Out',
                  style: GoogleFonts.inter(fontSize: 11, color: theme.textDim)),
              onTap: () { Navigator.of(ctx).pop(); setState(() => _idx = 6); },
            ),
          ],
        ),
      ),
    );
  }

  void _goToPosFromCart() {
    Navigator.of(context).maybePop();
    setState(() => _idx = 4);
  }

  void _openCart(List<CartItem> cart) {
    final width = MediaQuery.of(context).size.width;
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cart is empty',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: C.bgElevated,
      ));
      return;
    }
    if (width < 700) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CartSheet(onGoToPos: _goToPosFromCart),
      );
    } else {
      Scaffold.of(context).openEndDrawer();
    }
  }
}

class _NavItem {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.index, required this.icon,
      required this.activeIcon, required this.label});
}

class _AppBarBadge extends StatelessWidget {
  final String icon;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _AppBarBadge({required this.icon, required this.count,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text('$count', style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      ]),
    ),
  );
}

class _CartAction extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CartAction({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasItems = count > 0;
    return Semantics(
      label: hasItems ? 'Cart, $count item(s)' : 'Cart, empty',
      button: true,
      child: IconButton(
        onPressed: onTap,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.shopping_cart_outlined, color: C.textDim),
            if (hasItems)
              Positioned(
                right: -2, top: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: C.primary, borderRadius: BorderRadius.circular(99)),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text(count > 99 ? '99+' : '$count',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9, fontWeight: FontWeight.w800, color: C.bg)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartDrawer extends ConsumerWidget {
  final VoidCallback onGoToPos;
  const _CartDrawer({required this.onGoToPos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart  = ref.watch(cartProvider);
    final total = cart.fold<double>(0, (s, c) => s + c.product.sellingPrice * c.qty);
    return Drawer(
      backgroundColor: C.bgElevated,
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cart', style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
                      IconButton(
                          icon: const Icon(Icons.close, color: C.textDim),
                          onPressed: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (cart.isEmpty)
                    Expanded(child: Center(
                      child: Text('Your cart is empty',
                          style: GoogleFonts.inter(fontSize: 13, color: C.textMuted)),
                    ))
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: cart.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = cart[i];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: C.bgCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: C.border),
                            ),
                            child: Row(children: [
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.productName,
                                      style: GoogleFonts.inter(fontSize: 13,
                                          fontWeight: FontWeight.w600, color: C.text),
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('${fmtMoney(item.product.sellingPrice)} each',
                                      style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
                                ],
                              )),
                              const SizedBox(width: 8),
                              Row(children: [
                                IconButton(
                                  onPressed: () => ref.read(cartProvider.notifier)
                                      .setQty(item.product.productId, item.qty - 1),
                                  icon: const Icon(Icons.remove, size: 18, color: C.textDim),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text('${item.qty}', style: GoogleFonts.inter(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: C.white)),
                                ),
                                IconButton(
                                  onPressed: () => ref.read(cartProvider.notifier)
                                      .updateQty(item.product.productId, item.qty + 1),
                                  icon: const Icon(Icons.add, size: 18, color: C.textDim),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                              ]),
                              const SizedBox(width: 12),
                              Text(fmtMoney(item.product.sellingPrice * item.qty),
                                  style: GoogleFonts.inter(fontSize: 13,
                                      fontWeight: FontWeight.w700, color: C.primary)),
                              IconButton(
                                onPressed: () => ref.read(cartProvider.notifier)
                                    .setQty(item.product.productId, 0),
                                icon: const Icon(Icons.close, size: 18, color: C.textDim),
                                padding: const EdgeInsets.only(left: 4),
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  if (cart.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
                        Text(fmtMoney(total), style: GoogleFonts.plusJakartaSans(
                            fontSize: 16, fontWeight: FontWeight.w800, color: C.green)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PBtn(label: 'Go to POS', onTap: onGoToPos, full: true, color: C.primary),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: C.bgElevated,
                            title: Text('Clear cart?', style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800, color: C.white)),
                            content: Text('This will remove all items from the cart.',
                                style: GoogleFonts.inter(color: C.textMuted, fontSize: 13)),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text('Cancel',
                                      style: GoogleFonts.inter(color: C.textMuted))),
                              TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: Text('Clear', style: GoogleFonts.inter(
                                      color: C.red, fontWeight: FontWeight.w700))),
                            ],
                          ),
                        );
                        if (confirm == true) ref.read(cartProvider.notifier).clear();
                      },
                      child: Text('Clear cart', style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600, color: C.textMuted)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartSheet extends ConsumerWidget {
  final VoidCallback onGoToPos;
  const _CartSheet({required this.onGoToPos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart  = ref.watch(cartProvider);
    final total = cart.fold<double>(0, (s, c) => s + c.product.sellingPrice * c.qty);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: C.bgElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cart', style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w800, color: C.white)),
                  IconButton(
                      icon: const Icon(Icons.close, color: C.textDim),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 8),
              if (cart.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text('Your cart is empty',
                      style: GoogleFonts.inter(fontSize: 13, color: C.textMuted)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = cart[i];
                      return Row(children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.productName,
                                style: GoogleFonts.inter(fontSize: 13,
                                    fontWeight: FontWeight.w600, color: C.text),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('${fmtMoney(item.product.sellingPrice)} each',
                                style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Row(children: [
                          IconButton(
                            onPressed: () => ref.read(cartProvider.notifier)
                                .setQty(item.product.productId, item.qty - 1),
                            icon: const Icon(Icons.remove, size: 18, color: C.textDim),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text('${item.qty}', style: GoogleFonts.inter(
                                fontSize: 12, fontWeight: FontWeight.w700, color: C.white)),
                          ),
                          IconButton(
                            onPressed: () => ref.read(cartProvider.notifier)
                                .setQty(item.product.productId, item.qty + 1),
                            icon: const Icon(Icons.add, size: 18, color: C.textDim),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          ),
                        ]),
                        const SizedBox(width: 12),
                        Text(fmtMoney(item.product.sellingPrice * item.qty),
                            style: GoogleFonts.inter(fontSize: 13,
                                fontWeight: FontWeight.w700, color: C.primary)),
                        IconButton(
                          onPressed: () => ref.read(cartProvider.notifier)
                              .setQty(item.product.productId, 0),
                          icon: const Icon(Icons.close, size: 18, color: C.textDim),
                          padding: const EdgeInsets.only(left: 4),
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ]);
                    },
                  ),
                ),
              if (cart.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
                    Text(fmtMoney(total), style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w800, color: C.green)),
                  ],
                ),
                const SizedBox(height: 12),
                PBtn(label: 'Go to POS', onTap: onGoToPos, full: true, color: C.primary),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: C.bgElevated,
                        title: Text('Clear cart?', style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800, color: C.white)),
                        content: Text('This will remove all items from the cart.',
                            style: GoogleFonts.inter(color: C.textMuted, fontSize: 13)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text('Cancel',
                                  style: GoogleFonts.inter(color: C.textMuted))),
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: Text('Clear', style: GoogleFonts.inter(
                                  color: C.red, fontWeight: FontWeight.w700))),
                        ],
                      ),
                    );
                    if (confirm == true) ref.read(cartProvider.notifier).clear();
                  },
                  child: Text('Clear cart', style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600, color: C.textMuted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
