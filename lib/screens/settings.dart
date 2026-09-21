import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../services/supabase_service.dart';
import '../services/inventory_repair_service.dart';
import 'transaction_history.dart';

Future<void> _shopSave(BuildContext context, WidgetRef ref,
    Future<void> Function() fn, {String successMsg = '✅ Saved'}) async {
  try {
    await fn();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(successMsg, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: C.green, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
    }
  } catch (e) {
    final msg = e.toString().replaceAll('Exception: ', '');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ ${msg.length > 110 ? msg.substring(0,110) : msg}',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
        backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5)));
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CONSISTENT PAGE SCAFFOLD
// ─────────────────────────────────────────────────────────────
class _Page extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? fab;
  final List<Widget>? actions;

  const _Page({
    required this.title,
    this.subtitle,
    required this.children,
    this.fab,
    this.actions,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    appBar: AppBar(
      backgroundColor: C.bgElevated,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
          if (subtitle != null)
            Text(subtitle!, style: GoogleFonts.inter(
                fontSize: 11, color: C.textMuted)),
        ],
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: C.border),
      ),
    ),
    floatingActionButton: fab,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: children,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Consistent Save Button with loading state
// ─────────────────────────────────────────────────────────────
class _SaveBtn extends StatefulWidget {
  final VoidCallback onSave;
  final String label;
  const _SaveBtn({required this.onSave, this.label = '💾  Save Changes'});

  @override
  State<_SaveBtn> createState() => _SaveBtnState();
}

class _SaveBtnState extends State<_SaveBtn> {
  bool _loading = false;
  bool _done = false;

  Future<void> _handle() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onSave();
    setState(() { _loading = false; _done = true; });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: _loading ? null : _handle,
      style: ElevatedButton.styleFrom(
        backgroundColor: _done ? C.green : C.primary,
        foregroundColor: C.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: _loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
          : Text(_done ? '✅  Saved!' : widget.label,
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Consistent info banner
// ─────────────────────────────────────────────────────────────
Widget _infoBanner(String text, {Color color = C.primary}) => Container(
  padding: const EdgeInsets.all(12),
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withValues(alpha: 0.3)),
  ),
  child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: color, height: 1.5)),
);

// ─────────────────────────────────────────────────────────────
// MAIN SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final userAsync = ref.watch(currentUserProvider);
    final session = userAsync.asData?.value;
    // Role comes from activeSessionProvider (who is operating NOW),
    // NOT from currentUserProvider (which is always the Firebase owner account).
    final activeSession = ref.watch(activeSessionProvider);
    final role = activeSession?.role ?? session?.role ?? 'technician';
    final isOwner = activeSession?.isOwner ?? session?.isOwner ?? false;
    final isAdmin = role == 'admin';
    final isManager = role == 'manager';
    final isReception = role == 'reception';
    final isTechnician = role == 'technician';
    final canManageShopSettings = isOwner || isAdmin || isManager;
    final canSeeUserRoles = isOwner || isAdmin || isManager;
    final roleLabel = isOwner
        ? 'Owner'
        : isAdmin
            ? 'Admin'
            : isManager
                ? 'Manager'
                : isReception
                    ? 'Reception'
                    : isTechnician
                        ? 'Technician'
                        : 'Staff';

    if (session != null && session.shopId.isNotEmpty && s.shopId != session.shopId) {
      ref.read(settingsProvider.notifier).loadFromSupabase(session.shopId);
    }

    void go(Widget page) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: C.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── Profile card ─────────────────────────────────────
          GestureDetector(
            onTap: () => go(const ShopProfilePage()),
            child: SCard(
              glowColor: C.primary,
              child: Row(children: [
                Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [C.primary, C.primaryDark],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(
                        color: C.primary.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: Center(child: Text(
                    (() {
                      final name = activeSession?.displayName.isNotEmpty == true
                          ? activeSession!.displayName : s.ownerName;
                      return (name.isEmpty ? 'A' : name[0]).toUpperCase();
                    })(),
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900,
                        fontSize: 24, color: C.bg),
                  )),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    activeSession?.displayName.isNotEmpty == true
                        ? activeSession!.displayName
                        : s.ownerName.isEmpty ? 'Admin User' : s.ownerName,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800,
                        fontSize: 17, color: C.white)),
                  Text(s.shopName.isEmpty ? 'TechFix Pro' : s.shopName,
                      style: GoogleFonts.inter(fontSize: 13, color: C.primary)),
                  Text(s.email.isEmpty ? 'Tap to set up profile →' : s.email,
                      style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                  const SizedBox(height: 6),
                  Pill(roleLabel, small: true),
                ])),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: C.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.edit_outlined, color: C.primary, size: 18),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Quick toggles ────────────────────────────────────
          SettingsGroup(title: 'QUICK CONTROLS', tiles: [
            SettingsTile(
              icon: '🌙', title: 'Dark Mode',
              subtitle: s.darkMode ? 'Currently using dark theme' : 'Currently using light theme',
              trailing: Switch(value: s.darkMode,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('darkMode')),
            ),
            SettingsTile(
              icon: '📸', title: 'Require Intake Photos',
              subtitle: s.requireIntakePhoto ? 'Mandatory at job check-in' : 'Optional at check-in',
              trailing: Switch(value: s.requireIntakePhoto,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('requireIntakePhoto')),
            ),
            SettingsTile(
              icon: '🏁', title: 'Require Completion Photos',
              subtitle: s.requireCompletionPhoto ? 'Mandatory before pickup' : 'Optional before pickup',
              trailing: Switch(value: s.requireCompletionPhoto,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('requireCompletionPhoto')),
            ),
          ]),

          if (canManageShopSettings)
            SettingsGroup(title: 'SHOP', tiles: [
              SettingsTile(icon: '🏪', title: 'Shop Profile',
                  subtitle: s.shopName.isEmpty ? 'Not configured' : s.shopName,
                  onTap: () => go(const ShopProfilePage())),
              SettingsTile(icon: '🧾', title: 'Invoice & Receipts',
                  subtitle: 'Prefix: ${s.invoicePrefix}  ·  Format & logo',
                  onTap: () => go(const InvoicePage())),
              SettingsTile(icon: '📊', title: 'Tax & GST',
                  subtitle: 'Default rate: ${s.defaultTaxRate.toStringAsFixed(0)}%',
                  onTap: () => go(const TaxPage())),
              SettingsTile(icon: '💳', title: 'Payment Methods',
                  subtitle: 'Cash, Card, UPI, Wallet',
                  onTap: () => go(const PaymentMethodsPage())),
            ]),

          SettingsGroup(title: 'TEAM & WORKFLOW', tiles: [
            SettingsTile(icon: '👨‍🔧', title: 'Staff',
                subtitle: '${ref.watch(techsProvider).where((t) => t.isActive).length} active team members',
                onTap: () => go(const StaffPage())),
            if (!isTechnician)
              SettingsTile(icon: '🔄', title: 'Repair Workflow',
                  subtitle: '9 stages from check-in to completion',
                  onTap: () => go(const WorkflowPage())),
            if (!isTechnician)
              SettingsTile(icon: '🛡️', title: 'Warranty Rules',
                  subtitle: 'Default: ${s.defaultWarrantyDays} days post-repair',
                  onTap: () => go(const WarrantyPage())),
            if (canSeeUserRoles)
              SettingsTile(icon: '👥', title: 'User Roles & Access',
                  subtitle: 'Staff permissions and PIN access',
                  onTap: () => go(const UserRolesPage())),
          ]),

          // ── Notifications ────────────────────────────────────
          SettingsGroup(title: 'NOTIFICATIONS', tiles: [
            SettingsTile(icon: '💬', title: 'WhatsApp Business',
                subtitle: 'API key & message templates',
                onTap: () => go(const WhatsappPage())),
            SettingsTile(icon: '📱', title: 'SMS Gateway',
                subtitle: 'Twilio / MSG91 configuration',
                onTap: () => go(const SmsPage())),
            SettingsTile(icon: '🔔', title: 'Push Notifications',
                subtitle: 'Overdue alerts, low stock warnings',
                onTap: () => go(const PushNotifPage())),
            SettingsTile(icon: '📧', title: 'Email Settings',
                subtitle: 'SMTP configuration & templates',
                onTap: () => go(const EmailPage())),
          ]),

          // ── Integrations ─────────────────────────────────────
          SettingsGroup(title: 'INTEGRATIONS', tiles: [
            SettingsTile(icon: '💳', title: 'Payment Gateway',
                subtitle: 'Razorpay / Stripe / PayTM',
                onTap: () => go(const PaymentGatewayPage())),
            SettingsTile(icon: '📚', title: 'Accounting Export',
                subtitle: 'Tally, Zoho Books, QuickBooks',
                onTap: () => go(const AccountingPage())),
            SettingsTile(icon: '📦', title: 'Supplier Integration',
                subtitle: 'Auto-reorder on low stock',
                onTap: () => go(const SupplierPage())),
            SettingsTile(icon: '🤖', title: 'AI Diagnostics',
                subtitle: 'Claude AI for repair suggestions',
                onTap: () => go(const AiPage())),
          ]),

          // ── Data & Security ────────────────────────────────────
          SettingsGroup(title: 'DATA & SECURITY', tiles: [
            SettingsTile(icon: '🔒', title: 'App Lock & Biometrics',
                subtitle: 'PIN, fingerprint, Face ID',
                onTap: () => go(const AppLockPage())),
            if (session != null && session.isOwner)
              SettingsTile(icon: '💳', title: 'Transaction History',
                  subtitle: 'View and edit all transactions',
                  onTap: () => go(const TransactionHistoryScreen())),
            if (session != null && session.isOwner)
              SettingsTile(icon: '📋', title: 'Audit Logs',
                  subtitle: 'Full activity & change history',
                  onTap: () => go(const AuditLogsPage())),
            SettingsTile(icon: '☁️', title: 'Cloud Backup',
                subtitle: 'Auto-backup & restore',
                onTap: () => go(const BackupPage())),
            SettingsTile(icon: '📤', title: 'Export Data',
                subtitle: 'CSV / Excel / PDF reports',
                onTap: () => go(const ExportPage())),
            if (isAdmin || role == 'admin' || role == 'manager')
            SettingsTile(icon: '🧪', title: 'Demo Data Tools',
                subtitle: 'Seed or clear demo data for this shop',
                onTap: () => go(const DemoDataPage())),
          ]),

          // ── About ────────────────────────────────────────────
          SettingsGroup(title: 'ABOUT', tiles: [
            SettingsTile(icon: '📄', title: 'Terms & Privacy Policy',
                subtitle: 'Legal information', onTap: () => _showInfoDialog(context,
                    'Terms & Privacy Policy',
                    'TechFix Pro stores all data locally on your device. '
                    'No data is sent to third parties without your explicit consent. '
                    'By using this app you agree to these terms.')),
            SettingsTile(icon: '💡', title: 'Send Feedback',
                subtitle: 'Help us improve the app',
                onTap: () => _showInfoDialog(context, 'Send Feedback',
                    'Email your feedback to: feedback@techfixpro.app\n'
                    'We read every message and aim to respond within 48 hours.')),
            const SettingsTile(icon: '📱', title: 'App Version',
                subtitle: 'v3.0.0  ·  Build 2025.02'),
          ]),

          // ── Sign out — role session only ─────────────────────
          // Logs out of the current role → back to staff PIN screen.
          // Firebase stays connected. DB streams stay live.
          // To sign out from Firebase, use the hidden admin screen (5-tap logo).
          GestureDetector(
            onTap: () => _confirmRoleSignOut(context, ref),
            child: SCard(
              borderColor: C.yellow.withValues(alpha: 0.3),
              child: Row(children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: C.yellow.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Center(child: Text('🔄', style: TextStyle(fontSize: 20)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Sign Out', style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 15, color: C.yellow)),
                  Text('Log out of current role  ·  Returns to staff PIN screen',
                      style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Center(child: Text('TechFix Pro v3.0  ·  Made with ❤️ in India',
              style: GoogleFonts.inter(fontSize: 11, color: C.textDim))),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String body) =>
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800, color: C.white)),
        content: Text(body, style: GoogleFonts.inter(
            fontSize: 13, color: C.textMuted, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.inter(
                color: C.primary, fontWeight: FontWeight.w700)))],
      ));

  /// Signs out of the current ROLE only — Firebase stays connected.
  /// Staff see PIN screen again. To sign out from Firebase, use hidden admin screen.
  void _confirmRoleSignOut(BuildContext context, WidgetRef ref) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: C.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Sign Out?', style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800, color: C.white)),
      content: Text(
        'You will be returned to the staff PIN screen. '
        'The app stays connected to the database.',
        style: GoogleFonts.inter(fontSize: 13, color: C.textMuted, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: C.textMuted))),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            AppUtils.staffLogout(ref);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: C.yellow, foregroundColor: C.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text('Sign Out', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800))),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════
