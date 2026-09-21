// ─────────────────────────────────────────────────────────────────────────────
//  screens/customer_detail.dart  —  Issue 7: Full Customer Profile Page
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import 'add_repair.dart';
import 'cust_form.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always watch live state so stats stay current after jobs change
    final customers  = ref.watch(customersProvider);
    final cust       = customers.firstWhere(
        (c) => c.customerId == customer.customerId,
        orElse: () => customer);
    final allJobs    = ref.watch(jobsProvider);
    final custJobs   = allJobs
        .where((j) => j.customerId == cust.customerId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final openJobs   = custJobs.where((j) => j.isActive).toList();
    final doneJobs   = custJobs.where((j) => j.isCompleted).toList();

    return Scaffold(
      backgroundColor: C.bg,
      body: CustomScrollView(
        slivers: [
          // ── Collapsing header ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: C.bgElevated,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: C.white),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CustomerFormScreen(customer: cust))),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _HeaderGradient(cust: cust),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── KPI row ─────────────────────────────────────────────────
                Row(children: [
                  _kpi('🔧', '${custJobs.length}', 'Total\nRepairs', C.primary),
                  const SizedBox(width: 8),
                  _kpi('💰',
                      cust.totalSpend >= 1000
                          ? '₹${(cust.totalSpend / 1000).toStringAsFixed(1)}k'
                          : '₹${cust.totalSpend.toStringAsFixed(0)}',
                      'Total\nSpend', C.green),
                  const SizedBox(width: 8),
                  _kpi('🟢', '${openJobs.length}', 'Open\nJobs', C.yellow),
                  const SizedBox(width: 8),
                  _kpi('✅', '${doneJobs.length}', 'Done', Colors.teal),
                ]),
                const SizedBox(height: 16),

                // ── Quick actions ────────────────────────────────────────────
                Row(children: [
                  Expanded(child: PBtn(
                    label: '🔧  New Job',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AddRepairScreen(preselectedCustomer: cust))),
                    full: true,
                    color: C.green,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: PBtn(
                    label: '✏️  Edit',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CustomerFormScreen(customer: cust))),
                    full: true,
                    outline: true,
                    color: C.primary,
                  )),
                ]),
                const SizedBox(height: 20),

                // ── Contact info ─────────────────────────────────────────────
                _Section('CONTACT INFORMATION', [
                  _infoRow('📱', 'Phone',   cust.phone),
                  if (cust.email.isNotEmpty)
                    _infoRow('✉️', 'Email',  cust.email),
                  if (cust.address.isNotEmpty)
                    _infoRow('📍', 'Address', cust.address),
                  _infoRow('📅', 'Customer since',
                      cust.createdAt.length >= 10
                          ? cust.createdAt.substring(0, 10)
                          : cust.createdAt),
                ]),
                const SizedBox(height: 16),

                // ── Loyalty & tier ───────────────────────────────────────────
                _Section('LOYALTY & TIER', [
                  _infoRow('👑', 'Tier',   cust.tier),
                  _infoRow('⭐', 'Points', '${cust.points} pts'),
                  if (cust.isVip)
                    _infoRow('💎', 'Status', 'VIP Customer'),
                  if (cust.isBlacklisted)
                    _infoRow('🚫', 'Status', 'Blacklisted'),
                ]),
                const SizedBox(height: 16),

                // ── Open jobs ────────────────────────────────────────────────
                if (openJobs.isNotEmpty) ...[
                  _SectionTitle('OPEN JOBS (${openJobs.length})'),
                  ...openJobs.map((j) => _JobCard(j)),
                  const SizedBox(height: 16),
                ],

                // ── Completed jobs ───────────────────────────────────────────
                _SectionTitle('REPAIR HISTORY (${custJobs.length})'),
                if (custJobs.isEmpty)
                  const _Empty('No repairs yet')
                else
                  ...custJobs.map((j) => _JobCard(j)),
                const SizedBox(height: 16),

                // ── Recent activity timeline ─────────────────────────────────
                if (custJobs.isNotEmpty) ...[
                  const _SectionTitle('RECENT ACTIVITY'),
                  _Timeline(custJobs.take(5).toList()),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String icon, String val, String label, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: C.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.border),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(val, style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 14, color: color)),
          Text(label, textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 9, color: C.textMuted)),
        ]),
      ));

  Widget _infoRow(String icon, String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Text('$label:', style: GoogleFonts.inter(
          fontSize: 12, color: C.textMuted, fontWeight: FontWeight.w500)),
      const SizedBox(width: 6),
      Expanded(child: Text(val, style: GoogleFonts.inter(
          fontSize: 13, color: C.white, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _HeaderGradient extends StatelessWidget {
  final Customer cust;
  const _HeaderGradient({required this.cust});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0A1628), Color(0xFF0099CC)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: SafeArea(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 32),
        Stack(alignment: Alignment.center, children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(cust.name[0],
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 28, color: Colors.white)),
          ),
          if (cust.isVip)
            const Positioned(bottom: 0, right: 0,
                child: Text('👑', style: TextStyle(fontSize: 18))),
        ]),
        const SizedBox(height: 8),
        Text(cust.name, style: GoogleFonts.plusJakartaSans(
            fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(cust.phone,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        Pill(cust.tier, color: C.tierColor(cust.tier)),
      ]),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) => SCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: C.textMuted, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      const Divider(color: C.border, height: 1),
      const SizedBox(height: 8),
      ...children,
    ]),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: C.textMuted, letterSpacing: 0.8)),
  );
}

