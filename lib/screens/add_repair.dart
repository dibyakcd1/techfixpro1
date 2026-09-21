// ─────────────────────────────────────────────────────────────────────────────
//  screens/add_repair.dart  —  Unified name-or-phone search + inline quick-add
//
//  UX FLOW:
//   1. Single search field — type name OR phone (≥2 chars triggers suggestions).
//   2. Predictive dropdown shows matching customers with highlighted match text.
//   3. Tap a suggestion → confirmed customer tile appears instantly.
//   4. No matches → "Not found" banner → ➕ Quick-Add panel expands inline.
//      Quick-Add pre-fills whatever the user typed (name or phone).
//   5. Confirmed customer + device/problem → Save creates job immediately.
//
//  FIXES retained:
//   ✅ Phone normalised via PhoneNormalizer.
//   ✅ Atomic job number via JobNumberService.
//   ✅ AuditLogService on customer + job creation.
//   ✅ CustomerStatsService.refresh() after job creation.
//   ✅ customerId null (not '') → satisfies FK constraint.
//   ✅ Resilient dual-payload insert for customers and jobs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../services/supabase_service.dart';
import '../services/phone_normalizer.dart';
import '../services/job_number_service.dart';
import '../services/audit_log_service.dart';
import '../services/customer_stats_service.dart';

class AddRepairScreen extends ConsumerStatefulWidget {
  final Customer? preselectedCustomer;
  const AddRepairScreen({super.key, this.preselectedCustomer});

  @override
  ConsumerState<AddRepairScreen> createState() => _AddRepairScreenState();
}