// 1. SHOP PROFILE
// ═════════════════════════════════════════════════════════════
class ShopProfilePage extends ConsumerStatefulWidget {
  const ShopProfilePage({super.key});
  @override
  ConsumerState<ShopProfilePage> createState() => _ShopProfileState();
}

class _ShopProfileState extends ConsumerState<ShopProfilePage> {
  late final TextEditingController _shopName, _owner, _phone, _email, _address, _gst;
  XFile? _logoFile;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _shopName = TextEditingController(text: s.shopName);
    _owner    = TextEditingController(text: s.ownerName);
    _phone    = TextEditingController(text: s.phone);
    _email    = TextEditingController(text: s.email);
    _address  = TextEditingController(text: s.address);
    _gst      = TextEditingController(text: s.gstNumber);
  }

  @override
  void dispose() {
    for (final c in [_shopName, _owner, _phone, _email, _address, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(
          shopName: _shopName.text.trim(),
          ownerName: _owner.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          gstNumber: _gst.text.trim(),
        ));
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Shop Profile', subtitle: 'Business info shown on invoices',
    children: [
      // Logo picker
      Center(child: Column(children: [
        GestureDetector(
          onTap: () async {
            final file = await pickPhoto(context);
            if (file != null) setState(() => _logoFile = file);
          },
        child: Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
              color: C.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.primary.withValues(alpha: 0.5), width: 2),
            ),
            child: _logoFile != null
                ? ClipRRect(borderRadius: BorderRadius.circular(18),
                    child: Image.network(_logoFile!.path, fit: BoxFit.cover))
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.store_outlined, color: C.primary, size: 34),
                    const SizedBox(height: 4),
                    Text('Shop Logo', style: GoogleFonts.inter(
                        fontSize: 10, color: C.textMuted)),
                  ]),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            final file = await pickPhoto(context);
            if (file != null) setState(() => _logoFile = file);
          },
          icon: const Icon(Icons.upload_outlined, size: 16, color: C.primary),
          label: Text('Upload Logo', style: GoogleFonts.inter(
              fontSize: 13, color: C.primary, fontWeight: FontWeight.w700)),
        ),
      ])),
      const SizedBox(height: 8),
      const SLabel('BUSINESS DETAILS'),
      AppField(label: 'Shop Name', controller: _shopName, required: true,
          hint: 'e.g. TechFix Pro'),
      AppField(label: 'Owner / Manager Name', controller: _owner, required: true,
          hint: 'Your full name'),
      AppField(label: 'Business Phone', controller: _phone,
          keyboardType: TextInputType.phone, hint: '+91 XXXXX XXXXX'),
      AppField(label: 'Business Email', controller: _email,
          keyboardType: TextInputType.emailAddress, hint: 'shop@email.com'),
      AppField(label: 'Full Address', controller: _address,
          maxLines: 3, hint: 'Shop number, Street, Area, City, PIN'),
      const SLabel('GST & LEGAL'),
      AppField(label: 'GSTIN Number', controller: _gst,
          hint: '29ABCDE1234F1Z5'),
      _infoBanner('GSTIN will appear on all invoices and receipts.'),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 21. DEMO DATA TOOLS
// ═════════════════════════════════════════════════════════════
class DemoDataPage extends ConsumerStatefulWidget {
  const DemoDataPage({super.key});
  @override
  ConsumerState<DemoDataPage> createState() => _DemoDataState();
}

