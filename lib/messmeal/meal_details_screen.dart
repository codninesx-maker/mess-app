import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MealDetailsScreen extends StatefulWidget {
  const MealDetailsScreen({super.key});

  @override
  State<MealDetailsScreen> createState() => _MealDetailsScreenState();
}

class _MealDetailsScreenState extends State<MealDetailsScreen> {
  final _supabase = Supabase.instance.client;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  late String _selectedMonth;
  late int _selectedYear;
  double _mealRate = 60.0;

  List _dailyMeals = [];
  bool _isLoading = true;
  bool _isOffline = false;
  String? _resolvedMemberId;

  // Payment & Balance tracking variables
  double _totalPaid = 0.0;
  String _paymentMethod = 'Cash'; // Default payment channel

  String? get _currentAuthId => _supabase.auth.currentUser?.id;
  String get _monthYearKey => '$_selectedMonth $_selectedYear';
  String get _cacheKey => 'cached_my_meals_${_currentAuthId}_$_monthYearKey';
  String get _rateCacheKey => 'cached_my_meal_rate_${_currentAuthId}_$_monthYearKey';
  String get _paymentCacheKey => 'cached_my_meal_payment_${_currentAuthId}_$_monthYearKey';

  String get _prefFixedToggleKey => 'pref_is_fixed_day_rate_$_currentAuthId';
  String get _prefFixedCostKey => 'pref_fixed_day_cost_$_currentAuthId';
  String get _prefBreakfastKey => 'pref_breakfast_$_currentAuthId';
  String get _prefLunchKey => 'pref_lunch_$_currentAuthId';
  String get _prefDinnerKey => 'pref_dinner_$_currentAuthId';



  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = _months[now.month - 1];
    _selectedYear = now.year;
    _initializeAndLoad();
  }

  Future<String?> _getOrCreateMemberId() async {
    if (_resolvedMemberId != null) return _resolvedMemberId;

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final email = user.email?.toLowerCase().trim();

    try {
      var query = _supabase.from('mess_members').select('id');
      if (email != null && email.isNotEmpty) {
        query = query.eq('email', email);
      } else {
        query = query.eq('owner_id', user.id);
      }

      final existing = await query.limit(1).maybeSingle();
      if (existing != null && existing['id'] != null) {
        _resolvedMemberId = existing['id'].toString();
        return _resolvedMemberId;
      }

      final defaultName = (email != null && email.contains('@'))
          ? email.split('@').first
          : 'Member';

      final inserted = await _supabase
          .from('mess_members')
          .insert({
        'name': defaultName,
        'email': email,
        'owner_id': user.id,
      })
          .select('id')
          .single();

      _resolvedMemberId = inserted['id'].toString();
      return _resolvedMemberId;
    } catch (e) {
      debugPrint('Error resolving member ID: $e');
      return null;
    }
  }

  Future<void> _initializeAndLoad() async {
    await _getOrCreateMemberId();
    await _loadMealData();
  }

  Future<void> _loadMealData() async {
    final memberId = await _getOrCreateMemberId();
    if (memberId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final savedRate = prefs.getDouble(_rateCacheKey);
    if (savedRate != null && savedRate > 0) {
      _mealRate = savedRate;
    }

    final savedPaid = prefs.getDouble(_paymentCacheKey);
    if (savedPaid != null) {
      _totalPaid = savedPaid;
    }

    try {
      final response = await _supabase
          .from('mess_daily_meals')
          .select('*')
          .eq('member_id', memberId)
          .eq('month_year', _monthYearKey)
          .order('meal_date', ascending: false);

      final fetched = List.from(response);

      if (fetched.isNotEmpty && (fetched.first['meal_rate'] ?? 0) > 0) {
        _mealRate = (fetched.first['meal_rate'] as num).toDouble();
        await prefs.setDouble(_rateCacheKey, _mealRate);
      }

      await prefs.setString(_cacheKey, jsonEncode(fetched));

      if (mounted) {
        setState(() {
          _dailyMeals = fetched;
          _isOffline = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching meal details: $e');
      await _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString(_cacheKey);

    if (cachedStr != null) {
      final decoded = jsonDecode(cachedStr) as List;
      if (mounted) {
        setState(() {
          _dailyMeals = List.from(decoded);
          _isOffline = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _dailyMeals = [];
          _isOffline = true;
          _isLoading = false;
        });
      }
    }
  }

  double get _totalMeals {
    return _dailyMeals.fold(0.0, (sum, row) {
      final b = (row['breakfast'] as num?)?.toDouble() ?? 0.0;
      final l = (row['lunch'] as num?)?.toDouble() ?? 0.0;
      final d = (row['dinner'] as num?)?.toDouble() ?? 0.0;
      return sum + b + l + d;
    });
  }

  double get _totalMonthlyExpense {
    return _dailyMeals.fold(0.0, (sum, row) {
      final isFixedDayRate = row['is_fixed_day_rate'] == true;
      if (isFixedDayRate) {
        final fixedCost = (row['fixed_day_cost'] as num?)?.toDouble() ?? 0.0;
        return sum + fixedCost;
      } else {
        final b = (row['breakfast'] as num?)?.toDouble() ?? 0.0;
        final l = (row['lunch'] as num?)?.toDouble() ?? 0.0;
        final d = (row['dinner'] as num?)?.toDouble() ?? 0.0;
        final rate = (row['meal_rate'] as num?)?.toDouble() ?? _mealRate;
        return sum + ((b + l + d) * rate);
      }
    });
  }

  double get _averagePerDayExpense {
    if (_dailyMeals.isEmpty) return 0.0;
    return _totalMonthlyExpense / _dailyMeals.length;
  }

  double get _balanceDue {
    return (_totalMonthlyExpense - _totalPaid).clamp(0.0, double.infinity);
  }

  void _showPaymentDialog() {
    final amountController = TextEditingController();
    String selectedMethod = _paymentMethod;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Add Payment ($_monthYearKey)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Total Paid: ${_totalPaid.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'New Payment Amount ()',
                  hintText: 'e.g. 500',
                  prefixIcon: Icon(Icons.add_card),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selectedMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  prefixIcon: Icon(Icons.payment),
                  border: OutlineInputBorder(),
                ),
                items: ['Cash', 'bKash', 'Nagad', 'Bank Transfer', 'Other']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedMethod = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final addedAmount = double.tryParse(amountController.text.trim()) ?? 0.0;
                if (addedAmount <= 0) return;

                setState(() {
                  _totalPaid += addedAmount; // Accumulate with previous total
                  _paymentMethod = selectedMethod;
                });

                final prefs = await SharedPreferences.getInstance();
                await prefs.setDouble(_paymentCacheKey, _totalPaid);

                if (context.mounted) Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added $addedAmount via $_paymentMethod successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Add Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEditDailyMealDialog({Map<String, dynamic>? existingRecord}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    DateTime selectedDate = existingRecord != null
        ? DateTime.parse(existingRecord['meal_date'])
        : DateTime.now();

    // If editing an existing record, load its values; otherwise load your saved setup defaults
    double breakfast = existingRecord != null
        ? ((existingRecord['breakfast'] as num?)?.toDouble() ?? 0.5)
        : (prefs.getDouble(_prefBreakfastKey) ?? 0.5);

    double lunch = existingRecord != null
        ? ((existingRecord['lunch'] as num?)?.toDouble() ?? 1.0)
        : (prefs.getDouble(_prefLunchKey) ?? 1.0);

    double dinner = existingRecord != null
        ? ((existingRecord['dinner'] as num?)?.toDouble() ?? 1.0)
        : (prefs.getDouble(_prefDinnerKey) ?? 1.0);

    bool isFixedDayRate = existingRecord != null
        ? (existingRecord['is_fixed_day_rate'] == true ||
        existingRecord['is_fixed_day_rate'] == 1 ||
        existingRecord['is_fixed_day_rate'].toString().toLowerCase() == 'true')
        : (prefs.getBool(_prefFixedToggleKey) ?? false);

    final initialRate = (existingRecord?['meal_rate'] as num?)?.toDouble() ?? _mealRate;
    final rateController = TextEditingController(
      text: initialRate == initialRate.toInt()
          ? initialRate.toInt().toString()
          : initialRate.toString(),
    );

    final initialFixedCost = existingRecord != null
        ? ((existingRecord['fixed_day_cost'] as num?)?.toDouble() ?? 120.0)
        : (prefs.getDouble(_prefFixedCostKey) ?? 120.0);

    final fixedCostController = TextEditingController(
      text: initialFixedCost == initialFixedCost.toInt()
          ? initialFixedCost.toInt().toString()
          : initialFixedCost.toString(),
    );

    final List<double> mealOptions = [0.0, 0.5, 1.0, 1.5, 2.0, 3.0];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double dayTotalMeals = breakfast + lunch + dinner;
          double dayTotalCost = 0.0;

          if (isFixedDayRate) {
            dayTotalCost = double.tryParse(fixedCostController.text.trim()) ?? 0.0;
          } else {
            final currentRate = double.tryParse(rateController.text.trim()) ?? _mealRate;
            dayTotalCost = dayTotalMeals * currentRate;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(existingRecord == null ? 'Log My Daily Meals' : 'Edit My Daily Meals'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, color: Colors.blue),
                    title: Text(
                      'Date: ${selectedDate.toIso8601String().split('T')[0]}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Text('Change', style: TextStyle(color: Colors.blue)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use Fixed Per-Day Rate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isFixedDayRate ? 'Charging flat rate for this day' : 'Charging per meal count',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    value: isFixedDayRate,
                    onChanged: (val) {
                      setDialogState(() {
                        isFixedDayRate = val;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<double>(
                    value: mealOptions.contains(breakfast) ? breakfast : 1.0,
                    decoration: const InputDecoration(
                      labelText: 'Breakfast Meal Count',
                      prefixIcon: Icon(Icons.free_breakfast_outlined),
                    ),
                    items: mealOptions.map((v) => DropdownMenuItem(value: v, child: Text('$v meal'))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => breakfast = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<double>(
                    value: mealOptions.contains(lunch) ? lunch : 1.0,
                    decoration: const InputDecoration(
                      labelText: 'Lunch Meal Count',
                      prefixIcon: Icon(Icons.lunch_dining_outlined),
                    ),
                    items: mealOptions.map((v) => DropdownMenuItem(value: v, child: Text('$v meal'))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => lunch = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<double>(
                    value: mealOptions.contains(dinner) ? dinner : 1.0,
                    decoration: const InputDecoration(
                      labelText: 'Dinner Meal Count',
                      prefixIcon: Icon(Icons.dinner_dining_outlined),
                    ),
                    items: mealOptions.map((v) => DropdownMenuItem(value: v, child: Text('$v meal'))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => dinner = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  if (isFixedDayRate)
                    TextField(
                      controller: fixedCostController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fixed Daily Total Cost ()',
                        prefixIcon: Icon(Icons.money),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    )
                  else
                    TextField(
                      controller: rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Per-Meal Rate',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total: $dayTotalMeals meals',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('${dayTotalCost.toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                                fontSize: 16)),
                      ],
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
                  final memberId = await _getOrCreateMemberId();
                  if (memberId == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Error: Member record not found.')),
                      );
                    }
                    return;
                  }

                  final dateStr = selectedDate.toIso8601String().split('T')[0];
                  final recordMonthYear = '${_months[selectedDate.month - 1]} ${selectedDate.year}';

                  final finalRate = double.tryParse(rateController.text.trim()) ?? _mealRate;
                  final finalFixedCost = double.tryParse(fixedCostController.text.trim()) ?? 0.0;

                  setState(() => _mealRate = finalRate);

                  // Save your setup preferences for all future new entries
                  await prefs.setDouble(_rateCacheKey, finalRate);
                  await prefs.setBool(_prefFixedToggleKey, isFixedDayRate);
                  await prefs.setDouble(_prefFixedCostKey, finalFixedCost);
                  await prefs.setDouble(_prefBreakfastKey, breakfast);
                  await prefs.setDouble(_prefLunchKey, lunch);
                  await prefs.setDouble(_prefDinnerKey, dinner);

                  final payload = {
                    'member_id': memberId,
                    'meal_date': dateStr,
                    'month_year': recordMonthYear,
                    'breakfast': breakfast,
                    'lunch': lunch,
                    'dinner': dinner,
                    'meal_rate': finalRate,
                    'is_fixed_day_rate': isFixedDayRate,
                    'fixed_day_cost': finalFixedCost,
                  };

                  try {
                    await _supabase.from('mess_daily_meals').upsert(
                      payload,
                      onConflict: 'member_id,meal_date',
                    );
                    await _loadMealData();
                  } catch (e) {
                    debugPrint('DB Upsert Error: $e');
                    setState(() {
                      _dailyMeals.removeWhere((m) => m['meal_date'] == dateStr);
                      _dailyMeals.insert(0, payload);
                      _isOffline = true;
                    });
                    await prefs.setString(_cacheKey, jsonEncode(_dailyMeals));
                  }

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save Meals'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group daily meals month-wise for collapsible cards
    Map<String, List<dynamic>> groupedMeals = {};
    for (var row in _dailyMeals) {
      final my = row['month_year'] ?? _monthYearKey;
      if (!groupedMeals.containsKey(my)) {
        groupedMeals[my] = [];
      }
      groupedMeals[my]!.add(row);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Meal Details'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDailyMealDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Today Meals'),
      ),
      body: Column(
        children: [
          if (_isOffline)
          // Auto-Picked Current Month & Year Header Banner
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Showing Meals For:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _monthYearKey,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonth = val);
                        _loadMealData();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    // Dynamically generates 5 years back and 5 years forward from the current year (11 options total)
                    items: List.generate(7, (index) => (DateTime.now().year - 3) + index)
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYear = val);
                        _loadMealData();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatItem('Total Meals', _totalMeals.toStringAsFixed(1), Colors.blue),
                      _buildStatItem('Meal Rate', '${_mealRate.toStringAsFixed(0)}', Colors.teal),
                      _buildStatItem('Avg / Day', '${_averagePerDayExpense.toStringAsFixed(1)}', Colors.orange),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Expense:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                      Text('${_totalMonthlyExpense.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _showPaymentDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Total Paid ($_paymentMethod):',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.add_circle_outline, size: 16, color: Colors.green),
                            ],
                          ),
                          Text(
                            '${_totalPaid.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Remaining Balance Due:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.redAccent)),
                      Text('${_balanceDue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator(
              onRefresh: _loadMealData,
              child: groupedMeals.isEmpty
                  ? ListView(
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.no_meals_outlined, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No meals logged for $_monthYearKey',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              )
                  : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                children: groupedMeals.entries.map((entry) {
                  final monthYearKey = entry.key;
                  final monthMeals = entry.value;

                  double monthTotalCost = 0.0;
                  for (var r in monthMeals) {
                    final isFixed = r['is_fixed_day_rate'] == true;
                    if (isFixed) {
                      monthTotalCost += (r['fixed_day_cost'] as num?)?.toDouble() ?? 0.0;
                    } else {
                      final b = (r['breakfast'] as num?)?.toDouble() ?? 0.0;
                      final l = (r['lunch'] as num?)?.toDouble() ?? 0.0;
                      final d = (r['dinner'] as num?)?.toDouble() ?? 0.0;
                      final rate = (r['meal_rate'] as num?)?.toDouble() ?? _mealRate;
                      monthTotalCost += ((b + l + d) * rate);
                    }
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ExpansionTile(
                      leading: const Icon(Icons.date_range, color: Colors.blue),
                      title: Text(
                        monthYearKey,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text('${monthMeals.length} days logged', style: const TextStyle(fontSize: 11)),
                      trailing: Text(
                        '৳${monthTotalCost.toStringAsFixed(1)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
                      ),
                      children: monthMeals.map((row) {
                        final date = row['meal_date'] ?? '';
                        final b = (row['breakfast'] as num?)?.toDouble() ?? 0.0;
                        final l = (row['lunch'] as num?)?.toDouble() ?? 0.0;
                        final d = (row['dinner'] as num?)?.toDouble() ?? 0.0;

                        final isFixed = row['is_fixed_day_rate'] == true;
                        final rate = (row['meal_rate'] as num?)?.toDouble() ?? _mealRate;

                        final dayMeals = b + l + d;
                        final dayExpense = isFixed
                            ? ((row['fixed_day_cost'] as num?)?.toDouble() ?? 0.0)
                            : (dayMeals * rate);

                        return ListTile(
                          onTap: () => _showAddEditDailyMealDialog(existingRecord: row),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(date, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  if (isFixed) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('Fixed', style: TextStyle(fontSize: 8, color: Colors.orange, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              Text('${dayExpense.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('B: $b | L: $l | D: $d  (Total: $dayMeals)', style: const TextStyle(fontSize: 11)),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: MessTestBanner(),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}