// ─────────────────────────────────────────────────────────────────────────────
//  screens/auth_signup.dart — Owner signup with Supabase Auth & seed data
//
//  FIX: signUp() does NOT create a session when email confirmation is enabled.
//  All DB inserts (registrations / shops / users) now happen AFTER the user
//  has verified their email and signed in for the first time, via a
//  deep-link callback caught in main.dart (onAuthStateChange).
//
//  Flow:
//    SignUpScreen → signUp() → show "check your email" screen
//    User clicks link → app opens → onAuthStateChange fires (event: signedIn)
//    → PendingOnboardingService.run() seeds the DB with the saved data
//    → navigate to home
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../data/providers.dart';
import '../data/seed.dart';
import 'auth_login.dart';
import '../services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PendingOnboardingService
//  Saves signup data to SharedPreferences BEFORE email verification,
//  then runs the actual DB seeding AFTER the session is established.
//  Call PendingOnboardingService.run() from your onAuthStateChange handler.
// ─────────────────────────────────────────────────────────────────────────────
class PendingOnboardingService {
  static const _key = 'pending_onboarding';

  /// Persist all signup data locally so it survives app restart.
  static Future<void> save({
    required String shopId,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String shopName,
    required String ownerPin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'shopId':     shopId,
      'ownerName':  ownerName,
      'ownerEmail': ownerEmail,
      'ownerPhone': ownerPhone,
      'shopName':   shopName,
      'ownerPin':   ownerPin,
    }));
  }

  /// Call this from onAuthStateChange when event == AuthChangeEvent.signedIn.
  /// Runs ShopOnboarding.initialize() with the session now active, then clears.
  static Future<void> run(String ownerUid, WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;   // Nothing pending — normal login, skip.

    final data = jsonDecode(raw) as Map<String, dynamic>;
    final shopId = data['shopId'] as String;

    try {
      await ShopOnboarding.initialize(
        shopId:     shopId,
        ownerUid:   ownerUid,
        ownerName:  data['ownerName']  as String,
        ownerEmail: data['ownerEmail'] as String,
        ownerPhone: data['ownerPhone'] as String,
        shopName:   data['shopName']   as String,
        ownerPin:   data['ownerPin']   as String,
      );

      // Load providers now that DB rows exist
      try { await ref.read(settingsProvider.notifier).loadFromSupabase(shopId); } catch (_) {}
      try { await ref.read(staffProvider.notifier).loadFromSupabase(shopId); } catch (_) {}
      try { await ref.read(transactionsProvider.notifier).loadFromSupabase(shopId); } catch (_) {}

      // Save shopId for future fast-login
      await prefs.setString('shopId', shopId);
    } finally {
      // Always clear pending data whether it succeeded or failed
      await prefs.remove(_key);
    }
  }

  /// Returns true if there is pending onboarding data waiting to be seeded.
  static Future<bool> hasPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  SignUpScreen