class _DemoDataState extends ConsumerState<DemoDataPage> {
  bool _seeding = false;
  bool _clearing = false;

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
      if (shopId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ No shop ID available'), backgroundColor: C.red)
          );
        }
        return;
      }

      // Helper to insert with resilience
      Future<void> insertResilient(String table, List<Map<String, dynamic>> dataSets, String description) async {
        for (final data in dataSets) {
          try {
            await SupabaseService().client.from(table).upsert(data);
            debugPrint('✅ $description inserted with ${data.length} fields');
            return;
          } catch (e) {
            debugPrint('⚠️ $description failed with ${data.length} fields: $e');
          }
        }
        debugPrint('⚠️ Failed to insert $description');
      }

      final now = DateTime.now();
      // Create demo staff
      final techUid = 'demo-$shopId-tech-001';
      await insertResilient('users', [
        {
          'uid': techUid,
          'shopId': shopId,
          'displayName': 'Demo Technician',
          'email': 'tech@demo.local',
          'phone': '+1 555 123 4567',
          'role': 'technician',
          'specialization': 'Screen Repair',
          'totalJobs': 0,
          'completedJobs': 0,
          'rating': 4.8,
          'isActive': true,
          'isOwner': false,
          'biometricEnabled': false,
          'pin': '1234',
          'pin_hash': '',
          'createdAt': now.toIso8601String(),
          'joinedAt': now.toIso8601String(),
          'lastLoginAt': '',
        },
        {
          'uid': techUid,
          'shopId': shopId,
          'displayName': 'Demo Technician',
          'role': 'technician',
          'isActive': true,
        },
      ], 'Demo tech staff');

      final recUid = 'demo-$shopId-rec-001';
      await insertResilient('users', [
        {
          'uid': recUid,
          'shopId': shopId,
          'displayName': 'Demo Receptionist',
          'email': 'reception@demo.local',
          'phone': '+1 555 765 4321',
          'role': 'reception',
          'specialization': 'Front Desk',
          'totalJobs': 0,
          'completedJobs': 0,
          'rating': 5.0,
          'isActive': true,
          'isOwner': false,
          'biometricEnabled': false,
          'pin': '5678',
          'pin_hash': '',
          'createdAt': now.toIso8601String(),
          'joinedAt': now.toIso8601String(),
          'lastLoginAt': '',
        },
        {
          'uid': recUid,
          'shopId': shopId,
          'displayName': 'Demo Receptionist',
          'role': 'reception',
          'isActive': true,
        },
      ], 'Demo reception staff');

      // Create demo customers
      final custId1 = 'demo-$shopId-cust-001';
      await insertResilient('customers', [
        {
          'customerId': custId1,
          'shopId': shopId,
          'name': 'Rajesh Kumar',
          'phone': '+91 98765 43210',
          'email': 'rajesh@example.com',
          'address': 'MG Road, Bangalore',
          'tier': 'Gold',
          'isVip': true,
          'isBlacklisted': false,
          'points': 1500,
          'repairsCount': 3,
          'totalSpend': 28500.0,
          'notes': '',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        {
          'customerId': custId1,
          'shopId': shopId,
          'name': 'Rajesh Kumar',
          'phone': '+91 98765 43210',
        },
      ], 'Demo customer');

      // Create demo products
      final prodId1 = 'demo-$shopId-prod-001';
      await insertResilient('products', [
        {
          'productId': prodId1,
          'shopId': shopId,
          'sku': 'SCR-SAM-S24-001',
          'productName': 'Samsung Galaxy S24 OLED Screen',
          'category': 'Spare Parts',
          'brand': 'Samsung',
          'description': 'OEM quality OLED display assembly',
          'supplierName': 'Demo Parts Supplier',
          'costPrice': 3200.0,
          'sellingPrice': 4500.0,
          'stockQty': 5,
          'reorderLevel': 3,
          'stockHistory': [],
          'isActive': true,
          'imageUrl': '',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        {
          'productId': prodId1,
          'shopId': shopId,
          'productName': 'Samsung Galaxy S24 OLED Screen',
          'stockQty': 5,
        },
      ], 'Demo product 1');

      final prodId2 = 'demo-$shopId-prod-002';
      await insertResilient('products', [
        {
          'productId': prodId2,
          'shopId': shopId,
          'sku': 'BAT-IPH-15-001',
          'productName': 'iPhone 15 Battery',
          'category': 'Spare Parts',
          'brand': 'Apple',
          'description': 'Original Apple battery for iPhone 15',
          'supplierName': 'Demo Parts Supplier',
          'costPrice': 2100.0,
          'sellingPrice': 3200.0,
          'stockQty': 8,
          'reorderLevel': 5,
          'stockHistory': [],
          'isActive': true,
          'imageUrl': '',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        {
          'productId': prodId2,
          'shopId': shopId,
          'productName': 'iPhone 15 Battery',
          'stockQty': 8,
        },
      ], 'Demo product 2');

      // Create demo job (resilient)
      final jobId1 = 'demo-$shopId-job-001';
      const jobNumber = 'DEMO-0001';

      final jobDataSets = [
        {
          'jobId': jobId1,
          'jobNumber': jobNumber,
          'shopId': shopId,
          'customerId': custId1,
          'customerName': 'Rajesh Kumar',
          'customerPhone': '+91 98765 43210',
          'brand': 'Samsung',
          'model': 'Galaxy S24',
          'imei': '352099001761481',
          'color': 'Phantom Black',
          'problem': 'Screen cracked',
          'notes': 'Customer reported dropping phone, screen has a spider-web crack, touch not working in some areas',
          'status': 'In Repair',
          'previousStatus': 'Checked In',
          'holdReason': null,
          'priority': 'Normal',
          'technicianId': techUid,
          'technicianName': 'Demo Technician',
          'createdAt': now.toIso8601String(),
          'estimatedEndDate': now.add(const Duration(days: 3)).toIso8601String(),
          'laborCost': 1000.0,
          'partsCost': 4500.0,
          'discountAmount': 0.0,
          'taxAmount': 990.0,
          'totalAmount': 6490.0,
          'partsUsed': [{'productId': prodId1, 'name': 'Samsung Galaxy S24 OLED Screen', 'quantity': 1, 'price': 4500.0}],
          'intakePhotos': [],
          'completionPhotos': [],
          'timeline': [
            {'status': 'Job Created', 'time': now.toIso8601String(), 'by': 'System', 'type': 'flow', 'note': 'Demo job created'}
          ],
          'notificationSent': false,
          'reopenCount': 0,
          'warrantyExpiry': now.add(const Duration(days: 90)).toIso8601String(),
          'invoiceId': null,
          'updatedAt': now.toIso8601String(),
        },
        {
          'jobId': jobId1,
          'jobNumber': jobNumber,
          'shopId': shopId,
          'customerId': custId1,
          'customerName': 'Rajesh Kumar',
          'brand': 'Samsung',
          'model': 'Galaxy S24',
          'status': 'In Repair',
          'priority': 'Normal',
          'totalAmount': 6490.0,
        },
        {
          'jobId': jobId1,
          'jobNumber': jobNumber,
          'shopId': shopId,
          'customerName': 'Rajesh Kumar',
          'status': 'In Repair',
        },
      ];

      bool jobInserted = false;
      for (final jobData in jobDataSets) {
        try {
          await SupabaseService().client.from('jobs').upsert(jobData);
          jobInserted = true;
          debugPrint('✅ Demo job inserted with ${jobData.length} fields');
          break;
        } catch (e) {
          debugPrint('⚠️ Job insert failed with ${jobData.length} fields: $e');
        }
      }

      if (!jobInserted) {
        debugPrint('⚠️ Failed to insert demo job');
      }

      // Refresh local providers
      await ref.read(staffProvider.notifier).loadFromSupabase(shopId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Demo data generated successfully!'), backgroundColor: C.green)
        );
      }
    } catch (e) {
      debugPrint('Seeding error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to seed data: $e'), backgroundColor: C.red)
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bgCard,
        title: Text('Clear All Demo Data?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: C.white)),
        content: Text('This will delete all demo jobs, customers, products, and staff created with the demo tools. This action cannot be undone.',
            style: GoogleFonts.inter(fontSize: 13, color: C.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.white),
            child: const Text('Clear Demo Data'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _clearing = true);
      try {
        final session = ref.read(currentUserProvider).asData?.value;
        final shopId = session?.shopId ?? '';
        if (shopId.isEmpty) return;

        // First, fetch demo jobs to release their parts
        try {
          final demoJobsData = await SupabaseService().client.from('jobs').select().eq('shopId', shopId).ilike('jobId', 'demo-%');
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

        // Delete demo records with resilience
        Future<void> deleteResilient(String table, String column, String pattern) async {
          try {
            await SupabaseService().client.from(table).delete().eq('shopId', shopId).ilike(column, pattern);
            debugPrint('✅ Deleted demo records from $table');
          } catch (e) {
            debugPrint('⚠️ Failed to delete demo records from $table: $e');
          }
        }

        await deleteResilient('jobs', 'jobId', 'demo-%');
        await deleteResilient('products', 'productId', 'demo-%');
        await deleteResilient('customers', 'customerId', 'demo-%');
        await deleteResilient('users', 'uid', 'demo-%');

        // Refresh local providers
        await ref.read(staffProvider.notifier).loadFromSupabase(shopId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ Demo data cleared!'), backgroundColor: C.primary)
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Clear failed: $e'), backgroundColor: C.red)
          );
        }
      } finally {
        if (mounted) setState(() => _clearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Demo Data Tools',
    subtitle: 'Manage test data for your shop',
    children: [
      _infoBanner('Use these tools to quickly populate your shop with sample data for testing features, or to reset your shop data.'),
      
      SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌱 Seed Sample Data', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15, color: C.white)),
            const SizedBox(height: 8),
            Text('Populates your shop with 3+ samples for every feature: staff, products, customers, jobs, and transactions.',
                style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _seeding ? null : _seed,
                icon: _seeding 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.bg))
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(_seeding ? 'Seeding...' : 'Generate Demo Data', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(backgroundColor: C.primary, foregroundColor: C.bg),
              ),
            ),
          ],
        ),
      ),
      
      const SizedBox(height: 16),
      
      SCard(
        borderColor: C.red.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚠️ Clear Demo Data', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15, color: C.red)),
            const SizedBox(height: 8),
            Text('Remove demo customers, jobs, products and demo staff for this shop.',
                style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _clearing ? null : _clear,
                icon: _clearing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.red))
                  : const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(_clearing ? 'Clearing...' : 'Clear Demo Data', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(foregroundColor: C.red, side: const BorderSide(color: C.red)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 2. INVOICE & RECEIPTS
// ═════════════════════════════════════════════════════════════
class InvoicePage extends ConsumerStatefulWidget {
  const InvoicePage({super.key});
  @override
  ConsumerState<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends ConsumerState<InvoicePage> {
  late final TextEditingController _prefix, _footer;
  String _template = 'Standard';
  bool _showQR = true, _showLogo = true, _showTerms = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _prefix   = TextEditingController(text: s.invoicePrefix);
    _template = s.settings['invoiceTemplate'] as String? ?? 'Standard';
    _showQR   = s.settings['invoiceShowQR']   as bool?   ?? true;
    _showLogo = s.settings['invoiceShowLogo'] as bool?   ?? true;
    _showTerms= s.settings['invoiceShowTerms'] as bool?  ?? false;
    _footer   = TextEditingController(
        text: s.settings['invoiceFooter'] as String? ?? 'Thank you for choosing TechFix Pro!');
  }

  @override
  void dispose() { _prefix.dispose(); _footer.dispose(); super.dispose(); }

  Future<void> _save() async {
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings)
      ..['invoiceTemplate'] = _template
      ..['invoiceShowQR']   = _showQR
      ..['invoiceShowLogo'] = _showLogo
      ..['invoiceShowTerms']= _showTerms
      ..['invoiceFooter']   = _footer.text.trim();
    ref.read(settingsProvider.notifier).update(
        current.copyWith(invoicePrefix: _prefix.text.trim(), settings: newSettings));
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;
    if (!mounted) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId),
        successMsg: '✅ Invoice settings saved');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Invoice & Receipts', subtitle: 'Customise invoice appearance',
    children: [
      const SLabel('NUMBER FORMAT'),
      AppField(label: 'Invoice Number Prefix', controller: _prefix, hint: 'INV'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.bgElevated,
            borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: C.textMuted),
          const SizedBox(width: 8),
          Text('Preview: ${_prefix.text.isEmpty ? "INV" : _prefix.text}-2025-0042',
              style: GoogleFonts.inter(fontSize: 13, color: C.text,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
      const SLabel('TEMPLATE STYLE'),
      ...['Standard', 'Branded', 'Minimal', 'Thermal Print'].map((t) {
        final sel = _template == t;
        return GestureDetector(
          onTap: () => setState(() => _template = t),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(_templateIcon(t), style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(t, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 14, color: sel ? C.primary : C.white)),
                Text(_templateDesc(t), style: GoogleFonts.inter(
                    fontSize: 12, color: C.textMuted)),
              ])),
              if (sel) const Icon(Icons.check_circle, color: C.primary, size: 22),
            ]),
          ),
        );
      }),
      const SLabel('INVOICE OPTIONS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '📱', title: 'Show QR Code',
            subtitle: 'Payment QR on invoice',
            trailing: Switch(value: _showQR,
                onChanged: (v) => setState(() => _showQR = v))),
        SettingsTile(icon: '🖼️', title: 'Show Shop Logo',
            subtitle: 'Display logo at top',
            trailing: Switch(value: _showLogo,
                onChanged: (v) => setState(() => _showLogo = v))),
        SettingsTile(icon: '📝', title: 'Show T&C',
            subtitle: 'Terms and conditions section',
            trailing: Switch(value: _showTerms,
                onChanged: (v) => setState(() => _showTerms = v))),
      ]),
      AppField(label: 'Invoice Footer Text', controller: _footer, maxLines: 2,
          hint: 'Thank you message or return policy'),
      _SaveBtn(onSave: _save),
    ],
  );

  String _templateIcon(String t) =>
      {'Standard': '📄', 'Branded': '🎨', 'Minimal': '📋', 'Thermal Print': '🖨️'}[t] ?? '📄';
  String _templateDesc(String t) => {
    'Standard': 'Clean professional layout with all details',
    'Branded': 'With shop logo, colors and custom header',
    'Minimal': 'Simple list — fast to print and read',
    'Thermal Print': '58mm/80mm thermal printer compatible',
  }[t] ?? '';
}

// ═════════════════════════════════════════════════════════════
// 3. TAX & GST
// ═════════════════════════════════════════════════════════════
class TaxPage extends ConsumerStatefulWidget {
  const TaxPage({super.key});
  @override
  ConsumerState<TaxPage> createState() => _TaxPageState();
}

class _TaxPageState extends ConsumerState<TaxPage> {
  late final TextEditingController _rate;
  String _taxType = 'GST';
  bool _priceInclusive = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _rate           = TextEditingController(
        text: s.defaultTaxRate.toStringAsFixed(0));
    // taxType & priceInclusive live in the settings sub-map — no model change needed
    _taxType        = s.settings['taxType']        as String? ?? 'GST';
    _priceInclusive = s.settings['priceInclusive'] as bool?   ?? false;
  }
  @override
  void dispose() { _rate.dispose(); super.dispose(); }

  double get _half => (double.tryParse(_rate.text) ?? 18) / 2;

  Future<void> _save() async {
    // No Tax → always 0.0; otherwise use the field value (never fall back to 18)
    final rate = _taxType == 'No Tax' ? 0.0 : (double.tryParse(_rate.text) ?? 0.0);
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings)
      ..['taxType']        = _taxType
      ..['priceInclusive'] = _priceInclusive;

    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;
    // Step 1: Update local settings state immediately so UI reacts at once
    ref.read(settingsProvider.notifier).update(
        current.copyWith(defaultTaxRate: rate, settings: newSettings));

    // Step 2: Push new tax to every active job (local state + Firebase batch write).
    // Past jobs (Delivered / Cancelled) are untouched.
    ref.read(jobsProvider.notifier).reapplyTaxToActiveJobs(
      rate,
      priceInclusive: _priceInclusive,
    );

    // Step 3: Save shop settings to Firebase
    if (!mounted) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId),
        successMsg: '✅ Tax saved — all active job totals updated');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Tax & GST', subtitle: 'Applied to all repair jobs and POS sales',
    children: [
      const SLabel('TAX TYPE'),
      Row(children: ['GST', 'VAT', 'No Tax'].map((t) {
        final sel = _taxType == t;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: t == 'No Tax' ? 0 : 8),
          child: GestureDetector(
            onTap: () => setState(() => _taxType = t),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.15) : C.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Column(children: [
                Text(t == 'GST' ? '🇮🇳' : t == 'VAT' ? '💶' : '🚫',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(t, style: GoogleFonts.inter(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sel ? C.primary : C.textMuted)),
              ]),
            ),
          ),
        ));
      }).toList()),
      const SizedBox(height: 16),
      if (_taxType != 'No Tax') ...[
        AppField(label: 'Default Tax Rate (%)', controller: _rate,
            keyboardType: TextInputType.number,
            hint: '18', suffix: const Icon(Icons.percent, size: 16, color: C.textMuted),
            onChanged: (_) => setState(() {})),
        SettingsGroup(title: '', tiles: [
          SettingsTile(icon: '💰', title: 'Prices are tax-inclusive',
              subtitle: 'Tax is extracted from selling price',
              trailing: Switch(value: _priceInclusive,
                  onChanged: (v) => setState(() => _priceInclusive = v))),
        ]),
        SCard(child: Column(children: [
          _taxRow('CGST (Central)',  '$_half%', _half),
          const Divider(color: C.border, height: 16),
          _taxRow('SGST (State)',    '$_half%', _half),
          const Divider(color: C.border, height: 16),
          _taxRow('Total GST',      '${_rate.text}%',
              double.tryParse(_rate.text) ?? 18,  bold: true),
        ])),
        const SizedBox(height: 16),
        _infoBanner(
          'On ₹1,000 service:  CGST = ₹${(_half * 10).toStringAsFixed(0)}  +  '
          'SGST = ₹${(_half * 10).toStringAsFixed(0)}  =  '
          'Total ₹${((double.tryParse(_rate.text) ?? 18) * 10).toStringAsFixed(0)} tax',
        ),
      ],
      _SaveBtn(onSave: _save),
    ],
  );

  Widget _taxRow(String l, String r, double v, {bool bold = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: GoogleFonts.inter(fontSize: 13,
            color: bold ? C.white : C.textMuted,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        Text(r, style: GoogleFonts.plusJakartaSans(fontSize: 14,
            fontWeight: FontWeight.w800, color: C.primary)),
      ]);
}

