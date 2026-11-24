import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_new_members.dart';

class EmptyRoomsTab extends StatefulWidget {
  final String? messId;
  final String? messName;
  const EmptyRoomsTab({super.key, this.messId, this.messName});

  @override
  State<EmptyRoomsTab> createState() => _EmptyRoomsTabState();
}

class _EmptyRoomsTabState extends State<EmptyRoomsTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  List<String> _emptyRoomNumbers = [];
  int _totalRoomsCount = 0;
  String? _resolvedMessId;

  String _roomsCacheKey(String scopeKey) =>
      'offline_cache_empty_rooms_mess_rooms_$scopeKey';
  String _membersCacheKey(String scopeKey) =>
      'offline_cache_empty_rooms_active_members_$scopeKey';

  @override
  void initState() {
    super.initState();
    _fetchEmptyRooms();
  }

  @override
  void didUpdateWidget(covariant EmptyRoomsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messId != widget.messId || oldWidget.messName != widget.messName) {
      _fetchEmptyRooms();
    }
  }

  Future<void> _cacheDataLocally(
      String scopeKey,
      List rooms,
      List members,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomsCacheKey(scopeKey), jsonEncode(rooms));
    await prefs.setString(_membersCacheKey(scopeKey), jsonEncode(members));
  }

  Future _loadCachedDataLocally(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final roomsStr = prefs.getString(_roomsCacheKey(scopeKey));
      final membersStr = prefs.getString(_membersCacheKey(scopeKey));
      return {
        'rooms': roomsStr != null ? (jsonDecode(roomsStr) as List) : [],
        'members': membersStr != null ? (jsonDecode(membersStr) as List) : [],
      };
    } catch (e) {
      debugPrint("Error reading local empty rooms cache: $e");
      return {'rooms': [], 'members': []};
    }
  }

  List<String> _generateFallbackRoomNumbers(int totalFloors, int totalRooms) {
    final List<String> generated = [];
    if (totalFloors <= 0 || totalRooms <= 0) return generated;

    int roomsPerFloor = (totalRooms / totalFloors).ceil();
    if (roomsPerFloor <= 0) roomsPerFloor = 9;

    for (int floor = 1; floor <= totalFloors; floor++) {
      for (int seq = 1; seq <= roomsPerFloor; seq++) {
        if (generated.length >= totalRooms) break;
        generated.add('$floor${seq.toString().padLeft(2, '0')}');
      }
    }
    return generated;
  }

  Future<void> _fetchEmptyRooms() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final currentUserId = _supabase.auth.currentUser?.id;

      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      String? targetMessId = widget.messId?.trim();
      if (targetMessId != null && targetMessId.isEmpty) {
        targetMessId = null;
      }

      List messRoomsResponse = [];
      List activeMembersResponse = [];
      Map<String, dynamic>? setupRow;

      // Resolve targetMessId if not explicitly passed
      if (targetMessId == null) {
        try {
          setupRow = await _supabase
              .from('mess_setup')
              .select('id, total_floors, total_rooms')
              .eq('owner_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          targetMessId = setupRow?['id']?.toString();
        } catch (_) {}
      }

      final String cacheScopeKey = targetMessId ?? 'owner_$currentUserId';
      _resolvedMessId = targetMessId;

      try {
        if (targetMessId != null) {
          setupRow ??= await _supabase
              .from('mess_setup')
              .select('id, total_floors, total_rooms')
              .eq('id', targetMessId)
              .maybeSingle();

          messRoomsResponse = await _supabase
              .from('mess_rooms')
              .select('occupied_rooms, empty_rooms, is_occupied')
              .eq('mess_id', targetMessId)
              .order('occupied_rooms', ascending: true);

          activeMembersResponse = await _supabase
              .from('mess_members')
              .select('occupied_rooms')
              .eq('mess_id', targetMessId)
              .not('occupied_rooms', 'is', null);
        } else {
          // Only if no mess_id exists at all, scope strictly to owner_id
          messRoomsResponse = await _supabase
              .from('mess_rooms')
              .select('occupied_rooms, empty_rooms, is_occupied')
              .eq('owner_id', currentUserId)
              .order('occupied_rooms', ascending: true);

          activeMembersResponse = await _supabase
              .from('mess_members')
              .select('occupied_rooms')
              .eq('owner_id', currentUserId)
              .not('occupied_rooms', 'is', null);
        }

        await _cacheDataLocally(
          cacheScopeKey,
          messRoomsResponse,
          activeMembersResponse,
        );
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
          "🌐 Network offline. Loading empty rooms from local cache... Error: $networkError",
        );
        final cached = await _loadCachedDataLocally(cacheScopeKey);
        messRoomsResponse = cached['rooms'] ?? [];
        activeMembersResponse = cached['members'] ?? [];
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Extract configured rooms for THIS mess only
      List<String> allConfiguredRooms = messRoomsResponse
          .map((row) =>
      (row['occupied_rooms'] ?? row['empty_rooms'])?.toString().trim() ??
          '')
          .where((room) => room.isNotEmpty)
          .toList();

      // Fallback only if mess_rooms has 0 rows for this specific mess
      if (allConfiguredRooms.isEmpty && setupRow != null) {
        final int floors = (setupRow['total_floors'] as num?)?.toInt() ?? 1;
        final int totalRooms = (setupRow['total_rooms'] as num?)?.toInt() ?? 0;
        allConfiguredRooms = _generateFallbackRoomNumbers(floors, totalRooms);
      }

      allConfiguredRooms = allConfiguredRooms.toSet().toList()..sort();

      final Set<String> occupiedSet = activeMembersResponse
          .map((m) => m['occupied_rooms']?.toString().trim() ?? '')
          .where((r) => r.isNotEmpty)
          .toSet();

      final List<String> emptyRooms = allConfiguredRooms
          .where((roomNo) => !occupiedSet.contains(roomNo))
          .toList();

      if (mounted) {
        setState(() {
          _emptyRoomNumbers = emptyRooms;
          _totalRoomsCount = allConfiguredRooms.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching empty rooms: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (_emptyRoomNumbers.isEmpty) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: _fetchEmptyRooms,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isOfflineMode) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Text(
                        'OFFLINE MODE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange),
                      ),
                    ),
                  ],
                  const Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green),
                  const SizedBox(height: 12),
                  const Text(
                    'No empty rooms available',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchEmptyRooms,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_isOfflineMode) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      'Viewing offline cached room status',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.meeting_room_outlined,
                      color: Colors.green, size: 32),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available Rooms',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_emptyRoomNumbers.length} out of $_totalRoomsCount total rooms',
                        style:
                        const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: _emptyRoomNumbers.length,
              itemBuilder: (context, index) {
                final roomNo = _emptyRoomNumbers[index];

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final added = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddMembersScreen(
                          messId: _resolvedMessId ?? widget.messId,
                        ),
                      ),
                    );
                    if (added == true) {
                      _fetchEmptyRooms();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Text(
                      'Room $roomNo',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ),
                );
              },
            ),
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
}