import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'MemberLedgerScreen.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isOfflineMode = false;
  List _archivedMembers = [];
  List _filteredArchivedMembers = [];

  // Local Cache Keys
  static const String _cacheArchiveKey = 'offline_cache_archive_members_list';
  static const String _cacheArchivePaymentsKey = 'offline_cache_archive_payments';

  @override
  void initState() {
    super.initState();
    _fetchArchivedMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cacheDataLocally(List archiveList, List paymentsList) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheArchiveKey, jsonEncode(archiveList));
    await prefs.setString(_cacheArchivePaymentsKey, jsonEncode(paymentsList));
  }

  Future _loadCachedDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final archiveStr = prefs.getString(_cacheArchiveKey);
      final paymentsStr = prefs.getString(_cacheArchivePaymentsKey);
      return {
        'archive': archiveStr != null ? jsonDecode(archiveStr) as List : [],
        'payments': paymentsStr != null ? jsonDecode(paymentsStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local archive cache: $e");
      return {'archive': [], 'payments': []};
    }
  }

  // Fetch archived members and join their payment ledger records with offline cache support
  Future<void> _fetchArchivedMembers() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List archiveList = [];
      List paymentsList = [];

      try {
        // 1. Fetch archive records online
        final archiveResponse = await _supabase
            .from('mess_archive')
            .select('id, name, parents_name, occupation, home_town, mobile_number, parents_mobile_number, floor, occupied_rooms, entry_date, month, advance_paid, due, remarks, exited_at, created_at, exit_date, empty_rooms, owner_id')
            .eq('owner_id', currentUserId)
            .order('exited_at', ascending: false);

        archiveList = List.from(archiveResponse);

        if (archiveList.isNotEmpty) {
          final archivedIds = archiveList.map((m) => m['id']).toList();

          // 2. Fetch payments online
          final paymentsResponse = await _supabase
              .from('mess_member_payments')
              .select('*')
              .eq('owner_id', currentUserId)
              .filter('member_id', 'in', archivedIds);

          paymentsList = List.from(paymentsResponse);
        }

        // Cache locally
        await _cacheDataLocally(archiveList, paymentsList);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Fallback to local cache quietly if offline
        debugPrint("🌐 Network offline. Loading archived members from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally();
        archiveList = cached['archive']!;
        paymentsList = cached['payments']!;
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // 3. Attach payments locally to each member map
      for (var member in archiveList) {
        member['mess_member_payments'] = paymentsList
            .where((p) => p['member_id'] == member['id'])
            .toList();
      }

      if (mounted) {
        setState(() {
          _archivedMembers = archiveList;
          _filteredArchivedMembers = archiveList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching archived members: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Restore member back to active mess_members table
  Future<void> _restoreMember(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Member'),
        content: Text('Do you want to restore ${member['name']} back to active members?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final restoredData = Map<String, dynamic>.from(member);
        final archiveId = restoredData['id'];

        restoredData.remove('exited_at');
        restoredData.remove('created_at');
        restoredData.remove('mess_member_payments');

        await _supabase.from('mess_members').upsert(restoredData);
        await _supabase.from('mess_archive').delete().eq('id', archiveId);

        _fetchArchivedMembers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member['name']} has been successfully restored!')),
          );
        }
      } catch (e) {
        debugPrint("Error restoring member: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error restoring member: $e')),
          );
        }
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

  String _formatDate(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoString);
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanNumber.isEmpty) return;

    final Uri launchUri = Uri(
      scheme: 'tel',
      path: cleanNumber,
    );

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

  void _filterArchive(String query) {
    if (query.isEmpty) {
      setState(() => _filteredArchivedMembers = _archivedMembers);
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredArchivedMembers = _archivedMembers.where((member) {
        final name = (member['name'] ?? '').toString().toLowerCase();
        final mobile = (member['mobile_number'] ?? '').toString().toLowerCase();
        final town = (member['home_town'] ?? '').toString().toLowerCase();
        final roomNumber = (member['occupied_rooms'] ?? '').toString().toLowerCase();

        return name.contains(lowerQuery) ||
            mobile.contains(lowerQuery) ||
            town.contains(lowerQuery) ||
            roomNumber.contains(lowerQuery);
      }).toList();
    });
  }

  void _showArchivedMemberDetailsDialog(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.orange.withOpacity(0.1),
              child: const Icon(Icons.person_off, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member['name'] ?? 'N/A',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Exited: ${_formatDate(member['exited_at'])}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ],
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
                  double advancePaid = (member['advance_paid'] as num?)?.toDouble() ?? 0.0;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MemberLedgerScreen(
                        memberId: member['id']?.toString() ?? '',
                        memberName: member['name']?.toString() ?? 'Member',
                        initialAdvancePaid: advancePaid,
                      ),
                    ),
                  );
                } else if (value == 'restore') {
                  Navigator.pop(ctx);
                  _restoreMember(member);
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
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.settings_backup_restore, size: 20, color: Colors.green),
                      SizedBox(width: 12),
                      Text('Restore Member', style: TextStyle(color: Colors.green)),
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
                        Text('৳${member['due'] ?? 0}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Archived Members',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterArchive,
              decoration: InputDecoration(
                hintText: 'Search archived members by name, mobile, room...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterArchive('');
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _filteredArchivedMembers.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No archived members found', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _fetchArchivedMembers,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: _filteredArchivedMembers.length,
                itemBuilder: (context, index) {
                  final member = _filteredArchivedMembers[index];
                  return _buildArchivedMemberCard(member);
                },
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

  Widget _buildArchivedMemberCard(Map<String, dynamic> member) {
    final double dueAmount = (member['due'] as num?)?.toDouble() ?? 0.0;
    final List payments = member['mess_member_payments'] ?? [];

    double totalPaidFromLedger = 0.0;
    for (var p in payments) {
      totalPaidFromLedger += (p['total_paid'] as num?)?.toDouble() ?? 0.0;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showArchivedMemberDetailsDialog(member),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              const Icon(Icons.person_off_outlined, size: 20, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'] ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${payments.length} month(s) recorded',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Room ${member['occupied_rooms'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '৳$totalPaidFromLedger',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    dueAmount > 0 ? 'Due: ৳$dueAmount' : 'Clear',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: dueAmount > 0 ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$title: ',
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
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
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
            if (isValidValue)
              const Icon(Icons.call, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}