// ═════════════════════════════════════════════════════════════
// 4. PAYMENT METHODS
// ═════════════════════════════════════════════════════════════
class PaymentMethodsPage extends ConsumerStatefulWidget {
  const PaymentMethodsPage({super.key});
  @override
  ConsumerState<PaymentMethodsPage> createState() => _PayMethodsState();
}

class _PayMethodsState extends ConsumerState<PaymentMethodsPage> {
  late Map<String, bool> _methods;
  final _allOptions = [
    'Cash', 'Card (Debit/Credit)', 'UPI (GPay/PhonePe)',
    'Paytm Wallet', 'Net Banking', 'Bank Transfer (NEFT)',
    'EMI', 'Store Credit',
  ];
  final _icons = <String, String>{
    'Cash': '💵', 'Card (Debit/Credit)': '💳', 'UPI (GPay/PhonePe)': '📱',
    'Paytm Wallet': '👛', 'Net Banking': '🏦', 'Bank Transfer (NEFT)': '🔄',
    'EMI': '📆', 'Store Credit': '🎁',
  };

  @override
  void initState() {
    super.initState();
    final enabled = ref.read(settingsProvider).enabledPayments;
    _methods = { for (var opt in _allOptions) opt : enabled.contains(opt) };
  }

  Future<void> _save() async {
    final enabled = _methods.entries.where((e) => e.value).map((e) => e.key).toList();
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(enabledPayments: enabled));
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Payment Methods', subtitle: 'Enable methods at POS checkout',
    children: [
      _infoBanner('Enabled methods will appear on the POS screen and invoices.'),
      SettingsGroup(title: 'PAYMENT OPTIONS', tiles: _methods.entries.map((e) =>
          SettingsTile(
            icon: _icons[e.key] ?? '💰',
            title: e.key,
            subtitle: e.value ? 'Enabled at POS' : 'Disabled',
            trailing: Switch(value: e.value,
                onChanged: (v) => setState(() => _methods[e.key] = v)),
          )).toList()),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 5. STAFF
// ═════════════════════════════════════════════════════════════
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});
  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  @override
  Widget build(BuildContext context) {
    final ref   = this.ref;
    // Watch techsProvider — now contains ALL roles (owner excluded)
    final techs  = ref.watch(techsProvider);
    final active = techs.where((t) => t.isActive).length;

    return _Page(
      title: 'Staff', subtitle: '$active active · ${techs.length} total',
      fab: FloatingActionButton.extended(
        heroTag: 'fab_staff',
        backgroundColor: C.primary, foregroundColor: C.bg,
        icon: const Icon(Icons.person_add_outlined),
        label: Text('Add Staff', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StaffFormPage())),
      ),
      children: [
        if (techs.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(children: [
              const Text('👨‍🔧', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('No staff added', style: GoogleFonts.inter(
                  fontSize: 16, color: C.textMuted)),
            ]),
          )),
        ...techs.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StaffFormPage(staff: t))),
            child: SCard(
              borderColor: t.isActive ? null : C.red.withValues(alpha: 0.3),
              child: Row(children: [
                Stack(children: [
                  CircleAvatar(radius: 26,
                    backgroundColor: (t.isActive ? C.primary : C.textDim).withValues(alpha: 0.15),
                    child: Text(t.name.isNotEmpty ? t.name[0] : '?',
                        style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 18,
                        color: t.isActive ? C.primary : C.textMuted)),
                  ),
                  Positioned(bottom: 0, right: 0, child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: t.isActive ? C.green : C.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.bgCard, width: 2),
                    ),
                  )),
                ]),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(child: Text(t.name, style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 15, color: C.white),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    // ✅ Use role from Technician object — no Firebase fetch needed
                    _rolePill(t.role),
                  ]),
                  Text(t.specialization, style: GoogleFonts.inter(
                      fontSize: 12, color: C.primary)),
                  const SizedBox(height: 2),
                  Row(children: [
                    _statChip('🔧', '${t.totalJobs} jobs'),
                    const SizedBox(width: 8),
                    _statChip('⭐', t.rating.toStringAsFixed(1)),
                    if (t.phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _statChip('📞', t.phone),
                    ],
                  ]),
                ])),
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.edit_outlined, color: C.primary, size: 16)),
              ]),
            ),
          ),
        )),
      ],
    );
  }

  Widget _statChip(String icon, String val) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 11)),
    const SizedBox(width: 3),
    Text(val, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
  ]);

  // ✅ Fixed: takes role string directly — no async Firebase fetch per card
  Widget _rolePill(String role) {
    Color color = C.primary; // technician
    String emoji = '🔧';
    if (role == 'admin')     { color = C.yellow; emoji = '👑'; }
    if (role == 'manager')   { color = C.accent;  emoji = '🎯'; }
    if (role == 'reception') { color = C.green;   emoji = '💁'; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text('$emoji ${role.toUpperCase()}',
          style: GoogleFonts.plusJakartaSans(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class StaffFormPage extends ConsumerStatefulWidget {
  final Technician? staff;
  const StaffFormPage({super.key, this.staff});
  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<StaffFormPage> {
  late final TextEditingController _name, _phone, _spec, _rating, _pin;
  late bool _isActive;
  late String _role;
  bool get _isEdit => widget.staff != null;

  // Role metadata — emoji, label, color
  static const _roleMeta = <String, (String, String, Color)>{
    'technician': ('🔧', 'Technician', Color(0xFFFF9800)),
    'manager':    ('🎯', 'Manager',    Color(0xFF00BCD4)),
    'reception':  ('💁', 'Reception',  Color(0xFF4CAF50)),
    'admin':      ('👑', 'Admin',      Color(0xFF9B59B6)),
  };
  static const _roles = ['technician', 'manager', 'reception', 'admin'];

  @override
  void initState() {
    super.initState();
    final t = widget.staff;
    _name     = TextEditingController(text: t?.name ?? '');
    _phone    = TextEditingController(text: t?.phone ?? '');
    _spec     = TextEditingController(text: t?.specialization ?? 'General');
    _rating   = TextEditingController(text: t?.rating.toStringAsFixed(1) ?? '5.0');
    _pin      = TextEditingController(text: t?.pin ?? '');
    _isActive = t?.isActive ?? true;
    // ✅ Role comes from Technician.role (now a real field).
    // For existing staff, Technician.role is populated by the realtime listener
    // from users/$uid/role in main.dart. No separate async fetch needed.
    _role = t?.role ?? 'technician';
  }

  // ✅ Removed didChangeDependencies + _loadExistingRole — no longer needed
  // because Technician.role is now passed directly from techsProvider.

  @override
  void dispose() {
    for (final c in [_name, _phone, _spec, _rating, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    // ── Validation ────────────────────────────────────────────
    final name = _name.text.trim();
    final pin  = _pin.text.trim();
    if (name.isEmpty) {
      _snack('Name is required', C.red); return;
    }
    if (pin.isNotEmpty && pin.length != 4) {
      _snack('PIN must be exactly 4 digits', C.red); return;
    }

    final session = ref.read(currentUserProvider).asData?.value;
    final shopId  = session?.shopId ?? '';
    if (shopId.isEmpty) {
      _snack('Not logged in — cannot save', C.red); return;
    }

    final existing = widget.staff;
    final id  = existing?.techId ?? 'staff_${DateTime.now().millisecondsSinceEpoch}';
    final tech = (existing ?? Technician(
      techId: id, shopId: shopId, name: '',
    )).copyWith(
      name: name,
      phone: _phone.text.trim(),
      specialization: _spec.text.trim().isEmpty ? 'General' : _spec.text.trim(),
      isActive: _isActive,
      rating: double.tryParse(_rating.text) ?? 5.0,
      pin: pin,
      role: _role,
    );

    try {
      // Use Supabase staff provider methods
      if (_isEdit) {
        await ref.read(staffProvider.notifier).updateStaff(tech);
      } else {
        await ref.read(staffProvider.notifier).addStaff(tech);
      }

      // Update staffProvider — techsProvider auto-updates as a derived view
      await ref.read(staffProvider.notifier).loadFromSupabase(shopId);

      if (mounted) {
        _snack(_isEdit ? '✅ Staff updated' : '✅ Staff added', C.green);
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _snack('Save failed: $e', C.red);
    }
  }

  Future<void> _deleteStaff() async {
    final staff = widget.staff!;
    final id    = staff.techId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove ${staff.name}?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: C.white)),
        content: Text('This removes them from staff and job assignment. '
            'Their existing jobs are not deleted.',
            style: GoogleFonts.inter(fontSize: 13, color: C.textMuted, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: C.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: C.red,
                  foregroundColor: C.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('Remove', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Hard-delete: removes from Supabase AND local state instantly.
      await ref.read(staffProvider.notifier).removeFromSupabase(id);
      if (mounted) {
        _snack('✅ ${staff.name} removed', C.green);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _snack('Delete failed: $e', C.red);
    }
  }

  void _snack(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
        backgroundColor: bg, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) => _Page(
    title: _isEdit ? 'Edit Staff' : 'New Staff',
    subtitle: _isEdit ? widget.staff!.name : 'Add a team member',
    actions: [TextButton(onPressed: _save,
        child: Text('Save', style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800, color: C.primary, fontSize: 15)))],
    children: [
      // ── Avatar preview ──────────────────────────────────────
      Center(child: CircleAvatar(radius: 36,
        backgroundColor: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.15),
        child: Text(
          _name.text.isEmpty ? '?' : _name.text[0].toUpperCase(),
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900,
              fontSize: 28,
              color: _roleMeta[_role]?.$3 ?? C.primary),
        ),
      )),
      const SizedBox(height: 20),

      const SLabel('STAFF DETAILS'),
      AppField(label: 'Full Name', controller: _name, required: true,
          hint: 'e.g. Suresh Kumar', onChanged: (_) => setState(() {})),
      AppField(label: 'Phone Number', controller: _phone,
          keyboardType: TextInputType.phone, hint: '+91 XXXXX XXXXX'),
      AppField(label: 'Staff Login PIN (4 digits)', controller: _pin,
          keyboardType: TextInputType.number, hint: '1234', obscureText: true),

      // ── Role selector ───────────────────────────────────────
      // ✅ Chip-based selector — no DropdownButtonFormField initialValue bug
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('ROLE', style: GoogleFonts.plusJakartaSans(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: C.textMuted, letterSpacing: 1.0)),
          const SizedBox(width: 8),
          // Show currently selected role as a coloured badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.4)),
            ),
            child: Text(
              '${_roleMeta[_role]?.$1 ?? ''} ${_role.toUpperCase()}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: _roleMeta[_role]?.$3 ?? C.primary),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8,
          children: _roles.map((r) {
            final meta = _roleMeta[r]!;
            final sel  = _role == r;
            return GestureDetector(
              onTap: () => setState(() => _role = r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? meta.$3.withValues(alpha: 0.15) : C.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? meta.$3 : C.border,
                      width: sel ? 1.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(meta.$1, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, children: [
                    Text(meta.$2, style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? meta.$3 : C.text)),
                    Text(_roleDesc(r), style: GoogleFonts.inter(
                        fontSize: 9, color: sel ? meta.$3.withValues(alpha: 0.8) : C.textMuted)),
                  ]),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ]),

      AppField(label: 'Specialization', controller: _spec,
          hint: 'iOS Repair, Screen Replacement, Water Damage...'),
      AppField(label: 'Rating (0–5)', controller: _rating,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: '5.0'),

      SettingsGroup(title: 'STATUS', tiles: [
        SettingsTile(icon: '✅', title: 'Active',
            subtitle: _isActive
                ? 'Can be assigned to jobs'
                : 'Inactive — not shown in job assignment',
            trailing: Switch(value: _isActive,
                onChanged: (v) => setState(() => _isActive = v))),
      ]),

      _SaveBtn(onSave: _save, label: _isEdit ? '💾  Update Staff' : '➕  Add Staff'),
      if (_isEdit) ...[
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 50,
          child: OutlinedButton(
            onPressed: _deleteStaff,
            style: OutlinedButton.styleFrom(foregroundColor: C.red,
                side: const BorderSide(color: C.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('🗑️  Remove Staff', style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ],
    ],
  );

  String _roleDesc(String role) => switch (role) {
    'technician' => 'Repairs · job updates',
    'manager'    => 'All ops · no billing',
    'reception'  => 'Jobs · customers · POS',
    'admin'      => 'Full access',
    _            => '',
  };
}

// ═════════════════════════════════════════════════════════════
// 6. REPAIR WORKFLOW
// ═════════════════════════════════════════════════════════════
class WorkflowPage extends ConsumerStatefulWidget {
  const WorkflowPage({super.key});
  @override
  ConsumerState<WorkflowPage> createState() => _WorkflowState();
}

class _WorkflowState extends ConsumerState<WorkflowPage> {
  late List<Map<String, String>> _stages;

  @override
  void initState() {
    super.initState();
    _stages = List.from(ref.read(settingsProvider).workflowStages);
  }

  Future<void> _save() async {
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(workflowStages: _stages));
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Repair Workflow', subtitle: '${_stages.length} customizable stages',
    children: [
      _infoBanner('These stages appear in the status dropdown when managing repair jobs.'),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (oldIdx, newIdx) {
          setState(() {
            if (newIdx > oldIdx) newIdx -= 1;
            final item = _stages.removeAt(oldIdx);
            _stages.insert(newIdx, item);
          });
        },
        children: _stages.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final sc = C.statusColor(s['title'] ?? '');
          return SCard(
            key: ValueKey(i),
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(child: Text(s['icon'] ?? '⚙️', style: const TextStyle(fontSize: 16)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(s['title'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 14, color: C.white)),
                Text(s['desc'] ?? '', style: GoogleFonts.inter(
                    fontSize: 11, color: C.textMuted)),
              ])),
              const Icon(Icons.drag_indicator, color: C.textDim, size: 20),
            ]),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 7. WARRANTY RULES
// ═════════════════════════════════════════════════════════════
class WarrantyPage extends ConsumerStatefulWidget {
  const WarrantyPage({super.key});
  @override
  ConsumerState<WarrantyPage> createState() => _WarrantyPageState();
}

class _WarrantyPageState extends ConsumerState<WarrantyPage> {
  late final TextEditingController _days;

  final _rules = <String, TextEditingController>{
    'Screen Replacement':   TextEditingController(text: '90'),
    'Battery Replacement':  TextEditingController(text: '180'),
    'Water Damage Repair':  TextEditingController(text: '30'),
    'Charging Port Repair': TextEditingController(text: '60'),
    'Software Repair':      TextEditingController(text: '7'),
    'Camera Repair':        TextEditingController(text: '60'),
    'Speaker / Mic Repair': TextEditingController(text: '45'),
    'Back Glass Repair':    TextEditingController(text: '30'),
  };

  /// Converts a repair type name to a Firebase-safe key.
  /// Replaces spaces, slashes, and any other illegal chars with underscores,
  /// then collapses consecutive underscores and lowercases everything.
  /// e.g. "Speaker / Mic Repair" → "speaker_mic_repair"
  static String _safeKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _days = TextEditingController(text: s.defaultWarrantyDays.toString());
    for (final e in _rules.entries) {
      // Try safe key first, fall back to legacy raw key for backwards compat
      final safeKey  = 'warranty_${_safeKey(e.key)}';
      final legacyKey = 'warranty_${e.key}';
      final saved = s.settings[safeKey] ?? s.settings[legacyKey];
      if (saved != null) e.value.text = saved.toString();
    }
  }

  @override
  void dispose() {
    _days.dispose();
    for (final c in _rules.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings);
    for (final e in _rules.entries) {
      // Use safe Firebase key — no spaces, slashes, or special chars
      newSettings['warranty_${_safeKey(e.key)}'] = int.tryParse(e.value.text) ?? 30;
    }
    ref.read(settingsProvider.notifier).update(current.copyWith(
        defaultWarrantyDays: int.tryParse(_days.text) ?? 30, settings: newSettings));
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) return;

    // Build a summary line: "Screen 90d · Battery 180d · ..."
    final summary = _rules.entries.map((e) {
      final days = int.tryParse(e.value.text) ?? 30;
      // Shorten label: take first word only for compactness
      final short = e.key.split(' ').first;
      return '$short ${days}d';
    }).join(' · ');

    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToSupabase(session.shopId),
        successMsg: '✅ Warranty saved — $summary');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Warranty Rules', subtitle: 'Post-repair warranty periods',
    children: [
      AppField(label: 'Global Default Warranty (Days)', controller: _days,
          keyboardType: TextInputType.number, hint: '30'),
      _infoBanner('This default applies when no specific rule matches the repair type.'),
      const SLabel('BY REPAIR TYPE'),
      ..._rules.entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(e.key, style: GoogleFonts.inter(
              fontSize: 13, color: C.text))),
          SizedBox(width: 90,
            child: TextFormField(
              controller: e.value,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: C.white,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixText: 'days',
                  suffixStyle: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
            ),
          ),
        ]),
      )),
      const SizedBox(height: 16),
      _SaveBtn(onSave: _save),
    ],
  );
}

// 8. USER ROLES & ACCESS
// ═════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════
// 8. USER ROLES & ACCESS
// ═════════════════════════════════════════════════════════════

/// Full-screen page with its own Scaffold (not _Page) because it contains
/// a TabBarView which cannot live inside a ListView.
class UserRolesPage extends ConsumerStatefulWidget {
  const UserRolesPage({super.key});
  @override
  ConsumerState<UserRolesPage> createState() => _UserRolesState();
}

class _UserRolesState extends ConsumerState<UserRolesPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabs;
  bool   _loadingStaff = false;
  String _loadError    = '';

  // Role changes pending save  uid → new role
  final Map<String, String> _pendingRoles = {};
  // PIN field per member
  final Map<String, TextEditingController> _pinCtrls = {};

  static const _roles = ['admin', 'manager', 'reception', 'technician'];
  // (emoji, label, color)
  static const Map<String, (String, String, Color)> _roleMeta = {
    'admin':      ('👑', 'Admin',      Color(0xFF9B59B6)),
    'manager':    ('🎯', 'Manager',    Color(0xFF00BCD4)),
    'reception':  ('💁', 'Reception',  Color(0xFF4CAF50)),
    'technician': ('🔧', 'Tech',       Color(0xFFFF9800)),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(staffProvider).isEmpty) _loadStaff();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _pinCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ─── Firebase ops ────────────────────────────────────────────

  Future<void> _loadStaff() async {
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || session.shopId.isEmpty) {
      setState(() { _loadError = 'Not logged in or shopId missing.'; });
      return;
    }
    setState(() { _loadingStaff = true; _loadError = ''; });
    try {
      await ref.read(staffProvider.notifier).loadFromSupabase(session.shopId);
      for (final s in ref.read(staffProvider)) {
        _pinCtrls.putIfAbsent(s.uid, () => TextEditingController());
      }
      if (mounted) { setState(() => _loadingStaff = false); }
    } catch (e) {
      if (mounted) {
      setState(() {
        _loadError = e.toString();
        _loadingStaff = false;
      });
    }
    }
  }

  Future<void> _saveRoles() async {
    if (_pendingRoles.isEmpty) return;
    final notifier = ref.read(staffProvider.notifier);
    try {
      for (final e in _pendingRoles.entries) {
        await notifier.changeRole(e.key, e.value);
      }
      setState(() => _pendingRoles.clear());
      if (mounted) _snack('✅ Roles updated', C.green);
    } catch (e) {
      if (mounted) _snack('❌ ${e.toString().length > 70 ? e.toString().substring(0,70) : e}', C.red);
    }
  }

  Future<void> _resetPin(String uid) async {
    final pin = _pinCtrls[uid]?.text ?? '';
    if (pin.length != 4) { _snack('PIN must be exactly 4 digits', C.red); return; }
    try {
      await ref.read(staffProvider.notifier).resetPin(uid, pin);
      _pinCtrls[uid]?.clear();
      if (mounted) _snack('✅ PIN reset', C.green);
    } catch (e) {
      if (mounted) _snack('❌ PIN reset failed: $e', C.red);
    }
  }

  void _snack(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
             backgroundColor: bg, behavior: SnackBarBehavior.floating,
             duration: const Duration(seconds: 3)));

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider);
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('User Roles & Access',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
          Text('Assign roles · reset PINs',
              style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
        ]),
        actions: [
          if (_pendingRoles.isNotEmpty)
            TextButton.icon(
              onPressed: _saveRoles,
              icon: const Icon(Icons.save_rounded, size: 16, color: C.primary),
              label: Text('Save ${_pendingRoles.length}',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: C.primary, fontSize: 13)),
            ),
          IconButton(
            icon: _loadingStaff
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: C.primary))
                : const Icon(Icons.refresh_rounded, color: C.primary, size: 22),
            onPressed: _loadingStaff ? null : _loadStaff,
            tooltip: 'Reload from Firebase',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 1, color: C.border),
            TabBar(
              controller: _tabs,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
              labelColor: C.primary,
              unselectedLabelColor: C.textMuted,
              indicatorColor: C.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: '👥  Staff & Roles'),
                Tab(text: '🔐  Permissions'),
              ],
            ),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildStaffTab(staff),
          _buildPermissionsTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: Staff list ──────────────────────────────────────

  Widget _buildStaffTab(List<StaffMember> staff) {
    if (_loadingStaff) {
      return const Center(child: CircularProgressIndicator(color: C.primary));
    }

    if (_loadError.isNotEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('❌', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Failed to load staff', style: GoogleFonts.inter(
              fontSize: 15, color: C.red, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_loadError, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadStaff,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, foregroundColor: C.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      ));
    }

    if (staff.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('👥', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text('No staff found', style: GoogleFonts.plusJakartaSans(
            fontSize: 17, fontWeight: FontWeight.w800, color: C.white)),
        const SizedBox(height: 6),
        Text('Tap ↻ to load staff from Firebase.',
            style: GoogleFonts.inter(fontSize: 13, color: C.textMuted)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _loadStaff,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Load Staff',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
          style: ElevatedButton.styleFrom(
              backgroundColor: C.primary, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ]));
    }

    final active   = staff.where((s) => s.isActive).toList();
    final inactive = staff.where((s) => !s.isActive).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.primary.withValues(alpha: 0.25)),
          ),
          child: Text(
            'Tap a role pill to change it, then tap Save. '
            'Owner role is permanent and cannot be changed. '
            'PIN reset takes effect immediately.',
            style: GoogleFonts.inter(fontSize: 12, color: C.textMuted, height: 1.4),
          ),
        ),
        // Active staff
        ...active.map((s) => _staffCard(s)),
        // Inactive staff section
        if (inactive.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            child: Text('INACTIVE ACCOUNTS',
                style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800,
                    color: C.textMuted, letterSpacing: 1.2)),
          ),
          ...inactive.map((s) => Opacity(opacity: 0.5, child: _staffCard(s))),
        ],
        const SizedBox(height: 8),
        if (_pendingRoles.isNotEmpty)
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveRoles,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text('Save ${_pendingRoles.length} role change(s)',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, foregroundColor: C.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _staffCard(StaffMember s) {
    final currentRole = _pendingRoles[s.uid] ?? s.role;
    final meta = _roleMeta[currentRole] ?? ('👤', currentRole, C.textMuted);
    final roleColor = meta.$3;
    _pinCtrls.putIfAbsent(s.uid, () => TextEditingController());
    final hasPending = _pendingRoles.containsKey(s.uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: C.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: hasPending ? C.primary.withValues(alpha: 0.6) : C.border,
            width: hasPending ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(meta.$1,
                  style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Flexible(child: Text(s.displayName,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800,
                        fontSize: 14, color: C.white),
                    overflow: TextOverflow.ellipsis)),
                if (s.isOwner) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: C.yellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5)),
                    child: Text('OWNER', style: GoogleFonts.plusJakartaSans(
                        fontSize: 9, fontWeight: FontWeight.w800, color: C.yellow)),
                  ),
                ],
                if (hasPending) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: C.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('UNSAVED', style: GoogleFonts.plusJakartaSans(
                        fontSize: 9, fontWeight: FontWeight.w800, color: C.primary)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(s.email.isNotEmpty ? s.email : s.phone,
                  style: GoogleFonts.inter(fontSize: 11, color: C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),

        Container(height: 1, color: C.border),

        // ── Role pills ────────────────────────────────────────
        if (!s.isOwner) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Text('ROLE', style: GoogleFonts.plusJakartaSans(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: C.textMuted, letterSpacing: 1.0)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Wrap(spacing: 8, runSpacing: 6, children: _roles.map((r) {
              final rm  = _roleMeta[r]!;
              final sel = currentRole == r;
              return GestureDetector(
                onTap: () => setState(() {
                  if (r == s.role) {
                    _pendingRoles.remove(s.uid);
                  } else {
                    _pendingRoles[s.uid] = r;
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? rm.$3.withValues(alpha: 0.16) : C.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? rm.$3 : C.border, width: sel ? 1.5 : 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(rm.$1, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 5),
                    Text(rm.$2, style: GoogleFonts.inter(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? rm.$3 : C.textMuted)),
                  ]),
                ),
              );
            }).toList()),
          ),

          Container(height: 1, color: C.border),
        ],

        // ── PIN reset ─────────────────────────────────────────
        if (!s.isOwner)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RESET PIN', style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: C.textMuted, letterSpacing: 1.0)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _pinCtrls[s.uid],
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.inter(
                        fontSize: 20, letterSpacing: 10, color: C.white),
                    decoration: InputDecoration(
                      hintText: '  ●  ●  ●  ●',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 14, color: C.textDim, letterSpacing: 4),
                      counterText: '',
                      filled: true, fillColor: C.bgElevated,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.border)),
                      enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.border)),
                      focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.primary, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(height: 48,
                  child: ElevatedButton(
                    onPressed: () => _resetPin(s.uid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.primary, foregroundColor: C.bg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text('Reset',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
              ]),
              if (s.pin.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('Current PIN: ${'●' * s.pin.length}  (saved)',
                      style: GoogleFonts.inter(fontSize: 10, color: C.textMuted)),
                ),
            ]),
          ),
      ]),
    );
  }

  // ─── TAB 2: Permissions matrix ──────────────────────────────

  Widget _buildPermissionsTab() {
    const rows = [
      // (feature, admin, manager, reception, tech)
      ('SHOP SETTINGS', null, null, null, null),
      ('Edit shop profile',    true,  false, false, false),
      ('Tax & invoice config', true,  false, false, false),
      ('Workflow stages',      true,  true,  false, false),
      ('User roles & PINs',   true,  false, false, false),
      ('JOBS', null, null, null, null),
      ('Create job',           true,  true,  true,  false),
      ('Edit job details',     true,  true,  false, false),
      ('Change status',        true,  true,  true,  true),
      ('View all jobs',        true,  true,  true,  true),
      ('Delete job',           true,  false, false, false),
      ('CUSTOMERS', null, null, null, null),
      ('Add / edit customer',  true,  true,  true,  false),
      ('View customers',       true,  true,  true,  true),
      ('INVENTORY', null, null, null, null),
      ('Add / edit products',  true,  true,  false, false),
      ('Adjust stock',         true,  true,  false, false),
      ('View inventory',       true,  true,  true,  true),
      ('FINANCIALS', null, null, null, null),
      ('Create invoices',      true,  true,  true,  false),
      ('Record payments',      true,  true,  true,  false),
      ('View reports',         true,  true,  false, false),
      ('Export data',          true,  false, false, false),
    ];

    const colColors = [
      Color(0xFF9B59B6),
      Color(0xFF00BCD4),
      Color(0xFF4CAF50),
      Color(0xFFFF9800),
    ];
    const colIcons  = ['👑', '🎯', '💁', '🔧'];
    const colLabels = ['Admin', 'Mgr', 'Rec', 'Tech'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
      children: [
        // Column headers
        Row(children: [
          const Expanded(flex: 4, child: SizedBox()),
          for (int i = 0; i < 4; i++)
            Expanded(child: Column(children: [
              Text(colIcons[i], style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(colLabels[i], style: GoogleFonts.plusJakartaSans(
                  fontSize: 9, fontWeight: FontWeight.w800, color: colColors[i])),
            ])),
        ]),
        const SizedBox(height: 10),

        for (final row in rows)
          row.$2 == null
          // Section header
          ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
              child: Text(row.$1, style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: C.textMuted, letterSpacing: 1.1)),
            )
          // Data row
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: C.border.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(children: [
                Expanded(flex: 4, child: Text(row.$1,
                    style: GoogleFonts.inter(fontSize: 12, color: C.text))),
                ...List.generate(4, (i) {
                  final allowed = [row.$2, row.$3, row.$4, row.$5][i] == true;
                  return Expanded(child: Center(child: allowed
                      ? Icon(Icons.check_circle_rounded, size: 17,
                          color: colColors[i])
                      : Text('—', style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, color: C.textDim,
                          fontWeight: FontWeight.w900))));
                }),
              ]),
            ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.bgElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('Permissions are enforced by Firebase Security Rules, '
              'not just in the app UI. Changing a role takes effect immediately.',
              style: GoogleFonts.inter(fontSize: 11, color: C.textMuted, height: 1.5)),
        ),
      ],
    );
  }
}


