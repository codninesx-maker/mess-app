import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ElectricBillDetailsScreen extends StatefulWidget {
  final String? messId;
  final String? messName;

  const ElectricBillDetailsScreen({
    super.key,
    this.messId,
    this.messName,
  });

  @override
  State<ElectricBillDetailsScreen> createState() =>
      _ElectricBillDetailsScreenState();
}

class _ElectricBillDetailsScreenState extends State<ElectricBillDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _meterController = TextEditingController();
  final _floorController = TextEditingController(text: '1');
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  final _monthController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isOfflineMode = false;
  bool _applyToAllMembers = true;

  String? _resolvedMessId;
  Map<String, List<dynamic>> _groupedBills = {};
  int _activeMemberCount = 0;
  double _totalBilledAmount = 0.0;
  double _currentMonthBilledAmount = 0.0;
  double _latestPerMemberRate = 0.0;

  static const String _cacheBillsKey = 'offline_cache_electricity_bills';
  static const String _prefSyncToggleKey = 'pref_electricity_sync_toggle';

  String _scopeKeyFor(String? messId, String userId) {
    return (messId != null && messId.isNotEmpty) ? messId : userId;
  }

  String _billsCacheKey(String scopeKey) => '${_cacheBillsKey}_$scopeKey';
  String _syncToggleKey(String scopeKey) => '${_prefSyncToggleKey}_$scopeKey';

  @override
  void initState() {
    super.initState();
    _resolvedMessId =
    (widget.messId != null && widget.messId!.isNotEmpty) ? widget.messId : null;
    _dateController.text = _formatDate(_selectedDate);
    _monthController.text = '${_getMonthName(_selectedDate.month)} ${_selectedDate.year}';
    _loadSavedPreferences();
    _fetchElectricityData();
  }

  @override
  void dispose() {
    _meterController.dispose();
    _floorController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _supabase.auth.currentUser?.id;
    final scope = _scopeKeyFor(_resolvedMessId, userId ?? 'default');
    final savedValue =
        prefs.getBool(_syncToggleKey(scope)) ?? prefs.getBool(_prefSyncToggleKey);
    if (mounted) {
      setState(() {
        _applyToAllMembers = savedValue ?? true;
      });
    }
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
        _monthController.text = '${_getMonthName(picked.month)} ${picked.year}';
      });
    }
  }

  Future<void> _fetchElectricityData() async {
    setState(() => _isLoading = true);
    final userId = _supabase.auth.currentUser?.id;
    final userEmail = _supabase.auth.currentUser?.email?.toLowerCase().trim();

    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    String? targetMessId = _resolvedMessId;
    String scopeKey = _scopeKeyFor(targetMessId, userId);

    try {
      if (targetMessId == null || targetMessId.isEmpty) {
        final setupRow = await _supabase
            .from('mess_setup')
            .select('id')
            .eq('owner_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        targetMessId = setupRow?['id']?.toString();
        if (targetMessId != null && targetMessId.isNotEmpty) {
          _resolvedMessId = targetMessId;
          scopeKey = _scopeKeyFor(targetMessId, userId);
        }
      }

      final results = await Future.wait([
        _supabase
            .from('mess_electricity_bills')
            .select('*')
            .eq('owner_id', userId)
            .order('created_at', ascending: false),
        _supabase
            .from('mess_members')
            .select('*')
            .eq('owner_id', userId),
      ]);

      List bills = List.from(results[0] as List);
      List members = List.from(results[1] as List);

      // Scope by mess_id when available, while preserving legacy rows where mess_id is null
      if (targetMessId != null && targetMessId.isNotEmpty) {
        final hasMessScopedBills = bills.any(
              (b) => b['mess_id'] != null && b['mess_id'].toString().isNotEmpty,
        );
        if (hasMessScopedBills) {
          bills = bills.where((b) {
            final bMessId = b['mess_id']?.toString();
            return bMessId == null || bMessId.isEmpty || bMessId == targetMessId;
          }).toList();
        }

        final hasMessScopedMembers = members.any(
              (m) => m['mess_id'] != null && m['mess_id'].toString().isNotEmpty,
        );
        if (hasMessScopedMembers) {
          members = members.where((m) {
            final mMessId = m['mess_id']?.toString();
            return mMessId == null || mMessId.isEmpty || mMessId == targetMessId;
          }).toList();
        }
      }

      if (userEmail != null && userEmail.isNotEmpty) {
        members = members.where((m) {
          final mEmail = (m['email'] ?? '').toString().toLowerCase().trim();
          return mEmail.isEmpty || mEmail != userEmail;
        }).toList();
      }

      final now = DateTime.now();
      final currentMonthName = _getMonthName(now.month).toLowerCase();
      final currentYearStr = now.year.toString();

      double totalAllTime = 0.0;
      double currentMonthTotal = 0.0;
      Map<String, List<dynamic>> grouped = {};

      for (int i = 0; i < bills.length; i++) {
        final b = bills[i];
        final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
        totalAllTime += amount;

        final monthYear =
        (b['month_year'] ?? 'Unknown Month').toString().trim();
        grouped.putIfAbsent(monthYear, () => []).add(b);

        final monthYearLower = monthYear.toLowerCase();
        if (monthYearLower.contains(currentMonthName) &&
            monthYearLower.contains(currentYearStr)) {
          currentMonthTotal += amount;
        }
      }

      final int activeMemberCount = members.length;
      final double calculatedPerMemberRate = activeMemberCount > 0
          ? double.parse((currentMonthTotal / activeMemberCount).toStringAsFixed(2))
          : 0.0;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_billsCacheKey(scopeKey), jsonEncode(bills));

      if (mounted) {
        setState(() {
          _groupedBills = grouped;
          _activeMemberCount = activeMemberCount;
          _totalBilledAmount = totalAllTime;
          _currentMonthBilledAmount = currentMonthTotal;
          _latestPerMemberRate = calculatedPerMemberRate;
          _isOfflineMode = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(
          "Error loading electricity details (falling back to cache): $e");
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(_billsCacheKey(scopeKey)) ??
          prefs.getString(_cacheBillsKey);
      final cachedBills =
      cachedStr != null ? jsonDecode(cachedStr) as List : [];

      double totalAllTime = 0.0;
      double currentMonthTotal = 0.0;
      final now = DateTime.now();
      final currentMonthName = _getMonthName(now.month).toLowerCase();
      final currentYearStr = now.year.toString();
      Map<String, List<dynamic>> grouped = {};

      for (var b in cachedBills) {
        final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
        totalAllTime += amount;
        final monthYear =
        (b['month_year'] ?? 'Unknown Month').toString().trim();
        grouped.putIfAbsent(monthYear, () => []).add(b);

        final monthYearLower = monthYear.toLowerCase();
        if (monthYearLower.contains(currentMonthName) &&
            monthYearLower.contains(currentYearStr)) {
          currentMonthTotal += amount;
        }
      }

      final int effectiveMemberCount =
      _activeMemberCount > 0 ? _activeMemberCount : 0;
      final double calculatedPerMemberRate = effectiveMemberCount > 0
          ? double.parse(
          (currentMonthTotal / effectiveMemberCount).toStringAsFixed(2))
          : 0.0;

      if (mounted) {
        setState(() {
          _groupedBills = grouped;
          _totalBilledAmount = totalAllTime;
          _currentMonthBilledAmount = currentMonthTotal;
          _latestPerMemberRate = calculatedPerMemberRate;
          _isOfflineMode = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveElectricityBill() async {
    if (!_formKey.currentState!.validate()) return;

    final meterNumber = _meterController.text.trim();
    final floorNumber = int.tryParse(_floorController.text.trim()) ?? 1;
    final totalAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final billDate = _dateController.text.trim();
    final monthYear = _monthController.text.trim();

    final double tempPerMemberShare = _activeMemberCount > 0
        ? double.parse((totalAmount / _activeMemberCount).toStringAsFixed(2))
        : totalAmount;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Electricity Bill'),
        content: Text(
          'Are you sure you want to save this bill record?\n\n'
              '• Meter/Account: $meterNumber (Floor $floorNumber)\n'
              '• Month: $monthYear\n'
              '• Date: $billDate\n'
              '• Total Amount: ৳${_formatCurrency(totalAmount)}\n'
              '• Per Member Share: ৳${_formatCurrency(tempPerMemberShare)} (across $_activeMemberCount members)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'User not authenticated';

      String? targetMessId = _resolvedMessId;
      if (targetMessId == null || targetMessId.isEmpty) {
        final setupRow = await _supabase
            .from('mess_setup')
            .select('id')
            .eq('owner_id', userId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        targetMessId = setupRow?['id']?.toString();
        _resolvedMessId = targetMessId;
      }

      final double singleRowPerMemberShare = _activeMemberCount > 0
          ? double.parse((totalAmount / _activeMemberCount).toStringAsFixed(2))
          : totalAmount;

      await _supabase.from('mess_electricity_bills').insert({
        if (targetMessId != null && targetMessId.isNotEmpty)
          'mess_id': targetMessId,
        'owner_id': userId,
        'meter_number': meterNumber,
        'floor': floorNumber,
        'amount': totalAmount,
        'per_member_amount': singleRowPerMemberShare,
        'bill_date': billDate,
        'month_year': monthYear,
      });

      _amountController.clear();
      await _fetchElectricityData();

      if (_applyToAllMembers) {
        var setupUpdate = _supabase
            .from('mess_setup')
            .update({'monthly_electricity_bill': _latestPerMemberRate});
        if (targetMessId != null && targetMessId.isNotEmpty) {
          setupUpdate = setupUpdate.eq('id', targetMessId);
        } else {
          setupUpdate = setupUpdate.eq('owner_id', userId);
        }
        await setupUpdate;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _applyToAllMembers
                  ? 'Bill saved! Collective monthly per-member due set to $_latestPerMemberRate'
                  : 'Electricity bill record saved!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error saving electricity bill: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save bill: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleSyncToSetup(bool value) async {
    setState(() => _applyToAllMembers = value);

    final userId = _supabase.auth.currentUser?.id;
    final scope = _scopeKeyFor(_resolvedMessId, userId ?? 'default');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncToggleKey(scope), value);

    if (userId == null) return;

    try {
      final double rateToSync = value ? _latestPerMemberRate : 0.0;
      var setupUpdate = _supabase
          .from('mess_setup')
          .update({'monthly_electricity_bill': rateToSync});
      if (_resolvedMessId != null && _resolvedMessId!.isNotEmpty) {
        setupUpdate = setupUpdate.eq('id', _resolvedMessId!);
      } else {
        setupUpdate = setupUpdate.eq('owner_id', userId);
      }
      await setupUpdate;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Synced aggregate monthly per-member rate ($_latestPerMemberRate) to monthly dues.'
                  : 'Cleared shared monthly electricity due share.',
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error syncing toggle state: $e");
    }
  }

  String _formatCurrency(double val) {
    return val == val.toInt() ? '${val.toInt()}' : '${val.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Electric Bill Details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ),
            ],
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
        onRefresh: _fetchElectricityData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildBalanceSummaryCard(),
            const SizedBox(height: 20),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.electric_bolt, color: Colors.amber),
                          SizedBox(width: 8),
                          Text(
                            'Add Monthly Meter Bill',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _meterController,
                              decoration: const InputDecoration(
                                labelText: 'Meter / Account No',
                                hintText: 'e.g. 41029384',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.numbers, size: 18),
                              ),
                              validator: (val) =>
                              val == null || val.trim().isEmpty ? 'Enter meter no' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _floorController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Floor',
                                hintText: '1',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.layers, size: 18),
                              ),
                              validator: (val) =>
                              val == null || val.trim().isEmpty ? 'Floor' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Total Bill Amount',
                          hintText: 'e.g. 1000',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_money),
                          helperText: _activeMemberCount > 0
                              ? 'Divided equally across $_activeMemberCount active members'
                              : null,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter bill amount';
                          if ((double.tryParse(val.trim()) ?? 0) <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              readOnly: true,
                              onTap: () => _selectDate(context),
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _monthController,
                              decoration: const InputDecoration(
                                labelText: 'Month',
                                hintText: 'November 2026',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.date_range, size: 18),
                              ),
                              validator: (val) =>
                              val == null || val.trim().isEmpty ? 'Enter month' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Update all members\' monthly due share',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        subtitle: const Text(
                          'Syncs per-member share instantly to Current Total Dues',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _applyToAllMembers,
                        onChanged: _toggleSyncToSetup,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveElectricityBill,
                          icon: _isSaving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                          )
                              : const Icon(Icons.save),
                          label: const Text(
                            'Save Bill Record',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Bill History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (_groupedBills.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    'No electricity bill records yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._groupedBills.entries.map((entry) {
                final monthYear = entry.key;
                final billsList = entry.value;

                double monthTotalAmount = 0.0;
                for (var b in billsList) {
                  monthTotalAmount += (b['amount'] as num?)?.toDouble() ?? 0.0;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.amber.withOpacity(0.15),
                      child: const Icon(Icons.bolt, color: Colors.amber),
                    ),
                    title: Text(
                      monthYear,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Total Bills: ${billsList.length} record(s)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      _formatCurrency(monthTotalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                    children: billsList.map((bill) {
                      final amount = (bill['amount'] as num?)?.toDouble() ?? 0.0;
                      final perMember = (bill['per_member_amount'] as num?)?.toDouble() ?? 0.0;
                      final floorNo = bill['floor'] ?? 1;
                      final meterNo = bill['meter_number'] ?? 'N/A';
                      final billDate = bill['bill_date'] ?? 'N/A';

                      return ListTile(
                        dense: true,
                        title: Text(
                          'Meter: $meterNo (Floor $floorNo)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        subtitle: Text(
                          'Date: $billDate  |  Per Member: ${_formatCurrency(perMember)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          _formatCurrency(amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }),
            const SizedBox(height: 60),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: MessTestBanner(),
        ),
      ),
    );
  }

  Widget _buildBalanceSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.electric_bolt, color: Colors.amber, size: 20),
              const SizedBox(width: 6),
              Text(
                'Total Paid for Electricity Consumption',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatCurrency(_totalBilledAmount),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _summaryItem(
                'This Month Paid',
                _formatCurrency(_currentMonthBilledAmount),
                Colors.blue,
              ),
              _summaryItem(
                'Per Member ($_activeMemberCount)',
                _formatCurrency(_latestPerMemberRate),
                Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}