class _JobCard extends StatelessWidget {
  final Job job;
  const _JobCard(this.job);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      decoration: BoxDecoration(
        color: C.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: C.statusColor(job.status),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${job.brand} ${job.model}',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, fontSize: 13, color: C.text)),
                    const SizedBox(height: 2),
                    Text('${job.jobNumber}  ·  ${job.createdAt.substring(0, 10)}',
                        style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
                    if (job.problem.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(job.problem,
                            style: GoogleFonts.inter(fontSize: 11, color: C.textDim),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                )),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Pill('${C.statusIcon(job.status)} ${job.status}',
                      color: C.statusColor(job.status), small: true),
                  const SizedBox(height: 4),
                  Text(fmtMoney(job.totalAmount), style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: C.primary)),
                ]),
              ]),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Timeline extends StatelessWidget {
  final List<Job> jobs;
  const _Timeline(this.jobs);

  @override
  Widget build(BuildContext context) {
    final entries = <Map<String, String>>[];
    for (final j in jobs) {
      for (final t in j.timeline.reversed.take(2)) {
        entries.add({
          'status': t.status,
          'time'  : t.time.length >= 10 ? t.time.substring(0, 10) : t.time,
          'by'    : t.by,
          'note'  : t.note,
          'job'   : '${j.brand} ${j.model}',
        });
      }
    }
    entries.sort((a, b) => b['time']!.compareTo(a['time']!));

    return SCard(
      child: Column(
        children: entries.take(8).map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 8, height: 8, margin: const EdgeInsets.only(top: 4, right: 10),
              decoration: const BoxDecoration(
                color: C.primary, shape: BoxShape.circle),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['status']}  —  ${e['job']}',
                  style: GoogleFonts.inter(fontSize: 12, color: C.text,
                      fontWeight: FontWeight.w600)),
              if ((e['note'] ?? '').isNotEmpty)
                Text(e['note']!, style: GoogleFonts.inter(fontSize: 11, color: C.textMuted)),
              Text('${e['time']}  ·  ${e['by']}',
                  style: GoogleFonts.inter(fontSize: 10, color: C.textDim)),
            ])),
          ]),
        )).toList(),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty(this.msg);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(msg,
          style: GoogleFonts.inter(fontSize: 13, color: C.textMuted)),
    ),
  );
}
