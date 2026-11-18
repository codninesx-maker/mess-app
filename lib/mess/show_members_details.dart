import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'MemberLedgerScreen.dart';
import 'add_new_members.dart';
import 'edit_member_screen.dart';

class ShowMembersDetailsScreen extends StatefulWidget {
  const ShowMembersDetailsScreen({super.key});

  @override
  State<ShowMembersDetailsScreen> createState() =>
      _ShowMembersDetailsScreenState();
}

class _ShowMembersDetailsScreenState extends State<ShowMembersDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isOfflineMode = false;
  List _allMembers = [];
  List _filteredMembers = [];
  double _currentMonthElectricityShare = 0;

  // Local Cache Keys
  static const String _cacheMembersKey = 'offline_cache_show_members_list';
  static const String _cachePaymentsKey = 'offline_cache_show_members_payments';

  @override
  void initState() {
    super.initState();
    _fetchMembersAndElectricity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cacheDataLocally(List members, List payments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheMembersKey, jsonEncode(members));
    await prefs.setString(_cachePaymentsKey, jsonEncode(payments));
  }

  Future _loadCachedDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final membersStr = prefs.getString(_cacheMembersKey);
      final paymentsStr = prefs.getString(_cachePaymentsKey);
      return {
        'members': membersStr != null ? jsonDecode(membersStr) as List : [],
        'payments': paymentsStr != null ? jsonDecode(paymentsStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local members cache: $e");
      return {'members': [], 'payments': []};
    }
  }

  // Fetch members, payments, and current month electricity shares dynamically
  // Fetch members, payments, and dynamically calculate current month electricity share
  Future<void> _fetchMembersAndElectricity() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;
      final currentUserEmail = user?.email?.toLowerCase().trim();

      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List membersList = [];
      List paymentsList = [];
      double monthlyElecShare = 0;

      try {
        // Fetch members, electricity bills, and setup concurrently
        final results = await Future.wait([
          _supabase
              .from('mess_members')
              .select('*')
              .eq('owner_id', currentUserId)
              .order('name', ascending: false),
          _supabase
              .from('mess_electricity_bills')
              .select('*')
              .eq('owner_id', currentUserId),
          _supabase
              .from('mess_setup')
              .select('monthly_electricity_bill')
              .eq('owner_id', currentUserId),
        ]);

        final membersResponse = results[0] as List;
        final billsResponse = results[1] as List;
        final setupResponse = results[2] as List;

        membersList = List.from(membersResponse);

        if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
          membersList = membersList.where((m) {
            final memberEmail = (m['email'] ?? '').toString().toLowerCase().trim();
            return memberEmail.isEmpty || memberEmail != currentUserEmail;
          }).toList();
        }

        // --- DYNAMICALLY CALCULATE TRUE PER-MEMBER ELECTRICITY SHARE FOR CURRENT MONTH ---
        final now = DateTime.now();
        final currentMonthName = _getMonthName(now.month).toLowerCase();
        final currentYearStr = now.year.toString();

        double currentMonthTotalBills = 0.0;
        for (var b in billsResponse) {
          final monthYear = (b['month_year'] ?? '').toString().toLowerCase().trim();
          final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
          if (monthYear.contains(currentMonthName) && monthYear.contains(currentYearStr)) {
            currentMonthTotalBills += amount;
          }
        }

        int activeMemberCount = membersList.length;
        if (activeMemberCount > 0 && currentMonthTotalBills > 0) {
          monthlyElecShare = double.parse((currentMonthTotalBills / activeMemberCount).toStringAsFixed(2));
        } else if (setupResponse.isNotEmpty) {
          // Fallback to setup table value if no bills found for current month
          monthlyElecShare = (setupResponse.first['monthly_electricity_bill'] as num?)?.toDouble() ?? 0;
        }

        if (membersList.isNotEmpty) {
          final memberIds = membersList.map((m) => m['id']).toList();

          final paymentsResponse = await _supabase
              .from('mess_member_payments')
              .select('*')
              .filter('member_id', 'in', memberIds);

          paymentsList = List.from(paymentsResponse);
        }

        await _cacheDataLocally(membersList, paymentsList);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint("🌐 Network offline. Loading members from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally();
        membersList = cached['members']!;
        paymentsList = cached['payments']!;

        if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
          membersList = membersList.where((m) {
            final memberEmail = (m['email'] ?? '').toString().toLowerCase().trim();
            return memberEmail.isEmpty || memberEmail != currentUserEmail;
          }).toList();
        }

        if (mounted) setState(() => _isOfflineMode = true);
      }

      for (var member in membersList) {
        member['mess_member_payments'] = paymentsList
            .where((p) => p['member_id'] == member['id'])
            .toList();
      }

      if (mounted) {
        setState(() {
          _allMembers = membersList;
          _filteredMembers = membersList;
          _currentMonthElectricityShare = monthlyElecShare;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching members: $e");
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

  void _filterMembers(String query) {
    if (query.isEmpty) {
      setState(() => _filteredMembers = _allMembers);
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredMembers = _allMembers.where((member) {
        final name = (member['name'] ?? '').toString().toLowerCase();
        final mobile = (member['mobile_number'] ?? '').toString().toLowerCase();
        final town = (member['home_town'] ?? '').toString().toLowerCase();
        final month = (member['month'] ?? '').toString().toLowerCase();
        final floorStr = (member['floor'] ?? '').toString().toLowerCase();
        final floorOrdinal = _getFloorOrdinal(member['floor']).toLowerCase();
        final roomNumber = (member['occupied_rooms'] ?? '').toString().toLowerCase();

        return name.contains(lowerQuery) ||
            mobile.contains(lowerQuery) ||
            town.contains(lowerQuery) ||
            month.contains(lowerQuery) ||
            floorStr == lowerQuery ||
            floorOrdinal.contains(lowerQuery) ||
            roomNumber.contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _archiveMember(Map<String, dynamic> member) async {
    final memberName = member['name'] ?? 'this member';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            const Text('Exit & Archive'),
          ],
        ),
        content: Text(
          'Are you sure you want to exit and archive "$memberName"?\n\n'
              'This will move their profile to the archive records while preserving all payment history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Exit'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final archiveData = Map<String, dynamic>.from(member);
      archiveData.remove('mess_member_payments');
      archiveData['exited_at'] = DateTime.now().toIso8601String();

      await _supabase.from('mess_archive').upsert(archiveData);
      await _supabase.from('mess_members').delete().eq('id', member['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$memberName archived successfully!'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _fetchMembersAndElectricity();
    } catch (e) {
      debugPrint("Error archiving member: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  void _showMemberDetailsDialog(Map<String, dynamic> member) {
    final double advancePaid = (member['advance_paid'] as num?)?.toDouble() ?? 0;
    final double dueAmount = (member['due'] as num?)?.toDouble() ?? 0;

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
                    _fetchMembersAndElectricity();
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
                    _fetchMembersAndElectricity();
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
                        Text('৳${advancePaid.round()}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                    Container(height: 25, width: 1, color: Colors.grey.withOpacity(0.3)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Due Amount', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text('৳${dueAmount.round()}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
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
              'Member Details',
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
              onChanged: _filterMembers,
              decoration: InputDecoration(
                hintText: 'Search by room (e.g. 201), floor, name, mobile...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterMembers('');
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
                : _filteredMembers.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No members found', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _fetchMembersAndElectricity,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: _filteredMembers.length,
                itemBuilder: (context, index) {
                  final member = _filteredMembers[index];
                  return _buildMemberCard(member);
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

  bool _isPaymentInCurrentMonth(Map<String, dynamic> p, DateTime now) {
    final monthYear = (p['month_year'] ?? '').toString().toLowerCase();
    if (monthYear.isNotEmpty) {
      if (monthYear.contains(now.year.toString()) &&
          (monthYear.contains(now.month.toString()) ||
              monthYear.contains(_getMonthName(now.month).toLowerCase()) ||
              monthYear.contains(_getShortMonthName(now.month).toLowerCase()))) {
        return true;
      }
    }

    final rawDate = p['payment_date'] ?? p['created_at'];
    if (rawDate != null) {
      final parsedDate = DateTime.tryParse(rawDate.toString());
      if (parsedDate != null &&
          parsedDate.year == now.year &&
          parsedDate.month == now.month) {
        return true;
      }
    }

    return false;
  }

  // Returns true ONLY when both room rent and electricity bill share are paid for the current month
  bool _isFullyPaidForCurrentMonth(Map<String, dynamic> member, List payments) {
    final now = DateTime.now();
    final double expectedRent = (member['room_rent'] as num?)?.toDouble() ?? 0;
    final double memberDue = (member['due'] as num?)?.toDouble() ?? 0.0;

    if (memberDue > 0) return false;

    double currentMonthRentPaid = 0;
    double currentMonthElecPaid = 0;

    for (var p in payments) {
      if (_isPaymentInCurrentMonth(p, now)) {
        currentMonthRentPaid += (p['rent_amount'] as num?)?.toDouble() ?? 0;
        currentMonthElecPaid += (p['electricity_bill'] as num?)?.toDouble() ?? 0;
      }
    }

    final bool isRentPaid = expectedRent > 0
        ? currentMonthRentPaid >= expectedRent
        : currentMonthRentPaid > 0;
    final bool isElecPaid = _currentMonthElectricityShare <= 0 || currentMonthElecPaid >= _currentMonthElectricityShare;

    return isRentPaid && isElecPaid;
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  String _getShortMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  String _getCurrentMonthYearKey() {
    final now = DateTime.now();
    return '${_getMonthName(now.month)} ${now.year}';
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    final List payments = member['mess_member_payments'] ?? [];
    final currentMonthKey = _getCurrentMonthYearKey();
    final now = DateTime.now();

    double totalPaidFromLedger = 0.0;
    final Set<String> uniqueMonths = {};

    double currentMonthRentPaid = 0.0;
    double currentMonthElecPaid = 0.0;

    for (var p in payments) {
      final rentPaid = (p['rent_amount'] as num?)?.toDouble() ?? 0.0;
      final elecPaid = (p['electricity_bill'] as num?)?.toDouble() ?? 0.0;
      totalPaidFromLedger += (rentPaid + elecPaid);

      final monthYear = p['month_year']?.toString().trim();
      if (monthYear != null && monthYear.isNotEmpty) {
        uniqueMonths.add(monthYear);
      }

      if (_isPaymentInCurrentMonth(p, now)) {
        currentMonthRentPaid += rentPaid;
        currentMonthElecPaid += elecPaid;
      }
    }

    final bool paidForCurrentMonth = _isFullyPaidForCurrentMonth(member, payments);
    final double profileDue = (member['due'] as num?)?.toDouble() ?? 0.0;
    final double expectedRent = (member['room_rent'] as num?)?.toDouble() ?? 0.0;

    // Expected monthly total charges (Room Rent + Dynamic Monthly Electricity Share)
    final double totalExpectedThisMonth = expectedRent + _currentMonthElectricityShare;
    final double totalPaidThisMonth = currentMonthRentPaid + currentMonthElecPaid;

    double unpaidThisMonth = totalExpectedThisMonth > 0
        ? (totalExpectedThisMonth - totalPaidThisMonth).clamp(0.0, double.infinity)
        : 0.0;

    // Net Due = Profile Carried-over Due + Unpaid Current Month Balance
    double netDue = profileDue + unpaidThisMonth;

    String unpaidLabel;
    if (netDue > 0) {
      unpaidLabel = 'Due: ${netDue.round()}';
    } else if (currentMonthRentPaid < expectedRent) {
      unpaidLabel = 'Room Rent Unpaid';
    } else if (_currentMonthElectricityShare > 0 && currentMonthElecPaid < _currentMonthElectricityShare) {
      unpaidLabel = 'Elec Bill Unpaid';
    } else {
      unpaidLabel = 'Unpaid';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showMemberDetailsDialog(member),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: Colors.grey),
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
                      'Room ${member['occupied_rooms'] ?? 'N/A'} • ${uniqueMonths.length} month(s)',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '৳${totalPaidFromLedger.round()}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 2),
                  paidForCurrentMonth
                      ? Text(
                    'Paid ($currentMonthKey)',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unpaidLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
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