import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberLedgerScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final double initialAdvancePaid;

  const MemberLedgerScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    this.initialAdvancePaid = 0,
  });

  @override
  State<MemberLedgerScreen> createState() => _MemberLedgerScreenState();
}

class _MemberLedgerScreenState extends State<MemberLedgerScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  List _payments = [];
  double _advancePaid = 0;

  // Local Cache & Queue Keys scoped per member
  String get _cacheAdvanceKey => 'offline_cache_ledger_advance_${widget.memberId}';
  String get _cachePaymentsKey => 'offline_cache_ledger_payments_${widget.memberId}';
  String get _syncQueueKey => 'offline_sync_queue_payments_${widget.memberId}';

  @override
  void initState() {
    super.initState();
    _fetchLedgerData();
  }

  Future<void> _cacheDataLocally(double advance, List payments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cacheAdvanceKey, advance);
    await prefs.setString(_cachePaymentsKey, jsonEncode(payments));
  }

  Future _loadCachedDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final advance = prefs.getDouble(_cacheAdvanceKey) ?? widget.initialAdvancePaid;
      final paymentsStr = prefs.getString(_cachePaymentsKey);
      return {
        'advance': advance,
        'payments': paymentsStr != null ? jsonDecode(paymentsStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local ledger cache: $e");
      return {'advance': widget.initialAdvancePaid, 'payments': []};
    }
  }

  /// Pushes any offline-queued payments to Supabase when network is restored
  Future<void> _syncPendingPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString(_syncQueueKey);
    if (queueStr == null) return;

    try {
      List pendingQueue = jsonDecode(queueStr) as List;
      if (pendingQueue.isEmpty) return;

      List remainingQueue = [];

      for (var payment in pendingQueue) {
        try {
          // Remove temporary local ID before pushing to Supabase
          final serverPayload = Map<String, dynamic>.from(payment);
          serverPayload.remove('id');
          if (serverPayload['id'].toString().startsWith('local_')) {
            serverPayload.remove('id');
          }

          await _supabase.from('mess_member_payments').insert(serverPayload);
        } catch (e) {
          // If still failing, keep in queue
          remainingQueue.add(payment);
          debugPrint("Failed to sync individual payment: $e");
        }
      }

      // Update sync queue with any failed items
      if (remainingQueue.isEmpty) {
        await prefs.remove(_syncQueueKey);
      } else {
        await prefs.setString(_syncQueueKey, jsonEncode(remainingQueue));
      }
    } catch (e) {
      debugPrint("Error processing sync queue: $e");
    }
  }

  Future<void> _fetchLedgerData() async {
    setState(() => _isLoading = true);
    try {
      double fetchedAdvance = 0;
      List fetchedPayments = [];

      try {
        // 0. Try to sync any offline-created payments first if online
        await _syncPendingPayments();

        // 1. Get Advance Deposit
        if (widget.initialAdvancePaid > 0) {
          fetchedAdvance = widget.initialAdvancePaid;
        } else {
          final activeResponse = await _supabase
              .from('mess_members')
              .select('advance_paid')
              .eq('id', widget.memberId)
              .maybeSingle();

          if (activeResponse != null && activeResponse['advance_paid'] != null) {
            fetchedAdvance = (activeResponse['advance_paid'] as num).toDouble();
          } else {
            final archiveResponse = await _supabase
                .from('mess_archive')
                .select('advance_paid')
                .eq('id', widget.memberId)
                .maybeSingle();

            if (archiveResponse != null && archiveResponse['advance_paid'] != null) {
              fetchedAdvance = (archiveResponse['advance_paid'] as num).toDouble();
            }
          }
        }

        // 2. Fetch monthly payments online
        final paymentsResponse = await _supabase
            .from('mess_member_payments')
            .select('*')
            .eq('member_id', widget.memberId)
            .order('created_at', ascending: false);

        fetchedPayments = List.from(paymentsResponse);

        // Cache fresh data locally
        await _cacheDataLocally(fetchedAdvance, fetchedPayments);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Fallback to local cache quietly if offline
        debugPrint("🌐 Network offline. Loading ledger data from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally();
        fetchedAdvance = cached['advance'] as double;
        fetchedPayments = cached['payments'] as List;
        if (mounted) setState(() => _isOfflineMode = true);
      }

      if (mounted) {
        setState(() {
          _advancePaid = fetchedAdvance;
          _payments = fetchedPayments;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching ledger data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Groups payments by their month_year attribute
  Map<String, List<dynamic>> _groupPaymentsByMonth() {
    final Map<String, List<dynamic>> grouped = {};
    for (var payment in _payments) {
      final month = payment['month_year'] ?? 'General Payments';
      grouped.putIfAbsent(month, () => []).add(payment);
    }
    return grouped;
  }

  // Dialog to collect Rent + Electricity for a new month
  void _showAddMonthlyPaymentDialog() {
    String selectedMonth = 'December'; // Default selected month
    final rentController = TextEditingController();
    final electricityController = TextEditingController();
    final remarksController = TextEditingController();

    final List<String> months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Payment for ${widget.memberName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedMonth,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: months.map((String month) {
                    return DropdownMenuItem<String>(
                      value: month,
                      child: Text(month),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setDialogState(() {
                        selectedMonth = newValue;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rentController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Monthly Rent'),
                ),
                TextField(
                  controller: electricityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Electricity Bill'),
                ),
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks'),
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
                final rent = double.tryParse(rentController.text) ?? 0;
                final elec = double.tryParse(electricityController.text) ?? 0;
                final total = rent + elec;

                // --- CONFIRMATION DIALOG BEFORE SAVE ---
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Text('Confirm Payment'),
                    content: Text(
                      'Are you sure you want to save this payment?\n\n'
                          '• Month: $selectedMonth\n'
                          '• Rent: ${rent.round()}\n'
                          '• Electricity: ${elec.round()}\n'
                          '• Total: ${total.round()}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirm & Save'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return; // Stop if user cancels confirmation

                // Proceed with saving logic
                try {
                  final currentDate = DateTime.now().toIso8601String().split('T')[0];

                  final paymentPayload = {
                    'member_id': widget.memberId,
                    'month_year': selectedMonth,
                    'rent_amount': rent,
                    'electricity_bill': elec,
                    'total_paid': total,
                    'status': 'Paid',
                    'payment_date': currentDate,
                    'remarks': remarksController.text.trim(),
                  };

                  bool savedOnline = false;
                  try {
                    await _supabase.from('mess_member_payments').insert(paymentPayload);
                    savedOnline = true;
                  } catch (networkError) {
                    debugPrint("🌐 Network offline during payment insert. Queuing locally... Error: $networkError");

                    final prefs = await SharedPreferences.getInstance();
                    final queueStr = prefs.getString(_syncQueueKey);
                    List queue = queueStr != null ? jsonDecode(queueStr) as List : [];
                    queue.add(paymentPayload);
                    await prefs.setString(_syncQueueKey, jsonEncode(queue));
                  }

                  final localRecord = {
                    'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
                    ...paymentPayload,
                  };
                  setState(() {
                    _payments.insert(0, localRecord);
                  });
                  await _cacheDataLocally(_advancePaid, _payments);

                  if (mounted) {
                    Navigator.pop(context); // Close the main payment dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(savedOnline
                            ? 'Monthly payment added successfully!'
                            : 'Offline mode: Payment saved locally and will sync when online!'),
                        backgroundColor: savedOnline ? Colors.green : Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint("Error saving payment: $e");
                  if (mounted) {
                    String errorMessage = 'Failed to save payment: $e';
                    if (e.toString().contains('23505') || e.toString().contains('unique_member_month_year')) {
                      errorMessage = 'A payment record for this month already exists for this member!';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('${widget.memberName} Ledger'),
            if (_isOfflineMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMonthlyPaymentDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
        onRefresh: _fetchLedgerData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isOfflineMode) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'Viewing offline cached ledger data',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ],
            // Advance Deposit Summary Card
            Card(
              elevation: 2,
              color: Colors.amber.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Advance Security Deposit',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Paid at entry • Adjustment against exit month payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '৳$_advancePaid',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Monthly Payment History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _payments.isEmpty
                ? Padding(
              padding: const EdgeInsets.only(top: 60.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text(
                      'No monthly payments recorded yet.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap the + button below to add the first payment.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _groupPaymentsByMonth().keys.length,
              itemBuilder: (context, index) {
                final groupedMap = _groupPaymentsByMonth();
                final monthKey = groupedMap.keys.elementAt(index);
                final monthPayments = groupedMap[monthKey]!;

                // Calculate month's total paid amount
                double monthTotal = monthPayments.fold(
                  0.0,
                      (sum, item) => sum + ((item['total_paid'] ?? 0) as num).toDouble(),
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 1,
                  child: ExpansionTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.calendar_month, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      monthKey,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Total Records: ${monthPayments.length}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Text(
                      '${monthTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 16,
                      ),
                    ),
                    children: monthPayments.map((p) {
                      final paymentDate = p['payment_date'] ?? '';
                      final remarks = p['remarks'] ?? '';

                      return Container(
                        padding: const EdgeInsets.all(12.0),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Status: ${p['status'] ?? 'Paid'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                    fontSize: 12,
                                  ),
                                ),
                                if (paymentDate.isNotEmpty)
                                  Text(
                                    'Date: $paymentDate',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Rent: ${p['rent_amount']}'),
                                Text('Electricity: ${p['electricity_bill']}'),
                                Text(
                                  'Paid: ${p['total_paid']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                            if (remarks.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Remarks: $remarks',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700], fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}