import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_utils.dart';

class MonthWiseReportScreen extends StatefulWidget {
  const MonthWiseReportScreen({super.key});

  @override
  State<MonthWiseReportScreen> createState() => _MonthWiseReportScreenState();
}

class _MonthWiseReportScreenState extends State<MonthWiseReportScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  Map<String, Map<String, dynamic>> _groupedReport = {};

  // Owner-scoped local cache key
  String get _cacheReportKey =>
      'offline_cache_month_wise_report_${_supabase.auth.currentUser?.id ?? 'default'}';

  @override
  void initState() {
    super.initState();
    _fetchAndGroupData();
  }

  Future<void> _cacheReportLocally(List rawPayments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheReportKey, jsonEncode(rawPayments));
  }

  Future<List> _loadCachedReportLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cachedStr = prefs.getString(_cacheReportKey);
      if (cachedStr != null) {
        return jsonDecode(cachedStr) as List;
      }
    } catch (e) {
      debugPrint("Error reading local report cache: $e");
    }
    return [];
  }

  Future<void> _fetchAndGroupData() async {
    setState(() => _isLoading = true);
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List rawList = [];

      try {
        // Attempt online fetch strictly scoped to current owner
        final paymentsResponse = await _supabase
            .from('mess_member_payments')
            .select('*, mess_members(name, occupied_rooms)')
            .eq('owner_id', currentUserId);

        rawList = List.from(paymentsResponse);

        // Save fresh data locally
        await _cacheReportLocally(rawList);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Offline fallback without error snackbars
        debugPrint("Network offline. Loading month-wise report from cache... Error: $networkError");
        rawList = await _loadCachedReportLocally();
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Call utility method cleanly
      final grouped = CollectionUtils.groupCollectionsByMonth(rawList);

      if (mounted) {
        setState(() {
          _groupedReport = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading report: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Month-Wise Report',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _groupedReport.isEmpty
          ? const Center(child: Text('No report data available.'))
          : RefreshIndicator(
        onRefresh: _fetchAndGroupData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _groupedReport.entries.map((entry) {
            final month = entry.key;
            final data = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  month,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Total: ৳${data['total_collection'] ?? 0}',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}