class _AddRepairScreenState extends ConsumerState<AddRepairScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Customer search ───────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController(); // unified name-or-phone field
  final _qNameCtrl  = TextEditingController(); // quick-add: name
  final _qPhoneCtrl = TextEditingController(); // quick-add: phone
  final _qEmailCtrl = TextEditingController(); // quick-add: email (optional)

  Customer? _selectedCustomer;
  bool _showSuggestions = false;
  bool _showQuickAdd     = false;
  bool _quickAddDone     = false;
  bool _isSelectingCustomer = false; // Flag to prevent onSearchChanged from clearing selection

  // ── Device / job fields ───────────────────────────────────────────────────
  final _brand   = TextEditingController();
  final _model   = TextEditingController();
  final _imei    = TextEditingController();
  final _problem = TextEditingController();
  final _notes   = TextEditingController();

  String _priority = 'Normal';
  String _techId   = '';
  String _techName = '';
  bool   _saving   = false;

  // ─ helpers ────────────────────────────────────────────────────────────────
  String get _query => _searchCtrl.text.trim();
  bool   get _hasQuery => _query.length >= 2;

  bool _looksLikePhone(String q) =>
      q.replaceAll(RegExp(r'[^0-9]'), '').length >= 4;

  List<Customer> _suggest(List<Customer> all) {
    if (!_hasQuery) return [];
    final q    = _query.toLowerCase();
    final norm = PhoneNormalizer.normalize(_query);
    return all.where((c) {
      final nameMatch  = c.name.toLowerCase().contains(q);
      final phoneNorm  = PhoneNormalizer.normalize(c.phone);
      final phoneMatch = norm.isNotEmpty &&
          (phoneNorm.contains(norm) ||
           norm.contains(phoneNorm.length > 6
               ? phoneNorm.substring(phoneNorm.length - 6) : phoneNorm));
      return nameMatch || phoneMatch;
    }).take(6).toList();
  }

  @override
  void initState() {
    super.initState();
    final c = widget.preselectedCustomer;
    if (c != null) {
      _searchCtrl.text    = c.name;
      _selectedCustomer   = c;
    }
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose(); _qNameCtrl.dispose();
    _qPhoneCtrl.dispose(); _qEmailCtrl.dispose();
    _brand.dispose();  _model.dispose();   _imei.dispose();
    _problem.dispose(); _notes.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // If we're currently selecting a customer, don't reset anything
    if (_isSelectingCustomer) return;

    setState(() {
      _selectedCustomer = null;
      _showQuickAdd     = false;
      _quickAddDone     = false;
      _showSuggestions  = _hasQuery;
      // Pre-fill quick-add fields based on what user typed
      if (_looksLikePhone(_query)) {
        _qPhoneCtrl.text = _query;
        _qNameCtrl.clear();
      } else {
        _qNameCtrl.text  = _searchCtrl.text.trim();
        _qPhoneCtrl.clear();
      }
    });
  }

  void _selectCustomer(Customer c) {
    _isSelectingCustomer = true;
    setState(() {
      _selectedCustomer = c;
      _searchCtrl.text  = c.name;
      _showSuggestions  = false;
      _showQuickAdd     = false;
      _quickAddDone     = false;
    });
    // Reset the flag after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _isSelectingCustomer = false;
      }
    });
    FocusScope.of(context).unfocus();
  }

  void _openQuickAdd() {
    setState(() {
      _showSuggestions = false;
      _showQuickAdd    = true;
    });
  }

  void _confirmQuickAdd() {
    if (_qNameCtrl.text.trim().isEmpty || _qPhoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Name and phone are required.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: C.accent, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    setState(() => _quickAddDone = true);
    FocusScope.of(context).unfocus();
  }

  void _resetCustomer() {
    setState(() {
      _selectedCustomer = null;
      _showSuggestions  = false;
      _showQuickAdd     = false;
      _quickAddDone     = false;
      _searchCtrl.clear();
      _qNameCtrl.clear();
      _qPhoneCtrl.clear();
      _qEmailCtrl.clear();
    });
  }

  // ─ resilient insert ───────────────────────────────────────────────────────
  Future<void> _insertResilient(
      String table, List<Map<String, dynamic>> dataSets) async {
    for (final data in dataSets) {
      try {
        await SupabaseService.instance.client.from(table).insert(data);
        debugPrint('✅ Inserted $table (${data.keys.length} fields)');
        return;
      } catch (e) {
        debugPrint('⚠️ Insert $table failed: $e');
      }
    }
    throw Exception('Failed to insert $table with all datasets');
  }

  // ─ save ───────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Must have a confirmed customer
    final hasCustomer = _selectedCustomer != null || _quickAddDone;
    if (!hasCustomer) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please select or add a customer first.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: C.accent, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    setState(() => _saving = true);

    try {
      final shopId   = ref.read(shopIdProvider);
      if (shopId.isEmpty) throw Exception('No shop linked — please log in again.');
      final session  = ref.read(currentUserProvider).asData?.value;
      final settings = ref.read(settingsProvider);
      final now      = DateTime.now();
      final jobId    = 'job-${now.millisecondsSinceEpoch}';
      final prefix   = settings.invoicePrefix.isNotEmpty ? settings.invoicePrefix : 'JOB';
      final jobNumber = await JobNumberService.nextJobNumber(
          shopId: shopId, prefix: prefix);

      final String customerId;
      String  customerName;
      String  customerPhone;

      if (_selectedCustomer != null) {
        customerId    = _selectedCustomer!.customerId;
        customerName  = _selectedCustomer!.name;
        customerPhone = _selectedCustomer!.phone;
      } else {
        // Quick-add new customer
        customerId    = 'cust-${now.millisecondsSinceEpoch}';
        customerName  = _qNameCtrl.text.trim();
        customerPhone = PhoneNormalizer.normalize(_qPhoneCtrl.text.trim());

        final newCustomer = Customer(
          customerId   : customerId,
          shopId       : shopId,
          name         : customerName,
          phone        : customerPhone,
          email        : _qEmailCtrl.text.trim(),
          address      : '',
          tier         : 'Bronze',
          isVip        : false,
          isBlacklisted: false,
          points       : 0,
          repairsCount : 0,
          totalSpend   : 0,
          notes        : '',
          createdAt    : now.toIso8601String(),
          updatedAt    : now.toIso8601String(),
        );

        await _insertResilient('customers', [
          {
            'customerId'   : customerId,
            'name'         : customerName,
            'phone'        : customerPhone,
            'email'        : _qEmailCtrl.text.trim(),
            'address'      : '',
            'tier'         : 'Bronze',
            'isVip'        : false,
            'isBlacklisted': false,
            'points'       : 0,
            'repairsCount' : 0,
            'totalSpend'   : 0.0,
            'shopId'       : shopId,
            'notes'        : '',
            'createdAt'    : now.toIso8601String(),
            'updatedAt'    : now.toIso8601String(),
          },
          {
            'customerId': customerId,
            'shopId'    : shopId,
            'name'      : customerName,
            'phone'     : customerPhone,
          },
        ]);

        ref.read(customersProvider.notifier).add(newCustomer);

        _unawaited(AuditLogService.log(
          shopId  : shopId,
          userId  : session?.uid ?? '',
          action  : AuditLogService.create,
          entity  : 'customer',
          entityId: customerId,
          details : {'name': customerName, 'phone': customerPhone},
        ));
      }

      // ── Insert job ────────────────────────────────────────────────────────
      await _insertResilient('jobs', [
        {
          'jobId'           : jobId,
          'jobNumber'       : jobNumber,
          'shopId'          : shopId,
          'customerId'      : customerId,
          'customerName'    : customerName,
          'customerPhone'   : customerPhone,
          'brand'           : _brand.text.trim(),
          'model'           : _model.text.trim(),
          'imei'            : _imei.text.trim(),
          'color'           : '',
          'problem'         : _problem.text.trim(),
          'notes'           : _notes.text.trim(),
          'status'          : 'Checked In',
          'previousStatus'  : null,
          'holdReason'      : null,
          'priority'        : _priority,
          'technicianId'    : _techId,
          'technicianName'  : _techName.isEmpty ? 'Unassigned' : _techName,
          'laborCost'       : 0.0,
          'partsCost'       : 0.0,
          'discountAmount'  : 0.0,
          'taxAmount'       : 0.0,
          'totalAmount'     : 0.0,
          'partsUsed'       : <dynamic>[],
          'intakePhotos'    : <dynamic>[],
          'completionPhotos': <dynamic>[],
          'notificationSent': false,
          'reopenCount'     : 0,
          'createdAt'       : now.toIso8601String(),
          'updatedAt'       : now.toIso8601String(),
          'timeline'        : [
            {
              'status': 'Checked In',
              'time'  : now.toIso8601String(),
              'by'    : session?.displayName ?? 'Staff',
              'type'  : 'flow',
              'note'  : 'Job created',
            }
          ],
        },
        {
          'jobId'       : jobId,
          'jobNumber'   : jobNumber,
          'shopId'      : shopId,
          'customerName': customerName,
          'brand'       : _brand.text.trim(),
          'model'       : _model.text.trim(),
          'status'      : 'Checked In',
          'createdAt'   : now.toIso8601String(),
          'updatedAt'   : now.toIso8601String(),
        },
      ]);

      // ── Optimistic local state ────────────────────────────────────────────
      final newJob = Job(
        jobId           : jobId,
        jobNumber       : jobNumber,
        shopId          : shopId,
        customerId      : customerId,
        customerName    : customerName,
        customerPhone   : customerPhone,
        brand           : _brand.text.trim(),
        model           : _model.text.trim(),
        imei            : _imei.text.trim(),
        color           : '',
        problem         : _problem.text.trim(),
        notes           : _notes.text.trim(),
        status          : 'Checked In',
        previousStatus  : null,
        holdReason      : null,
        priority        : _priority,
        technicianId    : _techId,
        technicianName  : _techName.isEmpty ? 'Unassigned' : _techName,
        laborCost       : 0,
        partsCost       : 0,
        discountAmount  : 0,
        totalAmount     : 0,
        partsUsed       : const [],
        intakePhotos    : const [],
        completionPhotos: const [],
        timeline        : [
          TimelineEntry(
            status: 'Checked In',
            time  : now.toIso8601String(),
            by    : session?.displayName ?? 'Staff',
            note  : 'Job created',
            type  : 'flow',
          ),
        ],
        notificationSent: false,
        reopenCount     : 0,
        estimatedEndDate: '',
        createdAt       : now.toIso8601String(),
        updatedAt       : now.toIso8601String(),
      );
      ref.read(jobsProvider.notifier).addJob(newJob);

      _unawaited(CustomerStatsService.refresh(
          ref: ref, customerId: customerId, shopId: shopId));

      _unawaited(AuditLogService.log(
        shopId  : shopId,
        userId  : session?.uid ?? '',
        action  : AuditLogService.create,
        entity  : 'job',
        entityId: jobId,
        details : {'jobNumber': jobNumber, 'customerId': customerId},
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $jobNumber created',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          backgroundColor: C.green, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
          backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─ build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final techs    = ref.watch(techsProvider);
    final allCusts = ref.watch(customersProvider);
    final matches  = _suggest(allCusts);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('New Repair Job',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 15,
                    color: _saving ? C.textMuted : C.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [

            // ══════════════════════════════════════════════════════════════
            //  CUSTOMER
            // ══════════════════════════════════════════════════════════════
            const SLabel('CUSTOMER'),

            // ── Confirmed tile (existing or quick-added) ──────────────────
            if (_selectedCustomer != null || _quickAddDone) ...[
              _ConfirmedTile(
                name   : _selectedCustomer?.name  ?? _qNameCtrl.text.trim(),
                phone  : _selectedCustomer?.phone ?? _qPhoneCtrl.text.trim(),
                isNew  : _selectedCustomer == null,
                isVip  : _selectedCustomer?.isVip ?? false,
                onEdit : _resetCustomer,
              ),
              const SizedBox(height: 16),
            ]

            // ── Search + suggestions ──────────────────────────────────────
            else ...[
              _SearchField(
                controller: _searchCtrl,
                onChanged : (_) => setState(() {}),
                onClear   : _resetCustomer,
              ),
              const SizedBox(height: 6),

              // Suggestions overlay-style list
              if (_showSuggestions && matches.isNotEmpty)
                _SuggestionList(
                  matches  : matches,
                  query    : _query,
                  onSelect : _selectCustomer,
                  onAddNew : _openQuickAdd,
                ),

              // "Not found" banner
              if (_hasQuery && matches.isEmpty && !_showQuickAdd)
                _NotFoundBanner(query: _query, onAdd: _openQuickAdd),

              // Inline quick-add form
              if (_showQuickAdd)
                _QuickAddForm(
                  nameCtrl  : _qNameCtrl,
                  phoneCtrl : _qPhoneCtrl,
                  emailCtrl : _qEmailCtrl,
                  onConfirm : _confirmQuickAdd,
                  onCancel  : () => setState(() {
                    _showQuickAdd = false;
                    _showSuggestions = _hasQuery;
                  }),
                ),

              const SizedBox(height: 8),
            ],

            // ══════════════════════════════════════════════════════════════
            //  DEVICE
            // ══════════════════════════════════════════════════════════════
            const SLabel('DEVICE'),
            _field('Brand', _brand, required: true,
                hint: 'e.g. Samsung, Apple, OnePlus'),
            _field('Model', _model, required: true,
                hint: 'e.g. Galaxy S24, iPhone 15'),
            _field('IMEI / Serial', _imei,
                hint: '15-digit IMEI or serial number',
                type: TextInputType.number),

            // ══════════════════════════════════════════════════════════════
            //  PROBLEM & NOTES
            // ══════════════════════════════════════════════════════════════
            const SLabel('PROBLEM & NOTES'),
            _field('Problem Description', _problem, required: true,
                hint: 'e.g. Screen cracked, battery drains fast',
                maxLines: 3),
            _field('Internal Notes', _notes,
                hint: 'Accessories received, customer remarks…',
                maxLines: 2),

            // ══════════════════════════════════════════════════════════════
            //  ASSIGNMENT
            // ══════════════════════════════════════════════════════════════
            const SLabel('ASSIGNMENT'),
            SCard(child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Priority', style: GoogleFonts.inter(
                    fontSize: 14, color: C.text, fontWeight: FontWeight.w600)),
                DropdownButton<String>(
                  value: _priority,
                  dropdownColor: C.bgElevated,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _priority = v ?? 'Normal'),
                  items: ['Normal', 'Urgent', 'Express'].map((p) =>
                      DropdownMenuItem(value: p,
                        child: Text(p, style: GoogleFonts.inter(
                            fontSize: 13, color: _priorityColor(p),
                            fontWeight: FontWeight.w700)),
                      )).toList(),
                ),
              ]),
              if (techs.isNotEmpty) ...[
                const Divider(color: C.border, height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Assign To', style: GoogleFonts.inter(
                      fontSize: 14, color: C.text, fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: _techId.isEmpty ? '' : _techId,
                    dropdownColor: C.bgElevated,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) {
                      final t = techs.firstWhere((t) => t.techId == v,
                          orElse: () => techs.first);
                      setState(() {
                        _techId   = v ?? '';
                        _techName = (v != null && v.isNotEmpty) ? t.name : '';
                      });
                    },
                    items: [
                      const DropdownMenuItem(value: '',
                          child: Text('Unassigned',
                              style: TextStyle(color: Colors.grey))),
                      ...techs.map((t) => DropdownMenuItem(value: t.techId,
                            child: Text(t.name, style: GoogleFonts.inter(
                                fontSize: 13, color: C.white)))),
                    ],
                  ),
                ]),
              ],
            ])),

            const SizedBox(height: 24),
            PBtn(
              label : _saving ? 'Creating job…' : '➕  Create Repair Job',
              onTap : _saving ? null : _save,
              full  : true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    String? hint, TextInputType? type,
    bool required = false, int maxLines = 1,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          text: label.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
              color: C.textMuted, letterSpacing: 0.5),
          children: required
              ? [TextSpan(text: ' *', style: GoogleFonts.inter(color: C.accent))]
              : [],
        )),
        const SizedBox(height: 5),
        TextFormField(
          controller : ctrl,
          keyboardType: type,
          maxLines   : maxLines,
          style      : GoogleFonts.inter(fontSize: 13, color: C.text),
          decoration : InputDecoration(hintText: hint),
          validator  : required
              ? (v) => (v == null || v.trim().isEmpty)
                  ? '$label is required' : null
              : null,
        ),
        const SizedBox(height: 12),
      ]);

  Color _priorityColor(String p) => switch (p) {
    'Express' => Colors.red,
    'Urgent'  => Colors.orange,
    _         => C.primary,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  _SearchField — single field for name OR phone
// ─────────────────────────────────────────────────────────────────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onClear;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SEARCH CUSTOMER', style: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: C.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 5),
      TextFormField(
        controller  : controller,
        onChanged   : onChanged,
        style       : GoogleFonts.inter(fontSize: 14, color: C.text,
            fontWeight: FontWeight.w500),
        decoration  : InputDecoration(
          hintText   : 'Type name or phone number…',
          prefixIcon : const Icon(Icons.search, color: C.textMuted, size: 20),
          suffixIcon : controller.text.isNotEmpty
              ? IconButton(
                  icon    : const Icon(Icons.close, size: 16, color: C.textMuted),
                  onPressed: onClear)
              : null,
        ),
      ),
      const SizedBox(height: 4),
      Text('Search by name (e.g. "Rajesh") or phone (e.g. "9876…")',
          style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _SuggestionList — predictive dropdown with highlighted match text
// ─────────────────────────────────────────────────────────────────────────────
class _SuggestionList extends StatelessWidget {
  final List<Customer>     matches;
  final String             query;
  final ValueChanged<Customer> onSelect;
  final VoidCallback       onAddNew;
  const _SuggestionList({
    required this.matches,
    required this.query,
    required this.onSelect,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin    : const EdgeInsets.only(top: 2, bottom: 4),
      decoration: BoxDecoration(
        color       : C.bgCard,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: C.primary.withValues(alpha: 0.35)),
        boxShadow   : [BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 12, offset: const Offset(0, 4),
        )],
      ),
      child: Column(children: [
        // ── suggestion rows ──────────────────────────────────────────────
        ...matches.asMap().entries.map((e) {
          final i = e.key;
          final c = e.value;
          return Column(children: [
            if (i > 0) const Divider(color: C.border, height: 1, indent: 56),
            InkWell(
              borderRadius: BorderRadius.only(
                topLeft    : Radius.circular(i == 0 ? 14 : 0),
                topRight   : Radius.circular(i == 0 ? 14 : 0),
              ),
              onTap: () => onSelect(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [C.primary, C.primaryDark]),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(
                      c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: C.bg),
                    )),
                  ),
                  const SizedBox(width: 12),
                  // Name + phone with highlighted match
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightText(
                          text : c.name,
                          query: query,
                          base : GoogleFonts.inter(
                              fontSize: 13, color: C.text,
                              fontWeight: FontWeight.w700),
                          highlight: GoogleFonts.inter(
                              fontSize: 13, color: C.primary,
                              fontWeight: FontWeight.w800,
                              backgroundColor:
                                  C.primary.withValues(alpha: 0.15))),
                      const SizedBox(height: 2),
                      _HighlightText(
                          text : c.phone,
                          query: query,
                          base : GoogleFonts.inter(
                              fontSize: 12, color: C.textMuted),
                          highlight: GoogleFonts.inter(
                              fontSize: 12, color: C.primary,
                              fontWeight: FontWeight.w700,
                              backgroundColor:
                                  C.primary.withValues(alpha: 0.12))),
                    ],
                  )),
                  // Badges
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (c.isVip)
                      _badge('VIP 👑', Colors.amber),
                    if (c.repairsCount > 0) ...[
                      const SizedBox(height: 3),
                      _badge('${c.repairsCount} jobs', C.textMuted),
                    ],
                  ]),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 16, color: C.textMuted),
                ]),
              ),
            ),
          ]);
        }),

        // ── "Add new" footer row ─────────────────────────────────────────
        const Divider(color: C.border, height: 1),
        InkWell(
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14)),
          onTap: onAddNew,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color : C.accent.withValues(alpha: 0.15),
                  shape : BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_alt_1,
                    size: 18, color: C.accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Add new customer…',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: C.accent,
                      fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right, size: 16, color: C.accent),
            ]),
          ),
        ),
      ]),
    );
  }

  static Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color       : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: GoogleFonts.inter(
        fontSize: 10, color: color, fontWeight: FontWeight.w700)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HighlightText — bolds the matching fragment inside a text string
