import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_utils.dart';

class MonthWiseReportScreen extends StatefulWidget {
  final String? messId;
  final String? messName;

  const MonthWiseReportScreen({
    super.key,
    this.messId,
    this.messName,
  });

  @override
  State<MonthWiseReportScreen> createState() => _MonthWiseReportScreenState();
}

class _MonthWiseReportScreenState extends State<MonthWiseReportScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  Map<String, Map<String, dynamic>> _groupedReport = {};
  String? _resolvedMessId;

  static const String _cacheReportKeyPrefix = 'offline_cache_month_wise_report';

  String _ownerCacheKey(String userId) => '${_cacheReportKeyPrefix}_$userId';

  String _cacheReportKeyFor(String scopeKey) =>
      '${_cacheReportKeyPrefix}_$scopeKey';

  @override
  void initState() {
    super.initState();
    _resolvedMessId =
    (widget.messId != null && widget.messId!.isNotEmpty) ? widget.messId : null;
    _fetchAndGroupData();
  }

  Future<void> _cacheReportLocally(String scopeKey, List rawPayments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheReportKeyFor(scopeKey), jsonEncode(rawPayments));
  }

  Future<List> _loadCachedReportLocally(
      String scopeKey,
      String currentUserId,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cachedStr = prefs.getString(_cacheReportKeyFor(scopeKey)) ??
          prefs.getString(_ownerCacheKey(currentUserId));
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

      String? targetMessId = _resolvedMessId;
      String scopeKey =
      (targetMessId != null && targetMessId.isNotEmpty)
          ? targetMessId
          : currentUserId;

      List rawList = [];

      try {
        if (targetMessId == null || targetMessId.isEmpty) {
          final setupRow = await _supabase
              .from('mess_setup')
              .select('id')
              .eq('owner_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          targetMessId = setupRow?['id']?.toString();
          if (targetMessId != null && targetMessId.isNotEmpty) {
            _resolvedMessId = targetMessId;
            scopeKey = targetMessId;
          }
        }

        if (targetMessId != null && targetMessId.isNotEmpty) {
          // Scope to members belonging to this mess_id
          final messMembersResponse = await _supabase
              .from('mess_members')
              .select('id')
              .eq('owner_id', currentUserId)
              .eq('mess_id', targetMessId);

          final memberIds = (messMembersResponse as List)
              .map((m) => m['id'])
              .where((id) => id != null)
              .toList();

          if (memberIds.isEmpty) {
            rawList = [];
          } else {
            final paymentsResponse = await _supabase
                .from('mess_member_payments')
                .select('*, mess_members(name, occupied_rooms)')
                .eq('owner_id', currentUserId)
                .filter('member_id', 'in', memberIds);

            rawList = List.from(paymentsResponse);
          }
        } else {
          final paymentsResponse = await _supabase
              .from('mess_member_payments')
              .select('*, mess_members(name, occupied_rooms)')
              .eq('owner_id', currentUserId);

          rawList = List.from(paymentsResponse);
        }

        await _cacheReportLocally(scopeKey, rawList);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
            "Network offline. Loading month-wise report from cache... Error: $networkError");
        rawList = await _loadCachedReportLocally(scopeKey, currentUserId);
        if (mounted) setState(() => _isOfflineMode = true);
      }

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
                  'Total: ${data['total_collection'] ?? 0}',
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