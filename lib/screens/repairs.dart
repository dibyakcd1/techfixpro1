import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import 'repair_detail.dart';
import 'add_repair.dart';
import '../services/supabase_service.dart';

class RepairsScreen extends ConsumerStatefulWidget {
  const RepairsScreen({super.key});

  @override
  ConsumerState<RepairsScreen> createState() => _RepairsState();
}

class _RepairsState extends ConsumerState<RepairsScreen> {

  // Manual pull-to-refresh: re-fetches from Supabase and merges into provider.
  // The real-time stream in RootShell handles all live updates automatically;
  // this is only a fallback for connectivity edge cases.
  Future<void> _manualRefresh() async {
    final shopId = ref.read(shopIdProvider);
    if (shopId.isEmpty) return;
    try {
      final response = await SupabaseService.instance.client
          .from('jobs')
          .select()
          .eq('shopId', shopId);
      final list = <Job>[];
      for (final data in response) {
        try { list.add(Job.fromMap(data)); } catch (_) {}
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // Merge: keep any optimistic jobs not yet confirmed by Supabase
      final existing = ref.read(jobsProvider);
      final merged = <String, Job>{};
      for (final j in existing) { merged[j.jobId] = j; }
      for (final j in list)     { merged[j.jobId] = j; } // Supabase is source of truth
      ref.read(jobsProvider.notifier).setAll(merged.values.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final search = ref.watch(searchJobProvider);
    final tab = ref.watch(jobTabProvider);
    // Watch settings — screen must rebuild when tax type/rate changes
    ref.watch(settingsProvider);
    // Watch auth state — triggers rebuild on login/logout
    ref.watch(currentUserProvider);

    // Filter by tab
    List<Job> filtered = jobs.where((j) {
      switch (tab) {
        case 'Active':   return j.isActive;
        case 'On Hold':  return j.isOnHold;
        case 'Ready':    return j.status == 'Ready for Pickup';
        case 'Done':     return j.isCompleted || j.isCancelled;
        default:         return true;
      }
    }).toList();

    // Search filter
    if (search.isNotEmpty) {
      final s = search.toLowerCase();
      filtered = filtered.where((j) =>
          j.jobNumber.toLowerCase().contains(s) ||
          j.customerName.toLowerCase().contains(s) ||
          j.brand.toLowerCase().contains(s) ||
          j.model.toLowerCase().contains(s) ||
          j.problem.toLowerCase().contains(s)).toList();
    }

    // Sort: overdue first, then by creation date desc
    filtered.sort((a, b) {
      if (a.isOverdue && !b.isOverdue) return -1;
      if (!a.isOverdue && b.isOverdue) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    final counts = {
      'All':     jobs.length,
      'Active':  jobs.where((j) => j.isActive).length,
      'On Hold': jobs.where((j) => j.isOnHold).length,
      'Ready':   jobs.where((j) => j.status == 'Ready for Pickup').length,
      'Done':    jobs.where((j) => j.isCompleted || j.isCancelled).length,
    };

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────
          Container(
            color: C.bgElevated,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              onChanged: (v) => ref.read(searchJobProvider.notifier).state = v,
              style: GoogleFonts.inter(fontSize: 13, color: C.text),
              decoration: const InputDecoration(
                hintText: '🔍  Search job number, customer, device...',
                contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
          ),

          // ── Tab bar ───────────────────────────────────────────
          Container(
            color: C.bgElevated,
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              children: counts.entries.map((e) {
                final sel = tab == e.key;
                Color tabColor = C.primary;
                if (e.key == 'On Hold') tabColor = C.yellow;
                if (e.key == 'Done') tabColor = C.textMuted;
                if (e.key == 'Ready') tabColor = C.green;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref.read(jobTabProvider.notifier).state = e.key,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? tabColor.withValues(alpha: 0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: sel ? tabColor : C.border,
                            width: sel ? 2 : 1),
                      ),
                      child: Row(children: [
                        Text(e.key, style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: sel ? tabColor : C.textMuted)),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: sel ? tabColor.withValues(alpha: 0.25) : C.bgCard,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('${e.value}', style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, fontWeight: FontWeight.w800,
                              color: sel ? tabColor : C.textMuted)),
                        ),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Job list ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: C.primary,
              onRefresh: _manualRefresh,
              child: filtered.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('📋', style: TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text('No jobs found', style: GoogleFonts.inter(
                                  fontSize: 16, fontWeight: FontWeight.w700, color: C.textMuted)),
                              const SizedBox(height: 8),
                              Text('Pull down to refresh', style: GoogleFonts.inter(
                                  fontSize: 12, color: C.textDim)),
                            ],
                          )),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _JobCard(
                        job: filtered[i],
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => RepairDetailScreen(jobId: filtered[i].jobId))),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_repairs',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddRepairScreen())),
        backgroundColor: C.primary,
        foregroundColor: C.bg,
        icon: const Icon(Icons.add),
        label: Text('New Job', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ─── Job Card ─────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sc = C.statusColor(job.status);
    final isSpecial = job.isOnHold || job.isCancelled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: C.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.border),
              boxShadow: job.isOverdue
                  ? [BoxShadow(color: C.red.withValues(alpha: 0.15), blurRadius: 16)]
                  : isSpecial
                      ? [BoxShadow(color: sc.withValues(alpha: 0.1), blurRadius: 12)]
                      : [const BoxShadow(color: Color(0x22000000), blurRadius: 6)],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: sc,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // Row 1: Job num + badges + status
                Row(children: [
                  Text(job.jobNumber, style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 13, color: C.white)),
                  const SizedBox(width: 8),
                  if (job.priority != 'Normal')
                    Pill(job.priority,
                        color: job.priority == 'Express' ? C.red : C.yellow,
                        small: true),
                  const SizedBox(width: 4),
                  if (job.isOverdue) const Pill('OVERDUE', color: C.red, small: true),
                  if (job.reopenCount > 0) ...[
                    const SizedBox(width: 4),
                    const Pill('Reopened', color: C.green, small: true),
                  ],
                  const Spacer(),
                  Pill('${C.statusIcon(job.status)} ${job.status}', color: sc, small: true),
                ]),
                const SizedBox(height: 8),

                // Row 2: Device
                Text('${job.brand} ${job.model}',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 15, color: C.white)),
                const SizedBox(height: 2),

                // Row 3: Customer + problem
                Row(children: [
                  const Icon(Icons.person_outline, size: 13, color: C.textMuted),
                  const SizedBox(width: 4),
                  Text(job.customerName,
                      style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                ]),
                const SizedBox(height: 4),
                Text(job.problem,
                    style: GoogleFonts.inter(fontSize: 12, color: C.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),

                // Hold/Cancel reason banner
                if (isSpecial && job.holdReason != null && job.holdReason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sc.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${C.statusIcon(job.status)}  ${job.holdReason}',
                      style: GoogleFonts.inter(fontSize: 11, color: sc),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Warranty badge
                if (job.isUnderWarranty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: C.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: C.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user, size: 12, color: C.green),
                        const SizedBox(width: 4),
                        Text('UNDER WARRANTY', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: C.green)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Row 4: Tech + dates + amount
                Row(children: [
                  if (job.technicianName.isNotEmpty && job.technicianName != 'Unassigned') ...[
                    const Icon(Icons.engineering_outlined, size: 13, color: C.textMuted),
                    const SizedBox(width: 4),
                    Text(job.technicianName, style: GoogleFonts.inter(
                        fontSize: 11, color: C.textMuted)),
                    const Spacer(),
                  ] else const Spacer(),
                  if (job.notificationSent)
                    const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.notifications_active,
                            size: 14, color: C.green)),
                  Text(fmtMoney(job.totalAmount), style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 15, color: C.primary)),
                  const Icon(Icons.chevron_right, size: 18, color: C.textDim),
                ]),
              ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