// ─────────────────────────────────────────────────────────────────────────────
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name       = TextEditingController();
  final _email      = TextEditingController();
  final _phone      = TextEditingController();
  final _shopName   = TextEditingController();
  final _password   = TextEditingController();
  final _confirm    = TextEditingController();
  final _pin        = TextEditingController();
  final _pinConfirm = TextEditingController();

  bool _loading      = false;
  bool _showPassword = false;
  bool _showConfirm  = false;
  bool _created      = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _phone.dispose();
    _shopName.dispose(); _password.dispose(); _confirm.dispose();
    _pin.dispose(); _pinConfirm.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name      = _name.text.trim();
    final email     = _email.text.trim();
    final phone     = _phone.text.trim();
    final shopName  = _shopName.text.trim();
    final password  = _password.text;
    final confirm   = _confirm.text;
    final pin       = _pin.text.trim();
    final pinConfirm = _pinConfirm.text.trim();

    // ── Validation ──────────────────────────────────────────────────────────
    if ([name, email, shopName, password, confirm, pin, pinConfirm]
        .any((s) => s.isEmpty)) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _error = 'PIN must be 4 digits');
      return;
    }
    if (pin != pinConfirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // ── Step 1: Create the auth account ───────────────────────────────────
      //  signUp() does NOT establish a session when email confirmation is ON.
      //  The user object is returned but auth.currentSession is null.
      //  DO NOT attempt any DB inserts here — they will run as anon → 401.
      final authResponse = await SupabaseService().client.auth.signUp(
        email: email,
        password: password,
        data: {'displayName': name, 'role': 'super_admin'},
      );

      final user = authResponse.user;
      if (user == null) {
        setState(() => _error = 'Signup failed. Please try again.');
        return;
      }

      // ── Step 2: Save onboarding data locally (no DB call yet) ─────────────
      //  This data will be consumed by PendingOnboardingService.run()
      //  the moment the user verifies their email and the session fires.
      final shopId = 'shop_${DateTime.now().millisecondsSinceEpoch}';

      await PendingOnboardingService.save(
        shopId:     shopId,
        ownerName:  name,
        ownerEmail: email,
        ownerPhone: phone,
        shopName:   shopName,
        ownerPin:   pin,
      );

      // ── Step 3: Show "check your email" screen ────────────────────────────
      setState(() => _created = true);

    } on AuthException catch (e) {
      setState(() => _error = _friendlyMsg(e));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyMsg(AuthException e) => switch (e.message) {
    'User already registered'                      => 'This email already has an account.',
    'Email already in use'                         => 'This email already has an account.',
    'Password should be at least 6 characters'     => 'Password too short.',
    _                                              => e.message,
  };

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_created) return _VerifyEmailScreen(email: _email.text.trim());

    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  BackBtn(onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()))),
                  const SizedBox(width: 12),
                  Text('Create your account',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
                ]),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ErrBox(_error!),
                  ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: C.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: C.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeading('Owner details', 'The main admin for your shop'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: AppField(label: 'Full name', hint: 'Jane Doe',
                            controller: _name, required: true)),
                        const SizedBox(width: 12),
                        Expanded(child: AppField(label: 'Phone', hint: '+1 555-1234',
                            controller: _phone, keyboardType: TextInputType.phone)),
                      ]),
                      const SizedBox(height: 12),
                      AppField(label: 'Email address', hint: 'you@yourshop.com',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          required: true),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: AppField(
                            label: 'Password', hint: '••••••••',
                            controller: _password,
                            obscureText: !_showPassword,
                            required: true,
                            suffix: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 16, color: C.textMuted),
                              onPressed: () =>
                                  setState(() => _showPassword = !_showPassword)))),
                        const SizedBox(width: 12),
                        Expanded(child: AppField(
                            label: 'Confirm password', hint: '••••••••',
                            controller: _confirm,
                            obscureText: !_showConfirm,
                            required: true,
                            suffix: IconButton(
                              icon: Icon(
                                _showConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 16, color: C.textMuted),
                              onPressed: () =>
                                  setState(() => _showConfirm = !_showConfirm)))),
                      ]),
                      const SizedBox(height: 20),
                      const SectionHeading('Shop details', 'Your repair shop info'),
                      const SizedBox(height: 12),
                      AppField(label: 'Shop name', hint: 'Downtown Phone Repair',
                          controller: _shopName, required: true),
                      const SizedBox(height: 16),
                      const SectionHeading('Owner PIN', 'Quick access for you and staff'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: AppField(
                            label: '4-digit PIN', hint: '••••',
                            controller: _pin,
                            keyboardType: TextInputType.number,
                            maxLength: 4, obscureText: true, required: true)),
                        const SizedBox(width: 12),
                        Expanded(child: AppField(
                            label: 'Confirm PIN', hint: '••••',
                            controller: _pinConfirm,
                            keyboardType: TextInputType.number,
                            maxLength: 4, obscureText: true, required: true)),
                      ]),
                      const SizedBox(height: 24),
                      PBtn(
                        label: _loading ? 'Creating account…' : 'Create account',
                        icon: Icons.add_business_rounded,
                        full: true,
                        onTap: _loading ? null : _signUp,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Already have an account? ',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: C.textMuted)),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen())),
                              child: Text('Sign in',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: C.primary,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  _VerifyEmailScreen  (replaces inline _created check)
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyEmailScreen extends StatelessWidget {
  final String email;
  const _VerifyEmailScreen({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 80, height: 80,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [C.green, C.greenDark]),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: C.green.withValues(alpha: 0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.mark_email_read_outlined,
                      color: C.bg, size: 40),
                ),
                Text('Check your email',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: C.white),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'We sent a verification link to\n$email\n\n'
                  'Click the link in your email to finish setting up your shop. '
                  'Your data will be saved automatically once verified.',
                  style: GoogleFonts.inter(
                      fontSize: 14, color: C.textMuted, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                PBtn(
                  label: 'Back to sign in',
                  full: true,
                  onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
