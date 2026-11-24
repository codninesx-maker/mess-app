import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MonthCollectionScreen extends StatefulWidget {
  final String? messId;
  final String? messName;

  const MonthCollectionScreen({
    super.key,
    this.messId,
    this.messName,
  });

  @override
  State<MonthCollectionScreen> createState() => _MonthCollectionScreenState();
}

class _MonthCollectionScreenState extends State<MonthCollectionScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  Map<String, Map<String, dynamic>> _groupedCollections = {};
  String? _resolvedMessId;

  // Local Cache Keys
  static const String _cachePaymentsKey = 'offline_cache_month_collection_payments';
  static const String _cacheActiveMembersKey = 'offline_cache_month_collection_active_members';
  static const String _cacheArchivedMembersKey = 'offline_cache_month_collection_archived_members';

  String _scopeKeyFor(String? messId, String userId) {
    return (messId != null && messId.isNotEmpty) ? messId : userId;
  }

  String _paymentsCacheKey(String scopeKey) => '${_cachePaymentsKey}_$scopeKey';
  String _activeCacheKey(String scopeKey) =>
      '${_cacheActiveMembersKey}_$scopeKey';
  String _archivedCacheKey(String scopeKey) =>
      '${_cacheArchivedMembersKey}_$scopeKey';

  @override
  void initState() {
    super.initState();
    _resolvedMessId =
    (widget.messId != null && widget.messId!.isNotEmpty) ? widget.messId : null;
    _loadData();
  }

  Future<void> _cacheDataLocally(
      String scopeKey,
      List payments,
      List activeMembers,
      List archivedMembers,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paymentsCacheKey(scopeKey), jsonEncode(payments));
    await prefs.setString(_activeCacheKey(scopeKey), jsonEncode(activeMembers));
    await prefs.setString(
        _archivedCacheKey(scopeKey), jsonEncode(archivedMembers));
  }

  Future _loadCachedDataLocally(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final paymentsStr = prefs.getString(_paymentsCacheKey(scopeKey)) ??
          prefs.getString(_cachePaymentsKey);
      final activeStr = prefs.getString(_activeCacheKey(scopeKey)) ??
          prefs.getString(_cacheActiveMembersKey);
      final archivedStr = prefs.getString(_archivedCacheKey(scopeKey)) ??
          prefs.getString(_cacheArchivedMembersKey);
      return {
        'payments': paymentsStr != null ? jsonDecode(paymentsStr) as List : [],
        'activeMembers':
        activeStr != null ? jsonDecode(activeStr) as List : [],
        'archivedMembers':
        archivedStr != null ? jsonDecode(archivedStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local month collections cache: $e");
      return {'payments': [], 'activeMembers': [], 'archivedMembers': []};
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final rawPayments = await _fetchMonthWiseCollections();
      final grouped = _groupCollectionsByMonth(rawPayments);
      if (mounted) {
        setState(() {
          _groupedCollections = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading collection data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List> _fetchMonthWiseCollections() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      String? targetMessId = _resolvedMessId;
      String scopeKey = _scopeKeyFor(targetMessId, currentUserId);

      List paymentsList = [];
      List activeMembersResponse = [];
      List archivedMembersResponse = [];

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
            scopeKey = _scopeKeyFor(targetMessId, currentUserId);
          }
        }

        var paymentsQuery = _supabase
            .from('mess_member_payments')
            .select('*')
            .eq('owner_id', currentUserId);
        var activeQuery = _supabase
            .from('mess_members')
            .select('id, name, occupied_rooms, floor, mess_id')
            .eq('owner_id', currentUserId);
        var archivedQuery = _supabase
            .from('mess_archive')
            .select('id, name, occupied_rooms, floor, mess_id')
            .eq('owner_id', currentUserId);

        if (targetMessId != null && targetMessId.isNotEmpty) {
          activeQuery = activeQuery.eq('mess_id', targetMessId);
          archivedQuery = archivedQuery.eq('mess_id', targetMessId);
        }

        final results = await Future.wait([
          paymentsQuery.order('month_year', ascending: false),
          activeQuery,
          archivedQuery,
        ]);

        paymentsList = List.from(results[0] as List);
        activeMembersResponse = List.from(results[1] as List);
        archivedMembersResponse = List.from(results[2] as List);

        if (targetMessId != null && targetMessId.isNotEmpty) {
          final Set<String> messMemberIds = {
            for (var m in [...activeMembersResponse, ...archivedMembersResponse])
              if (m['id'] != null) m['id'].toString(),
          };
          paymentsList = paymentsList.where((p) {
            final pMessId = p['mess_id']?.toString();
            if (pMessId != null && pMessId.isNotEmpty) {
              return pMessId == targetMessId;
            }
            final mId = p['member_id']?.toString();
            return mId != null && messMemberIds.contains(mId);
          }).toList();
        }

        await _cacheDataLocally(
          scopeKey,
          paymentsList,
          activeMembersResponse,
          archivedMembersResponse,
        );
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
            "🌐 Network offline. Loading month collections from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally(scopeKey);
        paymentsList = List.from(cached['payments'] ?? []);
        activeMembersResponse = List.from(cached['activeMembers'] ?? []);
        archivedMembersResponse = List.from(cached['archivedMembers'] ?? []);

        if (targetMessId != null && targetMessId.isNotEmpty) {
          final Set<String> messMemberIds = {
            for (var m in [...activeMembersResponse, ...archivedMembersResponse])
              if (m['id'] != null) m['id'].toString(),
          };
          paymentsList = paymentsList.where((p) {
            final pMessId = p['mess_id']?.toString();
            if (pMessId != null && pMessId.isNotEmpty) {
              return pMessId == targetMessId;
            }
            final mId = p['member_id']?.toString();
            return mId != null && messMemberIds.contains(mId);
          }).toList();
        }

        if (mounted) setState(() => _isOfflineMode = true);
      }

      if (paymentsList.isEmpty) return [];

      final Map<String, Map<String, dynamic>> memberMap = {};
      for (var m in [...activeMembersResponse, ...archivedMembersResponse]) {
        if (m['id'] != null) {
          memberMap[m['id'].toString()] = Map<String, dynamic>.from(m as Map);
        }
      }

      for (var payment in paymentsList) {
        final memberId = payment['member_id']?.toString();

        if (memberId != null && memberMap.containsKey(memberId)) {
          payment['mess_members'] = memberMap[memberId];
        } else {
          payment['mess_members'] = {
            'name': payment['member_name'] ?? 'Archived/Deleted Member',
            'occupied_rooms': payment['occupied_rooms'] ?? 'N/A',
            'floor': 1,
          };
        }
      }

      return paymentsList;
    } catch (e) {
      debugPrint("Error fetching monthly collections: $e");
      return [];
    }
  }

  String _formatPaymentDate(dynamic rawDate) {
    if (rawDate == null) return '';
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) return rawDate.toString();

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year}';
  }

  // Grouping helper mapping raw payments by month and room with safe double types
  Map<String, Map<String, dynamic>> _groupCollectionsByMonth(List payments) {
    Map<String, Map<String, dynamic>> groupedData = {};

    for (var p in payments) {
      final monthYear = p['month_year']?.toString() ?? 'Unknown Month';
      final memberInfo = p['mess_members'] is Map<String, dynamic>
          ? p['mess_members'] as Map<String, dynamic>
          : <String, dynamic>{};

      final roomNo = memberInfo['occupied_rooms']?.toString() ?? 'N/A';

      final rent = (p['rent_amount'] as num?)?.toDouble() ?? 0.0;
      final elec = (p['electricity_bill'] as num?)?.toDouble() ?? 0.0;
      final totalPaid = (p['total_paid'] as num?)?.toDouble() ?? (rent + elec);

      final formattedDate = _formatPaymentDate(p['payment_date'] ?? p['created_at']);

      groupedData.putIfAbsent(monthYear, () => {
        'total_collection': 0.0,
        'rooms': <String, Map<String, dynamic>>{}
      });

      double currentMonthTotal = (groupedData[monthYear]!['total_collection'] as num).toDouble();
      groupedData[monthYear]!['total_collection'] = currentMonthTotal + totalPaid;

      var roomsMap = groupedData[monthYear]!['rooms'] as Map<String, dynamic>;

      roomsMap.putIfAbsent(roomNo, () => {
        'room_number': roomNo,
        'dates': <String>{},
        'total_rent': 0.0,
        'total_elec': 0.0,
        'room_total': 0.0,
        'members': []
      });

      var roomData = roomsMap[roomNo] as Map<String, dynamic>;

      if (formattedDate.isNotEmpty) {
        (roomData['dates'] as Set<String>).add(formattedDate);
      }

      roomData['total_rent'] = (roomData['total_rent'] as num).toDouble() + rent;
      roomData['total_elec'] = (roomData['total_elec'] as num).toDouble() + elec;
      roomData['room_total'] = (roomData['room_total'] as num).toDouble() + totalPaid;

      List membersList = roomData['members'] as List;
      membersList.add({
        'name': memberInfo['name']?.toString() ?? 'Unknown',
        'rent': rent,
        'elec': elec,
        'total': totalPaid,
        'date': formattedDate,
      });
    }

    return groupedData;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Colors.blue;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Month-Wise Collections'),
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
          : _groupedCollections.isEmpty
          ? const Center(child: Text('No collection records found.'))
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _groupedCollections.entries.map((monthEntry) {
            final monthName = monthEntry.key;
            final monthData = monthEntry.value;
            final totalCollection = (monthData['total_collection'] as num).toDouble();
            final roomsMap = monthData['rooms'] as Map<String, dynamic>;

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                title: Text(
                  monthName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  'Total Collection: ৳${totalCollection.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: roomsMap.entries.map((roomEntry) {
                  final roomNo = roomEntry.key;
                  final roomData = roomEntry.value as Map<String, dynamic>;
                  final roomTotal = (roomData['room_total'] as num).toDouble();
                  final members = roomData['members'] as List;
                  final datesSet = roomData['dates'] as Set<String>;
                  final dateLabel = datesSet.join(', ');

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Room $roomNo',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: primaryColor,
                                    ),
                                  ),
                                  if (dateLabel.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          dateLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '৳${roomTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        ...members.map(
                              (m) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${m['name']}',
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  'Rent: ৳${m['rent']} + Elec: ৳${m['elec']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          }).toList(),
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
}