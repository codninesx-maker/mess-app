import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_new_members.dart';

class EmptyRoomsTab extends StatefulWidget {
  const EmptyRoomsTab({super.key});

  @override
  State<EmptyRoomsTab> createState() => _EmptyRoomsTabState();
}

class _EmptyRoomsTabState extends State<EmptyRoomsTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  List<String> _emptyRoomNumbers = [];
  int _totalRoomsCount = 0;

  // Local Cache Keys
  static const String _cacheMessRoomsKey = 'offline_cache_empty_rooms_mess_rooms';
  static const String _cacheActiveMembersKey = 'offline_cache_empty_rooms_active_members';

  @override
  void initState() {
    super.initState();
    _fetchEmptyRooms();
  }

  Future<void> _cacheDataLocally(List rooms, List members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheMessRoomsKey, jsonEncode(rooms));
    await prefs.setString(_cacheActiveMembersKey, jsonEncode(members));
  }

  Future _loadCachedDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final roomsStr = prefs.getString(_cacheMessRoomsKey);
      final membersStr = prefs.getString(_cacheActiveMembersKey);
      return {
        'rooms': roomsStr != null ? jsonDecode(roomsStr) as List : [],
        'members': membersStr != null ? jsonDecode(membersStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local empty rooms cache: $e");
      return {'rooms': [], 'members': []};
    }
  }

  Future<void> _fetchEmptyRooms() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List messRoomsResponse = [];
      List activeMembersResponse = [];

      try {
        // 1. Fetch real rooms online
        messRoomsResponse = await _supabase
            .from('mess_rooms')
            .select('occupied_rooms, empty_rooms')
            .eq('owner_id', currentUserId)
            .order('occupied_rooms', ascending: true);

        // 2. Fetch occupied room numbers from active members online
        activeMembersResponse = await _supabase
            .from('mess_members')
            .select('occupied_rooms')
            .eq('owner_id', currentUserId)
            .not('occupied_rooms', 'is', null);

        // Cache locally for offline use
        await _cacheDataLocally(messRoomsResponse, activeMembersResponse);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Fallback to local cache quietly if offline
        debugPrint("🌐 Network offline. Loading empty rooms from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally();
        messRoomsResponse = cached['rooms']!;
        activeMembersResponse = cached['members']!;
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Extract all configured room numbers
      final List<String> allConfiguredRooms = messRoomsResponse
          .map((row) => (row['occupied_rooms'] ?? row['empty_rooms'])?.toString().trim() ?? '')
          .where((room) => room.isNotEmpty)
          .toList();

      allConfiguredRooms.sort();

      final Set<String> occupiedSet = activeMembersResponse
          .map((m) => m['occupied_rooms']?.toString().trim() ?? '')
          .where((r) => r.isNotEmpty)
          .toSet();

      // Filter out occupied rooms to calculate real empty rooms
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Text(
                        'OFFLINE MODE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                  const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
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
                      'Viewing offline cached room status',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
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
                  const Icon(Icons.meeting_room_outlined, color: Colors.green, size: 32),
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
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
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
                        builder: (context) => const AddMembersScreen(),
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