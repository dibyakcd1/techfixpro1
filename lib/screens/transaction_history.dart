import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../services/audit_log_service.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final session = ref.read(currentUserProvider).asData?.value;
    if (session != null && session.shopId.isNotEmpty) {
      await ref.read(transactionsProvider.notifier).loadFromSupabase(session.shopId);
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _editTransaction(Map<String, dynamic> tx) async {
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || !session.isOwner) return;

    final qtyController = TextEditingController(text: tx['qty'].toString());
    final priceController = TextEditingController(text: tx['price'].toString());
    final paymentController = TextEditingController(text: tx['payment']);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Transaction',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Product: ${tx['productName']}',
                  style: GoogleFonts.inter(color: C.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: paymentController,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final newQty = int.tryParse(qtyController.text) ?? tx['qty'];
              final newPrice = double.tryParse(priceController.text) ?? tx['price'];
              final newPayment = paymentController.text;
              final newTotal = newQty * newPrice;

              final updatedTx = Map<String, dynamic>.from(tx)
                ..['qty'] = newQty
                ..['price'] = newPrice
                ..['payment'] = newPayment
                ..['total'] = newTotal;

              await ref.read(transactionsProvider.notifier).updateTransactionInSupabase(updatedTx);

              // Log the edit to audit logs
              await AuditLogService.log(
                shopId: tx['shopId'],
                userId: session.uid,
                action: AuditLogService.update,
                entity: 'Transaction',
                entityId: tx['transactionId'],
                details: {
                  'oldQty': tx['qty'],
                  'newQty': newQty,
                  'oldPrice': tx['price'],
                  'newPrice': newPrice,
                  'oldPayment': tx['payment'],
                  'newPayment': newPayment,
                  'oldTotal': tx['total'],
                  'newTotal': newTotal,
                },
              );

              if (mounted) {
                nav.pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final session = ref.read(currentUserProvider).asData?.value;
    if (session == null || !session.isOwner) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Transaction',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete this transaction? This action cannot be undone.',
            style: GoogleFonts.inter()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(transactionsProvider.notifier).deleteTransactionFromSupabase(
        tx['transactionId'],
        tx['shopId'],
        session.uid,
      );
    }
  }

  String _formatDate(int timestampMs) {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestampMs.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final session = userAsync.asData?.value;
    final transactions = ref.watch(transactionsProvider);

    // Only allow owners to view this screen
    if (session == null || !session.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction History')),
        body: Center(
          child: Text('Only the shop owner can view transaction history',
              style: GoogleFonts.inter(color: C.textMuted, fontSize: 16),
              textAlign: TextAlign.center),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction History')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Transaction History',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: transactions.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final tx = transactions[index];
                return _buildTransactionCard(tx, session);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💳', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('No transactions yet',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: C.textMuted)),
            const SizedBox(height: 8),
            Text('Your transaction history will appear here',
                style: GoogleFonts.inter(color: C.textMuted),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, SessionUser session) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(tx['productName'] ?? 'Unknown Product',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: C.text)),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: C.primary, size: 20),
                      onPressed: () => _editTransaction(tx),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: C.red, size: 20),
                      onPressed: () => _deleteTransaction(tx),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Qty: ${tx['qty']}',
                    style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                const SizedBox(width: 16),
                Text('Price: ${fmtMoney(tx['price'])}',
                    style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                const SizedBox(width: 16),
                Text('Total: ${fmtMoney(tx['total'])}',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: C.primary)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Payment: ${tx['payment']}',
                    style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
                const SizedBox(width: 16),
                Text('Date: ${_formatDate(tx['time'])}',
                    style: GoogleFonts.inter(fontSize: 12, color: C.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
