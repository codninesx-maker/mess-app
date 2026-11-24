import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:mess_sur/mess/MemberLedgerScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'edit_member_screen.dart';

class OccupiedRoomsTab extends StatefulWidget {
  final String? messId;
  final String? messName;
  const OccupiedRoomsTab({super.key, this.messId, this.messName});

  @override
  State<OccupiedRoomsTab> createState() => _OccupiedRoomsTabState();
}

class _OccupiedRoomsTabState extends State<OccupiedRoomsTab> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  List<String> _occupiedRoomNumbers = [];
  Map<String, List> _roomOccupantsMap = {};
  int _totalRoomsCount = 0;
  String? _resolvedMessId;

  // Local Cache Keys
  static const String _cacheSetupPrefix = 'offline_cache_occupied_rooms_setup';
  static const String _cacheMembersPrefix = 'offline_cache_occupied_rooms_members';

  String _setupCacheKey(String scopeKey) => '${_cacheSetupPrefix}_$scopeKey';
  String _membersCacheKey(String scopeKey) => '${_cacheMembersPrefix}_$scopeKey';

  @override
  void initState() {
    super.initState();
    _fetchOccupiedRooms();
  }

  @override
  void didUpdateWidget(covariant OccupiedRoomsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messId != widget.messId || oldWidget.messName != widget.messName) {
      _fetchOccupiedRooms();
    }
  }

  Future<void> _cacheDataLocally(
      String scopeKey,
      Map<String, dynamic>? setup,
      List members,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    if (setup != null) {
      await prefs.setString(_setupCacheKey(scopeKey), jsonEncode(setup));
    }
    await prefs.setString(_membersCacheKey(scopeKey), jsonEncode(members));
  }

  Future _loadCachedDataLocally(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final setupStr = prefs.getString(_setupCacheKey(scopeKey));
      final membersStr = prefs.getString(_membersCacheKey(scopeKey));
      return {
        'setup': setupStr != null
            ? Map<String, dynamic>.from(jsonDecode(setupStr) as Map)
            : null,
        'members': membersStr != null ? (jsonDecode(membersStr) as List) : [],
      };
    } catch (e) {
      debugPrint("Error reading local occupied rooms cache: $e");
      return {'setup': null, 'members': []};
    }
  }

  Future<void> _fetchOccupiedRooms() async {
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

      String cacheScopeKey = targetMessId ?? 'owner_$currentUserId';
      Map<String, dynamic>? setupResponse;
      List membersResponse = [];

      try {
        // 1. Fetch setup config online scoped to mess_id when available
        var setupQuery =
        _supabase.from('mess_setup').select('id, total_rooms');
        if (targetMessId != null) {
          setupQuery = setupQuery.eq('id', targetMessId);
        } else {
          setupQuery = setupQuery.eq('owner_id', currentUserId);
        }

        setupResponse = await setupQuery
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (targetMessId == null) {
          targetMessId = setupResponse?['id']?.toString();
          if (targetMessId != null && targetMessId.isNotEmpty) {
            cacheScopeKey = targetMessId;
          }
        }

        _resolvedMessId = targetMessId;

        // 2. Fetch members online scoped strictly to mess_id when available
        var membersQuery = _supabase.from('mess_members').select('*');
        if (targetMessId != null && targetMessId.isNotEmpty) {
          membersQuery = membersQuery.eq('mess_id', targetMessId);
        } else {
          membersQuery = membersQuery.eq('owner_id', currentUserId);
        }
        membersResponse = await membersQuery.order('name', ascending: true);

        await _cacheDataLocally(cacheScopeKey, setupResponse, membersResponse);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
          "🌐 Network offline. Loading occupied rooms from local cache... Error: $networkError",
        );
        final cached = await _loadCachedDataLocally(cacheScopeKey);
        setupResponse = cached['setup'] as Map<String, dynamic>?;
        membersResponse = (cached['members'] as List?) ?? [];
        if (mounted) setState(() => _isOfflineMode = true);
      }

      final totalRooms =
          (setupResponse?['total_rooms'] as num?)?.toInt() ?? 55;

      Map<String, List> occupantsMap = {};
      for (var member in membersResponse) {
        final roomNo = member['occupied_rooms']?.toString().trim();
        if (roomNo != null && roomNo.isNotEmpty) {
          occupantsMap.putIfAbsent(roomNo, () => []).add(member);
        }
      }

      List<String> occupiedRooms = occupantsMap.keys.toList();
      occupiedRooms.sort();

      if (mounted) {
        setState(() {
          _occupiedRoomNumbers = occupiedRooms;
          _roomOccupantsMap = occupantsMap;
          _totalRoomsCount = totalRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching occupied rooms: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getFloorOrdinal(dynamic floorNum) {
    if (floorNum == null) return 'N/A';
    int? f = int.tryParse(floorNum.toString());
    if (f == null) return 'N/A';

    if (f == 1) return '1st Floor';
    if (f == 2) return '2nd Floor';
    if (f == 3) return '3rd Floor';
    return '${f}th Floor';
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanNumber.isEmpty) return;

    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch phone dialer for $phoneNumber')),
        );
      }
    }
  }

  Future<void> _archiveMember(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Member'),
        content: Text(
          'Are you sure you want to mark ${member['name']} as exited? This will move them to archives.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Exit', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final effectiveMessId =
        (member['mess_id'] ?? _resolvedMessId ?? widget.messId)
            ?.toString()
            .trim();
        final roomNumber = member['occupied_rooms']?.toString().trim();

        final archiveData = Map<String, dynamic>.from(member);
        archiveData.remove('id');
        archiveData.remove('mess_member_payments');
        if (effectiveMessId != null && effectiveMessId.isNotEmpty) {
          archiveData['mess_id'] = effectiveMessId;
        }
        archiveData['exited_at'] = DateTime.now().toIso8601String();

        await _supabase.from('mess_archive').insert(archiveData);

        var deleteQuery =
        _supabase.from('mess_members').delete().eq('id', member['id']);
        if (effectiveMessId != null && effectiveMessId.isNotEmpty) {
          deleteQuery = deleteQuery.eq('mess_id', effectiveMessId);
        }
        await deleteQuery;

        if (effectiveMessId != null &&
            effectiveMessId.isNotEmpty &&
            roomNumber != null &&
            roomNumber.isNotEmpty) {
          final remainingInRoom = await _supabase
              .from('mess_members')
              .select('id')
              .eq('mess_id', effectiveMessId)
              .eq('occupied_rooms', roomNumber)
              .limit(1);

          if ((remainingInRoom as List).isEmpty) {
            await _supabase
                .from('mess_rooms')
                .update({
              'is_occupied': false,
              'empty_rooms': roomNumber,
            })
                .eq('mess_id', effectiveMessId)
                .eq('occupied_rooms', roomNumber);
          }
        }

        _fetchOccupiedRooms();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member['name']} has been exited and archived.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error archiving member: $e')),
          );
        }
      }
    }
  }

  void _showMemberDetailsDialog(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                member['name'] ?? 'N/A',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[700]),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) async {
                if (value == 'ledger') {
                  Navigator.pop(ctx);
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MemberLedgerScreen(
                        memberId: member['id']?.toString() ?? '',
                        memberName: member['name']?.toString() ?? 'Member',
                        initialAdvancePaid: (member['advance_paid'] as num?)?.toDouble() ?? 0.0,
                      ),
                    ),
                  );
                  if (updated == true) {
                    _fetchOccupiedRooms();
                  }
                } else if (value == 'edit') {
                  Navigator.pop(ctx);
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditMemberScreen(member: member),
                    ),
                  );
                  if (updated == true) {
                    _fetchOccupiedRooms();
                  }
                } else if (value == 'exit') {
                  Navigator.pop(ctx);
                  _archiveMember(member);
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'ledger',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: Colors.green),
                      SizedBox(width: 12),
                      Text('Payment Ledger'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.blue),
                      SizedBox(width: 12),
                      Text('Edit Member'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'exit',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, size: 20, color: Colors.orange),
                      SizedBox(width: 12),
                      Text('Exit Member', style: TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (member['occupation'] != null && member['occupation'].toString().isNotEmpty) ...[
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(member['occupation'], style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.withOpacity(0.08),
                  side: BorderSide(color: Colors.blue.withOpacity(0.2)),
                ),
                const SizedBox(height: 12),
              ],
              _buildDetailRow(Icons.layers, 'Floor', _getFloorOrdinal(member['floor'])),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.meeting_room, 'Room', member['occupied_rooms']?.toString() ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.family_restroom, "Parents Name", member['parents_name'] ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.location_city, 'Home Town', member['home_town'] ?? 'N/A'),
              const SizedBox(height: 6),
              _buildClickableDetailRow(
                Icons.phone,
                'Mobile Number',
                member['mobile_number'] ?? 'N/A',
                onTap: () => _makePhoneCall(member['mobile_number'] ?? ''),
              ),
              const SizedBox(height: 6),
              _buildClickableDetailRow(
                Icons.phone_android,
                "Parents Mobile",
                member['parents_mobile_number'] ?? 'N/A',
                onTap: () => _makePhoneCall(member['parents_mobile_number'] ?? ''),
              ),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.calendar_today, 'Entry Date', member['entry_date'] ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.date_range, 'Month', member['month'] ?? 'N/A'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Advance Paid', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text('৳${member['advance_paid'] ?? 0}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    Container(height: 25, width: 1, color: Colors.grey.withOpacity(0.3)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Due Amount', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text('${member['due'] ?? 0}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ),
              ),
              if (member['remarks'] != null && member['remarks'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text('Remarks: ', style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w500)),
                    Expanded(
                      child: Text(
                        member['remarks'],
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleRoomTap(String roomNumber, List occupants) {
    if (occupants.isEmpty) return;

    if (occupants.length == 1) {
      _showMemberDetailsDialog(occupants.first);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Room $roomNumber Occupants'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: occupants.length,
              itemBuilder: (context, index) {
                final member = occupants[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                  title: Text(member['name'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Mobile: ${member['mobile_number'] ?? 'N/A'}', style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMemberDetailsDialog(member);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$title: ',
          style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildClickableDetailRow(
      IconData icon,
      String title,
      String value, {
        required VoidCallback onTap,
      }) {
    final bool isValidValue = value.isNotEmpty && value != 'N/A';

    return InkWell(
      onTap: isValidValue ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isValidValue ? Colors.blue : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              '$title: ',
              style: TextStyle(color: Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isValidValue ? Colors.blue : Colors.black,
                  decoration: isValidValue ? TextDecoration.underline : TextDecoration.none,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isValidValue) const Icon(Icons.call, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (_occupiedRoomNumbers.isEmpty) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: _fetchOccupiedRooms,
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
                  const Icon(Icons.meeting_room, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'No occupied rooms',
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
        onRefresh: _fetchOccupiedRooms,
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
                      'Viewing offline cached occupied rooms',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sensor_door, color: Colors.blue, size: 32),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Occupied Rooms',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_occupiedRoomNumbers.length} out of $_totalRoomsCount total rooms',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Color Legend
                  Row(
                    children: [
                      _buildLegendDot(Colors.blue, 'Single Occupant'),
                      const SizedBox(width: 16),
                      _buildLegendDot(Colors.orange, '2+ / Transition Room'),
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
              itemCount: _occupiedRoomNumbers.length,
              itemBuilder: (context, index) {
                final roomNo = _occupiedRoomNumbers[index];
                final occupants = _roomOccupantsMap[roomNo] ?? [];
                final bool isMultiOccupant = occupants.length > 1;
                final Color roomColor = isMultiOccupant ? Colors.orange : Colors.blue;

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _handleRoomTap(roomNo, occupants),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: roomColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: roomColor.withOpacity(isMultiOccupant ? 0.6 : 0.3),
                        width: isMultiOccupant ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Room $roomNo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: roomColor,
                          ),
                        ),
                        if (isMultiOccupant)
                          Text(
                            '${occupants.length} members',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: roomColor,
                            ),
                          ),
                      ],
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

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}