// ═════════════════════════════════════════════════════════════
// 9. WHATSAPP BUSINESS
// ═════════════════════════════════════════════════════════════
class WhatsappPage extends StatefulWidget {
  const WhatsappPage({super.key});
  @override
  State<WhatsappPage> createState() => _WhatsappPageState();
}

class _WhatsappPageState extends State<WhatsappPage> {
  final _apiKey    = TextEditingController();
  final _phoneId   = TextEditingController();
  bool _connected  = false;
  bool _autoPickup = true, _autoUpdate = false, _reminder = true;

  final _templates = [
    _Template('Pickup Ready',
        'Hi {name}! 👋 Your {device} ({job_num}) is ready for collection.\n'
        'Amount due: ₹{amount}. Open Mon–Sat 10am–7pm. 📍 {shop_address}'),
    _Template('Job Update',
        'Hi {name}! Update on your {device}: Status changed to {status}. '
        'Questions? Call us at {phone}.'),
    _Template('Pickup Reminder',
        'Hi {name}, reminder: your {device} has been ready for {days} days. '
        'Please collect at your earliest convenience.'),
  ];

  @override
  Widget build(BuildContext context) => _Page(
    title: 'WhatsApp Business', subtitle: 'Send automated customer messages',
    children: [
      _infoBanner(
        'Requires WhatsApp Business API access from Meta. '
        'Get your API key from business.facebook.com → WhatsApp → API Setup.',
        color: C.green,
      ),
      const SLabel('API CREDENTIALS'),
      AppField(label: 'API Key / Bearer Token', controller: _apiKey,
          hint: 'Paste your API key here'),
      AppField(label: 'Phone Number ID', controller: _phoneId,
          hint: 'From Meta Developer Console'),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton.icon(
          onPressed: () => setState(() => _connected = !_connected),
          icon: Icon(_connected ? Icons.check_circle : Icons.link,
              size: 18, color: C.bg),
          label: Text(_connected ? 'Connected ✓' : 'Test Connection',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _connected ? C.green : C.primary,
            foregroundColor: C.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
      const SLabel('AUTO-SEND TRIGGERS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🎉', title: 'Pickup Ready Notification',
            subtitle: 'Send when job → Ready for Pickup',
            trailing: Switch(value: _autoPickup,
                onChanged: (v) => setState(() => _autoPickup = v))),
        SettingsTile(icon: '🔄', title: 'Status Update Messages',
            subtitle: 'Notify on every status change',
            trailing: Switch(value: _autoUpdate,
                onChanged: (v) => setState(() => _autoUpdate = v))),
        SettingsTile(icon: '⏰', title: '3-Day Pickup Reminder',
            subtitle: 'Auto-remind if not collected in 3 days',
            trailing: Switch(value: _reminder,
                onChanged: (v) => setState(() => _reminder = v))),
      ]),
      const SLabel('MESSAGE TEMPLATES'),
      ..._templates.map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(t.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                fontSize: 13, color: C.white)),
            TextButton(onPressed: () => _editTemplate(context, t),
                child: Text('Edit', style: GoogleFonts.inter(
                    color: C.primary, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.bgElevated,
                borderRadius: BorderRadius.circular(8)),
            child: Text(t.body, style: GoogleFonts.inter(
                fontSize: 11, color: C.textMuted, height: 1.5))),
        ])),
      )),
      _SaveBtn(onSave: () {}),
    ],
  );

  void _editTemplate(BuildContext context, _Template t) {
    final ctrl = TextEditingController(text: t.body);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit: ${t.name}', style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800, color: C.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _infoBanner('Variables: {name} {device} {amount} {job_num} {status} {days}'),
          TextFormField(controller: ctrl, maxLines: 5,
              style: GoogleFonts.inter(fontSize: 13, color: C.text),
              decoration: const InputDecoration()),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: C.textMuted))),
          ElevatedButton(
            onPressed: () { setState(() => t.body = ctrl.text); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: C.primary,
                foregroundColor: C.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Save Template', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _Template { final String name; String body; _Template(this.name, this.body); }

// ═════════════════════════════════════════════════════════════
// 10. SMS GATEWAY
// ═════════════════════════════════════════════════════════════
class SmsPage extends StatefulWidget {
  const SmsPage({super.key});
  @override
  State<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends State<SmsPage> {
  String _provider = 'MSG91';
  final _apiKey  = TextEditingController();
  final _sender  = TextEditingController(text: 'TECHFX');
  bool _onPickup = true, _onUpdate = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'SMS Gateway', subtitle: 'Text message notifications to customers',
    children: [
      const SLabel('PROVIDER'),
      ...['MSG91', 'Twilio', 'TextLocal', 'Fast2SMS'].map((p) {
        final sel = _provider == p;
        return GestureDetector(
          onTap: () => setState(() => _provider = p),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(_providerIcon(p), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(p, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                  fontSize: 13, color: sel ? C.primary : C.white))),
              if (sel) const Icon(Icons.check_circle, color: C.primary, size: 20),
            ]),
          ),
        );
      }),
      const SLabel('CREDENTIALS'),
      AppField(label: 'API Key', controller: _apiKey, hint: 'Enter your $_provider API key'),
      AppField(label: 'Sender ID', controller: _sender, hint: 'TECHFX (6 chars max)'),
      const SLabel('SEND SETTINGS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🎉', title: 'Pickup Ready SMS',
            subtitle: 'Auto-send when Ready for Pickup',
            trailing: Switch(value: _onPickup,
                onChanged: (v) => setState(() => _onPickup = v))),
        SettingsTile(icon: '🔄', title: 'Status Update SMS',
            subtitle: 'Notify on status changes',
            trailing: Switch(value: _onUpdate,
                onChanged: (v) => setState(() => _onUpdate = v))),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );

  String _providerIcon(String p) =>
      {'MSG91': '🇮🇳', 'Twilio': '🌐', 'TextLocal': '🇬🇧', 'Fast2SMS': '⚡'}[p] ?? '📱';
}

