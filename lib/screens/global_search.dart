// ─────────────────────────────────────────────────────────────────────────────
//  screens/global_search.dart  —  Issue 5: Universal Global Search
//
//  Searches across: Customer Name, Phone, IMEI, Serial, Job Number,
//  Invoice Number, Device Model, Technician Name.
//
//  Usage:
//    Navigator.of(context).push(
//      MaterialPageRoute(builder: (_) => const GlobalSearchScreen()));
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

// ── Search result wrapper ─────────────────────────────────────────────────────
class _SearchResult {
  final String type;    // 'job' | 'customer'
  final String title;
  final String subtitle;
  final String badge;
  final Color  badgeColor;
  final Job?      job;
  final Customer? customer;

  _SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    this.job,
    this.customer,
  });
}

class GlobalSearchScreen extends ConsumerStatefulWidget {
  final void Function(String jobId)? onOpenJob;
  const GlobalSearchScreen({super.key, this.onOpenJob});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends ConsumerState<GlobalSearchScreen> {
  final _ctrl     = TextEditingController();
  String _query   = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<_SearchResult> _search(List<Job> jobs, List<Customer> customers) {
    final q = _query.toLowerCase().trim();
    if (q.length < 2) return [];

    final results = <_SearchResult>[];

    // ── Jobs ─────────────────────────────────────────────────────────────────
    for (final j in jobs) {
      final match = j.jobNumber.toLowerCase().contains(q)      ||
                    j.customerName.toLowerCase().contains(q)   ||
                    j.customerPhone.contains(q)                ||
                    j.imei.toLowerCase().contains(q)           ||
                    j.model.toLowerCase().contains(q)          ||
                    j.brand.toLowerCase().contains(q)          ||
                    j.technicianName.toLowerCase().contains(q) ||
                    (j.invoiceId?.toLowerCase().contains(q) ?? false);
      if (!match) continue;
      results.add(_SearchResult(
        type      : 'job',
        title     : '${j.brand} ${j.model}  ·  ${j.jobNumber}',
        subtitle  : '${j.customerName}  ·  ${j.customerPhone}  ·  ${j.technicianName}',
        badge     : j.status,
        badgeColor: C.statusColor(j.status),
        job       : j,
      ));
    }

    // ── Customers ─────────────────────────────────────────────────────────────
    for (final c in customers) {
      final match = c.name.toLowerCase().contains(q)  ||
                    c.phone.contains(q)                ||
                    c.email.toLowerCase().contains(q);
      if (!match) continue;
      results.add(_SearchResult(
        type      : 'customer',
        title     : c.name,
        subtitle  : '${c.phone}  ·  ${c.email}',
        badge     : c.tier,
        badgeColor: C.tierColor(c.tier),
        customer  : c,
      ));
    }

    // Sort: jobs first, then customers
    results.sort((a, b) => a.type.compareTo(b.type));
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final jobs      = ref.watch(jobsProvider);
    final customers = ref.watch(customersProvider);
    final results   = _search(jobs, customers);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 15, color: C.white),
          decoration: InputDecoration(
            hintText: 'Job #, IMEI, customer, model, technician…',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: C.textMuted),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: C.textMuted),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: _query.length < 2
          ? _EmptyHint()
          : results.isEmpty
              ? _NoResults(query: _query)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: results.length,
                  itemBuilder: (_, i) => _ResultTile(
                    result: results[i],
                    query: _query,
                    onTap: () => _open(results[i]),
                  ),
                ),
    );
  }

  void _open(_SearchResult r) {
    if (r.type == 'job' && r.job != null) {
      Navigator.of(context).pop();
      widget.onOpenJob?.call(r.job!.jobId);
    } else if (r.type == 'customer' && r.customer != null) {
      // Navigate to customer detail
      Navigator.of(context).pop();
      // The parent shell can handle routing via onOpenJob or pushNamed
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Search anything',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
          const SizedBox(height: 8),
          Text(
            'Job number · Customer name · Phone\nIMEI · Device model · Technician',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: C.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😶', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('No results for "$query"',
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w700, color: C.textMuted)),
          ],
        ),
      );
}

// ── Result tile ───────────────────────────────────────────────────────────────
class _ResultTile extends StatelessWidget {
  final _SearchResult result;
  final String query;
  final VoidCallback onTap;
  const _ResultTile({required this.result, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = result.type == 'job' ? '🔧' : '👤';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: result.badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Highlight(text: result.title, query: query),
                  const SizedBox(height: 2),
                  _Highlight(
                    text: result.subtitle,
                    query: query,
                    style: GoogleFonts.inter(fontSize: 11, color: C.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pill(result.badge, color: result.badgeColor, small: true),
          ],
        ),
      ),
    );
  }
}

// ── Highlight matching query text ─────────────────────────────────────────────
class _Highlight extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  const _Highlight({required this.text, required this.query, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ??
        GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: C.white);
    final q = query.toLowerCase();
    final idx = text.toLowerCase().indexOf(q);
    if (idx < 0 || q.isEmpty) return Text(text, style: base);
    return Text.rich(TextSpan(children: [
      if (idx > 0) TextSpan(text: text.substring(0, idx), style: base),
      TextSpan(
        text: text.substring(idx, idx + q.length),
        style: base.copyWith(
          color: C.primary,
          backgroundColor: C.primary.withValues(alpha: 0.15),
          fontWeight: FontWeight.w800,
        ),
      ),
      if (idx + q.length < text.length)
        TextSpan(text: text.substring(idx + q.length), style: base),
    ]));
  }
}
