import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewMessDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> messData;

  const ViewMessDetailsScreen({
    super.key,
    required this.messData,
  });

  @override
  State<ViewMessDetailsScreen> createState() => _ViewMessDetailsScreenState();
}

class _ViewMessDetailsScreenState extends State<ViewMessDetailsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoadingStats = true;
  bool _isOfflineMode = false;
  int _activeMembersCount = 0;
  int _createdRoomsCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchTenantMetrics();
  }

  // Local cache keys using owner_id for multi-tenant isolation
  String get _cacheMembersKey => 'offline_cache_members_${widget.messData['owner_id']}';
  String get _cacheRoomsKey => 'offline_cache_rooms_${widget.messData['owner_id']}';

  Future<void> _cacheMetricsLocally(int membersCount, int roomsCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cacheMembersKey, membersCount);
    await prefs.setInt(_cacheRoomsKey, roomsCount);
  }

  Future _loadCachedMetricsLocally() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'members': prefs.getInt(_cacheMembersKey) ?? 0,
      'rooms': prefs.getInt(_cacheRoomsKey) ?? 0,
    };
  }

  Future<void> _fetchTenantMetrics() async {
    final ownerId = widget.messData['owner_id']?.toString();
    if (ownerId == null || ownerId.isEmpty) {
      if (mounted) setState(() => _isLoadingStats = false);
      return;
    }

    try {
      int membersCount = 0;
      int roomsCount = 0;

      try {
        // Attempt online fetch from Supabase
        final results = await Future.wait([
          _supabase.from('mess_members').select('id').eq('owner_id', ownerId),
          _supabase.from('mess_rooms').select('id').eq('owner_id', ownerId),
        ]);

        membersCount = (results[0] as List).length;
        roomsCount = (results[1] as List).length;

        // Cache locally for offline use
        await _cacheMetricsLocally(membersCount, roomsCount);

        if (!mounted) return;
        setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Network offline -> Fallback to local cache quietly
        debugPrint("🌐 Network offline. Loading tenant metrics from local cache... Error: $networkError");
        final cached = await _loadCachedMetricsLocally();
        membersCount = cached['members']!;
        roomsCount = cached['rooms']!;

        if (!mounted) return;
        setState(() => _isOfflineMode = true);
      }

      if (!mounted) return;
      setState(() {
        _activeMembersCount = membersCount;
        _createdRoomsCount = roomsCount;
        _isLoadingStats = false;
      });
    } catch (e) {
      debugPrint('Error fetching tenant metrics: $e');
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mess = widget.messData;
    final messName = mess['mess_name'] ?? 'Unnamed Mess';
    final address = mess['address'] ?? 'No Address Provided';
    final contactPhone = mess['contact_phone'] ?? 'N/A';

    final rawOwnerId = mess['owner_id']?.toString() ?? 'N/A';
    final ownerId = rawOwnerId.length > 6
        ? rawOwnerId.substring(rawOwnerId.length - 6)
        : rawOwnerId;

    final totalFloors = mess['total_floors'] ?? 0;
    final totalRooms = mess['total_rooms'] ?? 0;
    final rentPerRoom = mess['rent_per_room'] ?? 0;
    final advanceAmount = mess['advance_amount'] ?? 0;
    final rules = mess['rules']?.toString() ?? 'N/A';
    final createdAt = mess['created_at'] != null
        ? mess['created_at'].toString().split('T').first
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                messName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Summary Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.15),
                      child: Icon(
                        Icons.home_work,
                        size: 30,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            messName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Registered: $createdAt',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Live Tenant Activity Row
            if (_isLoadingStats)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: CircularProgressIndicator.adaptive(),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _statBox(
                      context,
                      icon: Icons.people_outline,
                      label: 'Active Members',
                      value: '$_activeMembersCount',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statBox(
                      context,
                      icon: Icons.meeting_room_outlined,
                      label: 'Rooms Added',
                      value: '$_createdRoomsCount / $totalRooms',
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 20),
            const Text(
              'Configuration & Contact Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // Details Card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _detailTile(Icons.phone_outlined, 'Contact Phone', contactPhone),
                    const Divider(height: 1),
                    _detailTile(Icons.layers_outlined, 'Total Floors', '$totalFloors'),
                    const Divider(height: 1),
                    _detailTile(Icons.door_front_door_outlined, 'Configured Rooms', '$totalRooms'),
                    const Divider(height: 1),
                    _detailTile(Icons.payments_outlined, 'Rent Per Room', '$rentPerRoom'),
                    const Divider(height: 1),
                    _detailTile(Icons.account_balance_wallet_outlined, 'Advance Amount', ' $advanceAmount'),
                    const Divider(height: 1),
                    _detailTile(Icons.rule_outlined, 'Mess Rules', rules),
                    const Divider(height: 1),
                    _detailTile(Icons.fingerprint, 'Owner ID (Last 6)', ownerId),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(
      BuildContext context, {
        required IconData icon,
        required String label,
        required String value,
        required Color color,
      }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}