// ─────────────────────────────────────────────────────────────────────────────
class _HighlightText extends StatelessWidget {
  final String    text;
  final String    query;
  final TextStyle base;
  final TextStyle highlight;
  const _HighlightText({
    required this.text,
    required this.query,
    required this.base,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final lText  = text.toLowerCase();
    final lQuery = query.toLowerCase();
    final idx    = lText.indexOf(lQuery);
    if (idx < 0 || query.isEmpty) {
      return Text(text, style: base);
    }
    return RichText(text: TextSpan(children: [
      if (idx > 0)
        TextSpan(text: text.substring(0, idx), style: base),
      TextSpan(text: text.substring(idx, idx + query.length), style: highlight),
      if (idx + query.length < text.length)
        TextSpan(text: text.substring(idx + query.length), style: base),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _NotFoundBanner
// ─────────────────────────────────────────────────────────────────────────────
class _NotFoundBanner extends StatelessWidget {
  final String       query;
  final VoidCallback onAdd;
  const _NotFoundBanner({required this.query, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin    : const EdgeInsets.only(top: 6, bottom: 4),
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color       : C.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: C.accent.withValues(alpha: 0.30)),
      ),
      child: Row(children: [
        const Icon(Icons.person_off_outlined, color: C.accent, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No match for "$query"',
                style: GoogleFonts.inter(
                    fontSize: 13, color: C.text, fontWeight: FontWeight.w700)),
            Text('Create a new customer and continue',
                style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
          ],
        )),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon : const Icon(Icons.person_add_alt_1, size: 15),
          label: Text('Add New', style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: C.accent,
            foregroundColor: C.white,
            padding  : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            shape    : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _QuickAddForm — inline customer creation (no navigation)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickAddForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final VoidCallback          onConfirm;
  final VoidCallback          onCancel;

  const _QuickAddForm({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin    : const EdgeInsets.only(top: 6, bottom: 4),
      padding   : const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color       : C.bgCard,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: C.primary.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            padding   : const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color       : C.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person_add_alt_1, color: C.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Text('New Customer', style: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w800, color: C.primary)),
          const Spacer(),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close, size: 18, color: C.textMuted),
          ),
        ]),
        const SizedBox(height: 14),

        // Name
        _label('Full Name *'),
        TextFormField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          style     : GoogleFonts.inter(fontSize: 13, color: C.text),
          decoration: const InputDecoration(
              hintText : 'e.g. Rajesh Kumar',
              prefixIcon: Icon(Icons.person_outline,
                  size: 18, color: C.textMuted)),
        ),
        const SizedBox(height: 12),

        // Phone
        _label('Phone Number *'),
        TextFormField(
          controller  : phoneCtrl,
          keyboardType: TextInputType.phone,
          style       : GoogleFonts.inter(fontSize: 13, color: C.text),
          decoration  : const InputDecoration(
              hintText  : '+91 XXXXX XXXXX',
              prefixIcon: Icon(Icons.phone_outlined,
                  size: 18, color: C.textMuted)),
        ),
        const SizedBox(height: 12),

        // Email (optional)
        _label('Email  (optional)'),
        TextFormField(
          controller  : emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style       : GoogleFonts.inter(fontSize: 13, color: C.text),
          decoration  : const InputDecoration(
              hintText  : 'email@example.com',
              prefixIcon: Icon(Icons.mail_outline,
                  size: 18, color: C.textMuted)),
        ),
        const SizedBox(height: 16),

        // Confirm
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onConfirm,
            icon : const Icon(Icons.check_circle_outline, size: 17),
            label: Text('Confirm & Continue',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary,
              foregroundColor: C.bg,
              padding  : const EdgeInsets.symmetric(vertical: 13),
              shape    : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text.toUpperCase(), style: GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: C.textMuted, letterSpacing: 0.5)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ConfirmedTile — green "customer locked in" card
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmedTile extends StatelessWidget {
  final String  name;
  final String  phone;
  final bool    isNew;
  final bool    isVip;
  final VoidCallback onEdit;

  const _ConfirmedTile({
    required this.name,
    required this.phone,
    required this.isNew,
    required this.isVip,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color       : C.green.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border      : Border.all(color: C.green.withValues(alpha: 0.40)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius         : 20,
          backgroundColor: C.green.withValues(alpha: 0.20),
          child          : Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: C.green),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(name, style: GoogleFonts.inter(
                  fontSize: 13, color: C.text, fontWeight: FontWeight.w700)),
              if (isNew) ...[
                const SizedBox(width: 6),
                _chip('NEW', C.primary),
              ],
              if (isVip) ...[
                const SizedBox(width: 4),
                _chip('VIP 👑', Colors.amber),
              ],
            ]),
            const SizedBox(height: 2),
            Text(phone, style: GoogleFonts.inter(
                fontSize: 12, color: C.textMuted)),
          ],
        )),
        const Icon(Icons.check_circle, color: C.green, size: 20),
        IconButton(
          icon    : const Icon(Icons.edit_outlined, size: 16, color: C.textMuted),
          tooltip : 'Change customer',
          onPressed: onEdit,
        ),
      ]),
    );
  }

  static Widget _chip(String label, Color color) => Container(
    padding   : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color       : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: GoogleFonts.inter(
        fontSize: 9, color: color,
        fontWeight: FontWeight.w800, letterSpacing: 0.5)),
  );
}

/// Fire-and-forget.
void _unawaited(Future<void> future) {
  future.catchError((Object e) => debugPrint('⚠️ background task error: $e'));
}