// ═════════════════════════════════════════════════════════════
// 11. PUSH NOTIFICATIONS
// ═════════════════════════════════════════════════════════════
class PushNotifPage extends StatefulWidget {
  const PushNotifPage({super.key});
  @override
  State<PushNotifPage> createState() => _PushNotifState();
}

class _PushNotifState extends State<PushNotifPage> {
  final _notifs = <String, bool>{
    'Job Overdue Alert': true,
    'Low Stock Warning': true,
    'New Job Created': false,
    'Job Status Changed': true,
    'Daily Summary (8am)': false,
    'Customer Pickup Reminder': true,
    'Payment Received': true,
    'Warranty Expiring Soon': false,
  };

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Push Notifications', subtitle: 'Alerts sent to this device',
    children: [
      _infoBanner('Push notifications appear in your phone\'s notification centre.'),
      SettingsGroup(title: 'ALERT TYPES',
          tiles: _notifs.entries.map((e) => SettingsTile(
            icon: _notifIcon(e.key),
            title: e.key,
            subtitle: e.value ? 'Enabled' : 'Disabled',
            trailing: Switch(value: e.value,
                onChanged: (v) => setState(() => _notifs[e.key] = v)),
          )).toList()),
      _SaveBtn(onSave: () {}),
    ],
  );

  String _notifIcon(String k) {
    const m = {
      'Job Overdue Alert': '⏰', 'Low Stock Warning': '📦',
      'New Job Created': '🔧', 'Job Status Changed': '🔄',
      'Daily Summary (8am)': '📊', 'Customer Pickup Reminder': '🎉',
      'Payment Received': '💰', 'Warranty Expiring Soon': '🛡️',
    };
    return m[k] ?? '🔔';
  }
}

// ═════════════════════════════════════════════════════════════
// 12. EMAIL
// ═════════════════════════════════════════════════════════════
class EmailPage extends StatelessWidget {
  const EmailPage({super.key});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Email Settings', subtitle: 'SMTP configuration for email sending',
    children: [
      _infoBanner('For Gmail: use App Passwords (not your main password). '
          'Enable 2FA first, then generate an App Password.'),
      const SLabel('SMTP CONFIGURATION'),
      const AppField(label: 'SMTP Host', hint: 'smtp.gmail.com'),
      const AppField(label: 'SMTP Port', hint: '587  (TLS)  or  465  (SSL)',
          keyboardType: TextInputType.number),
      const AppField(label: 'From Email Address', hint: 'noreply@yourshop.com',
          keyboardType: TextInputType.emailAddress),
      const AppField(label: 'App Password', hint: '16-character app password'),
      const AppField(label: 'From Display Name', hint: 'TechFix Pro Shop'),
      const SLabel('EMAIL TRIGGERS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🧾', title: 'Invoice on Completion',
            subtitle: 'Email invoice when job is completed',
            trailing: Switch(value: true, onChanged: (_) {})),
        SettingsTile(icon: '🎉', title: 'Pickup Ready Email',
            subtitle: 'Notify when device is ready',
            trailing: Switch(value: true, onChanged: (_) {})),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 13. PAYMENT GATEWAY
// ═════════════════════════════════════════════════════════════
class PaymentGatewayPage extends StatefulWidget {
  const PaymentGatewayPage({super.key});
  @override
  State<PaymentGatewayPage> createState() => _PaymentGatewayState();
}

class _PaymentGatewayState extends State<PaymentGatewayPage> {
  String _selected = '';
  final _key = TextEditingController();
  final _secret = TextEditingController();
  bool _testMode = true;

  final _gateways = [
    ('razorpay', 'Razorpay', '🇮🇳', 'Most popular in India — UPI, cards, wallets'),
    ('stripe',   'Stripe',   '🌐', 'International cards & digital wallets'),
    ('paytm',    'Paytm',    '📱', 'Paytm QR, wallet & UPI payments'),
    ('instamojo','Instamojo','⚡', 'Simple Indian payment collection'),
  ];

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Payment Gateway', subtitle: 'Collect online payments from customers',
    children: [
      const SLabel('SELECT GATEWAY'),
      ..._gateways.map((g) {
        final sel = _selected == g.$1;
        return GestureDetector(
          onTap: () => setState(() => _selected = g.$1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(g.$3, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(g.$2, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 14, color: sel ? C.primary : C.white)),
                Text(g.$4, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
              ])),
              if (sel) const Icon(Icons.check_circle, color: C.primary),
            ]),
          ),
        );
      }),
      if (_selected.isNotEmpty) ...[
        const SLabel('API CREDENTIALS'),
        AppField(label: 'API Key / Key ID', controller: _key, hint: 'rzp_live_xxxx or pk_live_xxxx'),
        AppField(label: 'API Secret', controller: _secret, hint: 'Secret key from dashboard'),
          SettingsGroup(title: '', tiles: [
          SettingsTile(icon: '🧪', title: 'Test Mode',
              subtitle: _testMode ? 'Using sandbox — no real money' : 'LIVE mode — real payments',
              iconBg: _testMode ? C.yellow.withValues(alpha: 0.1) : C.red.withValues(alpha: 0.1),
              trailing: Switch(value: _testMode,
                  onChanged: (v) => setState(() => _testMode = v))),
        ]),
        if (!_testMode) _infoBanner(
            '⚠️ LIVE mode is active. Real payments will be processed.', color: C.red),
      ],
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 14. ACCOUNTING EXPORT
// ═════════════════════════════════════════════════════════════
class AccountingPage extends StatelessWidget {
  const AccountingPage({super.key});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Accounting Export', subtitle: 'Sync or export to accounting software',
    children: [
      ...[
        ('tally', 'Tally ERP 9 / Prime', '📊',
            'Export as Tally XML/CSV. Import via Tally gateway.'),
        ('zoho',  'Zoho Books',           '📚',
            'Auto-sync via Zoho Books API. Invoices & payments.'),
        ('qbo',   'QuickBooks Online',    '💼',
            'Connect via OAuth. Real-time sync.'),
        ('csv',   'Generic CSV Export',   '📋',
            'Download all transactions as CSV for any software.'),
      ].map((a) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(a.$3, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(a.$2, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                  fontSize: 14, color: C.white)),
              Text(a.$4, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
            ])),
            SizedBox(width: 80,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: C.primary,
                    foregroundColor: C.bg, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8)),
                child: Text(a.$1 == 'csv' ? 'Export' : 'Connect',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ]),
        ])),
      )),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 15. SUPPLIER INTEGRATION
// ═════════════════════════════════════════════════════════════
class SupplierPage extends StatefulWidget {
  const SupplierPage({super.key});
  @override
  State<SupplierPage> createState() => _SupplierState();
}

class _SupplierState extends State<SupplierPage> {
  final _url    = TextEditingController();
  final _apiKey = TextEditingController();
  bool _autoReorder = false, _emailPO = true;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Supplier Integration', subtitle: 'Auto-reorder low stock parts',
    children: [
      _infoBanner('When stock falls below reorder level, TechFix Pro can '
          'automatically create a Purchase Order and send it to your supplier.'),
      const SLabel('SUPPLIER API'),
      AppField(label: 'Supplier API URL', controller: _url,
          hint: 'https://api.supplier.com/orders'),
      AppField(label: 'API Key', controller: _apiKey,
          hint: 'Supplier-provided API key'),
      const SLabel('REORDER SETTINGS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🔄', title: 'Auto-Reorder on Low Stock',
            subtitle: _autoReorder ? 'Creates PO automatically' : 'Manual approval required',
            trailing: Switch(value: _autoReorder,
                onChanged: (v) => setState(() => _autoReorder = v))),
        SettingsTile(icon: '📧', title: 'Email Purchase Orders',
            subtitle: 'Send PO via email to supplier',
            trailing: Switch(value: _emailPO,
                onChanged: (v) => setState(() => _emailPO = v))),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 16. AI DIAGNOSTICS
// ═════════════════════════════════════════════════════════════
class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _apiKey = TextEditingController();
  bool _diagnosis = true, _pricing = false, _parts = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'AI Diagnostics', subtitle: 'Claude AI for smart repair suggestions',
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0099CC)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          const Text('🤖', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text('Claude AI', style: GoogleFonts.plusJakartaSans(fontSize: 22,
              fontWeight: FontWeight.w900, color: Colors.white)),
          Text('by Anthropic', style: GoogleFonts.inter(
              fontSize: 13, color: Colors.white60)),
          const SizedBox(height: 8),
          Text('Smart repair diagnosis, pricing suggestions, and parts recommendations',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
              textAlign: TextAlign.center),
        ]),
      ),
      const SizedBox(height: 16),
      const SLabel('API CONFIGURATION'),
      AppField(label: 'Anthropic API Key', controller: _apiKey,
          hint: 'sk-ant-api03-...'),
      _infoBanner('Get your API key from console.anthropic.com'),
      const SLabel('AI FEATURES'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🔍', title: 'Diagnosis Suggestions',
            subtitle: 'AI suggests likely causes from customer-reported symptoms',
            trailing: Switch(value: _diagnosis,
                onChanged: (v) => setState(() => _diagnosis = v))),
        SettingsTile(icon: '💰', title: 'Price Recommendations',
            subtitle: 'Market-rate pricing for common repairs',
            trailing: Switch(value: _pricing,
                onChanged: (v) => setState(() => _pricing = v))),
        SettingsTile(icon: '🔩', title: 'Parts Suggestions',
            subtitle: 'Auto-suggest parts needed based on diagnosis',
            trailing: Switch(value: _parts,
                onChanged: (v) => setState(() => _parts = v))),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 17. APP LOCK & BIOMETRICS
// ═════════════════════════════════════════════════════════════
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key});
  @override
  State<AppLockPage> createState() => _AppLockState();
}

class _AppLockState extends State<AppLockPage> {
  bool _pinEnabled = false, _biometric = false, _autoLock = true;
  int _lockAfter = 2; // minutes
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _pinMismatch = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'App Lock & Biometrics', subtitle: 'Secure your shop data',
    children: [
      SettingsGroup(title: 'LOCK METHODS', tiles: [
        SettingsTile(icon: '🔢', title: 'PIN Lock',
            subtitle: _pinEnabled ? '4-digit PIN is set' : 'No PIN configured',
            trailing: Switch(value: _pinEnabled,
                onChanged: (v) => setState(() { _pinEnabled = v; if (!v) { _pin.clear(); _confirm.clear(); } }))),
        SettingsTile(icon: '🤳', title: 'Biometrics / Face ID',
            subtitle: _biometric ? 'Fingerprint or Face ID enabled' : 'Not configured',
            trailing: Switch(value: _biometric,
                onChanged: (v) => setState(() => _biometric = v))),
        SettingsTile(icon: '⏱️', title: 'Auto-Lock',
            subtitle: 'Lock after $_lockAfter min${_lockAfter == 1 ? "" : "s"} of inactivity',
            trailing: Switch(value: _autoLock,
                onChanged: (v) => setState(() => _autoLock = v))),
      ]),
      if (_autoLock) ...[
        const SLabel('AUTO-LOCK TIMEOUT'),
        Slider(
          value: _lockAfter.toDouble(), min: 1, max: 30,
          divisions: 5, activeColor: C.primary,
          label: '$_lockAfter min',
          onChanged: (v) => setState(() => _lockAfter = v.round()),
        ),
        Center(child: Text('Lock after $_lockAfter minute${_lockAfter == 1 ? "" : "s"}',
            style: GoogleFonts.inter(fontSize: 13, color: C.textMuted))),
        const SizedBox(height: 16),
      ],
      if (_pinEnabled) ...[
        const SLabel('SET PIN'),
        TextFormField(
          controller: _pin, obscureText: true, maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.inter(fontSize: 18, letterSpacing: 12, color: C.white),
          decoration: InputDecoration(
            labelText: 'Enter 4-digit PIN',
            labelStyle: GoogleFonts.inter(color: C.textMuted),
            counterText: '',
          ),
          onChanged: (_) => setState(() => _pinMismatch = false),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _confirm, obscureText: true, maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.inter(fontSize: 18, letterSpacing: 12, color: C.white),
          decoration: InputDecoration(
            labelText: 'Confirm PIN',
            labelStyle: GoogleFonts.inter(color: C.textMuted),
            counterText: '',
            errorText: _pinMismatch ? 'PINs do not match' : null,
          ),
          onChanged: (_) => setState(() => _pinMismatch = false),
        ),
        const SizedBox(height: 16),
      ],
      _SaveBtn(onSave: () {
        if (_pinEnabled) {
          if (_pin.text != _confirm.text) {
            setState(() => _pinMismatch = true);
            return;
          }
        }
      }),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 18. AUDIT LOGS (OWNER ONLY)
// ═════════════════════════════════════════════════════════════
class AuditLogsPage extends ConsumerStatefulWidget {
  const AuditLogsPage({super.key});

  @override
  ConsumerState<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends ConsumerState<AuditLogsPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final session = ref.read(currentUserProvider).asData?.value;
    if (session != null && session.shopId.isNotEmpty) {
      await ref.read(auditLogsProvider.notifier).loadFromSupabase(session.shopId);
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  String _getActionIcon(String action) {
    switch (action.toLowerCase()) {
      case 'create':
        return '➕';
      case 'update':
        return '✏️';
      case 'delete':
        return '🗑️';
      case 'view':
        return '👁️';
      default:
        return '📋';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final session = userAsync.asData?.value;
    final logs = ref.watch(auditLogsProvider);

    // Only show if user is owner
    if (session == null || !session.isOwner) {
      return _Page(
        title: 'Audit Logs',
        subtitle: 'Owner-only feature',
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Only the shop owner can view audit logs.',
                style: GoogleFonts.inter(color: C.textMuted, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    if (_loading) {
      return const _Page(
        title: 'Audit Logs',
        subtitle: 'Loading...',
        children: [
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return _Page(
      title: 'Audit Logs',
      subtitle: 'Complete activity trail',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: C.primary),
          onPressed: _loadData,
        ),
      ],
      children: [
        _infoBanner('All actions by all users are logged here. '
            'Logs cannot be deleted.', color: C.textMuted),
        if (logs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    'No logs yet',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: C.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...logs.map((log) {
            final action = log['action'] as String? ?? '';
            final entity = log['entity'] as String? ?? '';
            final entityId = log['entityId'] as String? ?? '';
            final userId = log['userId'] as String? ?? '';
            final timestamp = log['timestamp'] as String? ?? '';
            final details = log['details'] as Map? ?? {};

            // Get display text
            String displayText;
            if (details['message'] != null) {
              displayText = details['message'].toString();
            } else if (details.containsKey(entity)) {
              displayText = '$action $entity ${entityId.isNotEmpty ? '- $entityId' : ''}';
            } else {
              displayText = '$action $entity ${entityId.isNotEmpty ? '- $entityId' : ''}';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: C.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: C.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _getActionIcon(action),
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayText,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: C.text,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline,
                                size: 12,
                                color: C.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                userId.isNotEmpty
                                    ? '${userId.substring(0, 8)}...'
                                    : 'Unknown',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: C.textMuted,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.access_time_outlined,
                                size: 12,
                                color: C.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timestamp.isNotEmpty
                                    ? _formatTimestamp(timestamp)
                                    : '',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: C.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════
// 19. CLOUD BACKUP
// ═════════════════════════════════════════════════════════════
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupState();
}

class _BackupState extends State<BackupPage> {
  String _freq = 'Daily';
  String _location = 'Google Drive';
  bool _backing = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Cloud Backup', subtitle: 'Keep your data safe & restorable',
    children: [
      SCard(
        glowColor: C.green,
        child: Column(children: [
          const Text('✅', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('All data backed up', style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w700, color: C.white)),
          Text('Last backup: Today 06:00 AM', style: GoogleFonts.inter(
              fontSize: 12, color: C.green)),
          const SizedBox(height: 4),
          Text('Size: 2.4 MB  ·  384 jobs  ·  47 customers',
              style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
        ]),
      ),
      const SizedBox(height: 16),
      const SLabel('BACKUP SCHEDULE'),
      Row(children: ['Daily', 'Weekly', 'Manual'].map((f) {
        final sel = _freq == f;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: f == 'Manual' ? 0 : 8),
          child: GestureDetector(
            onTap: () => setState(() => _freq = f),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.15) : C.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Text(f, textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? C.primary : C.textMuted)),
            ),
          ),
        ));
      }).toList()),
      const SizedBox(height: 16),
      const SLabel('BACKUP LOCATION'),
      ...['Google Drive', 'iCloud', 'Local Storage'].map((loc) =>
          GestureDetector(
            onTap: () => setState(() => _location = loc),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _location == loc ? C.primary.withValues(alpha: 0.08) : C.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _location == loc ? C.primary : C.border,
                    width: _location == loc ? 2 : 1),
              ),
              child: Row(children: [
                Text(_locIcon(loc), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Text(loc, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 13, color: _location == loc ? C.primary : C.white))),
                if (_location == loc) const Icon(Icons.check_circle, color: C.primary),
              ]),
            ),
          )),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton.icon(
          onPressed: _backing ? null : () async {
            setState(() => _backing = true);
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) setState(() => _backing = false);
          },
          icon: _backing
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
              : const Icon(Icons.cloud_upload_outlined, size: 20),
          label: Text(_backing ? 'Backing up...' : '☁️  Backup Now',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
          style: ElevatedButton.styleFrom(backgroundColor: C.primary, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 50,
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.restore_outlined, size: 20),
          label: Text('Restore from Backup',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 14)),
          style: OutlinedButton.styleFrom(foregroundColor: C.textMuted,
              side: const BorderSide(color: C.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
    ],
  );

  String _locIcon(String l) =>
      {'Google Drive': '🟢', 'iCloud': '☁️', 'Local Storage': '💾'}[l] ?? '💾';
}

// ═════════════════════════════════════════════════════════════
// 20. EXPORT DATA
// ═════════════════════════════════════════════════════════════
class ExportPage extends StatefulWidget {
  const ExportPage({super.key});
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  String _fromDate = '2025-01-01';
  String _toDate   = DateTime.now().toIso8601String().substring(0, 10);
  final Map<String, bool> _exporting = {};

  final _exports = [
    ('jobs',      '🔧', 'All Repair Jobs',         'Complete job history with status, costs & timeline'),
    ('customers', '👥', 'Customers List',           'Names, phones, tier, spend history'),
    ('inventory', '📦', 'Inventory & Stock',        'Products, SKUs, prices, stock levels'),
    ('invoices',  '🧾', 'Invoices & Receipts',      'All generated invoices with line items'),
    ('payments',  '💰', 'Payment Transactions',      'All payments received and pending'),
    ('finance',   '📊', 'Financial Summary Report', 'Revenue, costs, tax, profit summary'),
  ];

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Export Data', subtitle: 'Download your shop data',
    children: [
      const SLabel('DATE RANGE'),
      Row(children: [
        Expanded(child: AppField(label: 'From', hint: 'YYYY-MM-DD',
            controller: TextEditingController(text: _fromDate),
            onChanged: (v) => _fromDate = v)),
        const SizedBox(width: 10),
        Expanded(child: AppField(label: 'To', hint: 'YYYY-MM-DD',
            controller: TextEditingController(text: _toDate),
            onChanged: (v) => _toDate = v)),
      ]),
      const SLabel('EXPORT OPTIONS'),
      ..._exports.map((e) {
        final loading = _exporting[e.$1] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.bgCard, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.border)),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$3, style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                    fontSize: 13, color: C.white)),
                Text(e.$4, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
              ])),
              const SizedBox(width: 8),
              SizedBox(width: 80, height: 36,
                child: ElevatedButton(
                  onPressed: loading ? null : () async {
                    setState(() => _exporting[e.$1] = true);
                    await Future.delayed(const Duration(seconds: 2));
                    if (mounted) setState(() => _exporting[e.$1] = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: loading ? C.bgElevated : C.primary,
                    foregroundColor: loading ? C.textMuted : C.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                  ),
                  child: loading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: C.primary))
                      : Text('Export', style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ]),
          ),
        );
      }),
    ],
  );
}
