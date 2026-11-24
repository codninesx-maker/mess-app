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
  final String? messId;
  final String? messName;

  const ShowMembersDetailsScreen({
    super.key,
    this.messId,
    this.messName,
  });

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
  String? _resolvedMessId;

  // Local Cache Keys
  static const String _cacheMembersKey = 'offline_cache_show_members_list';
  static const String _cachePaymentsKey = 'offline_cache_show_members_payments';

  String _scopeKeyFor(String? messId, String userId) {
    return (messId != null && messId.isNotEmpty) ? messId : userId;
  }

  String _membersCacheKey(String scopeKey) => '${_cacheMembersKey}_$scopeKey';
  String _paymentsCacheKey(String scopeKey) => '${_cachePaymentsKey}_$scopeKey';

  @override
  void initState() {
    super.initState();
    _resolvedMessId =
    (widget.messId != null && widget.messId!.isNotEmpty) ? widget.messId : null;
    _fetchMembersAndElectricity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cacheDataLocally(
      String scopeKey,
      List members,
      List payments,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_membersCacheKey(scopeKey), jsonEncode(members));
    await prefs.setString(_paymentsCacheKey(scopeKey), jsonEncode(payments));
  }

  Future _loadCachedDataLocally(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final membersStr = prefs.getString(_membersCacheKey(scopeKey));
      final paymentsStr = prefs.getString(_paymentsCacheKey(scopeKey));
      return {
        'members': membersStr != null ? jsonDecode(membersStr) as List : [],
        'payments': paymentsStr != null ? jsonDecode(paymentsStr) as List : [],
      };
    } catch (e) {
      debugPrint("Error reading local members cache: $e");
      return {'members': [], 'payments': []};
    }
  }

  bool _isSameMonthAndYear(dynamic rawMonthOrDate, DateTime targetDate) {
    if (rawMonthOrDate == null) return false;
    final text = rawMonthOrDate.toString().toLowerCase().trim();
    if (text.isEmpty) return false;

    final fullMonth = _getMonthName(targetDate.month).toLowerCase(); // e.g. november
    final shortMonth = fullMonth.substring(0, 3); // e.g. nov
    final yearStr = targetDate.year.toString(); // e.g. 2026
    final monthNumPadded = targetDate.month.toString().padLeft(2, '0'); // e.g. 11

    // Matches "November 2026", "Nov 2026", "2026-11", "2026-11-15", "11/2026"
    if (text.contains(yearStr) &&
        (text.contains(fullMonth) ||
            text.contains(shortMonth) ||
            text.contains('-$monthNumPadded') ||
            text.contains('$monthNumPadded/'))) {
      return true;
    }

    // Fallback if only month name is stored without year (e.g. "November")
    if (text == fullMonth || text == shortMonth) {
      return true;
    }

    return false;
  }
  bool _isFullyPaidForCurrentMonth(Map<String, dynamic> member, List payments) {
    final now = DateTime.now();
    final bool hasStarted = _hasMemberStartedForMonth(member, now);
    final double profileDue = (member['due'] as num?)?.toDouble() ?? 0.0;
    final double calcDue =
        ((member['calculated_due'] ?? profileDue) as num?)?.toDouble() ?? 0.0;

    if (calcDue > 0) return false;
    if (!hasStarted) return true;

    final double expectedRent = (member['room_rent'] as num?)?.toDouble() ?? 0;

    double currentMonthRentPaid = 0;
    double currentMonthElecPaid = 0;

    for (var p in payments) {
      if (_isPaymentInCurrentMonth(p, now)) {
        currentMonthRentPaid += (p['rent_amount'] as num?)?.toDouble() ?? 0;
        currentMonthElecPaid +=
            (p['electricity_bill'] as num?)?.toDouble() ?? 0;
      }
    }

    final bool isRentPaid = expectedRent > 0
        ? currentMonthRentPaid >= expectedRent
        : currentMonthRentPaid > 0;
    final bool isElecPaid = _currentMonthElectricityShare <= 0 ||
        currentMonthElecPaid >= _currentMonthElectricityShare;

    return isRentPaid && isElecPaid;
  }

  bool _hasMemberStartedForMonth(Map<String, dynamic> member, DateTime referenceDate) {
    final rawEntryDate = member['entry_date']?.toString().trim();
    if (rawEntryDate != null && rawEntryDate.isNotEmpty) {
      final parsedDate = DateTime.tryParse(rawEntryDate);
      if (parsedDate != null) {
        // Compare by year & month (end of current month) so entry on 2026-11-23 counts for Nov 2026,
        // while entry on 2026-12-01 does NOT count for Nov 2026.
        final currentYearMonth = referenceDate.year * 12 + referenceDate.month;
        final entryYearMonth = parsedDate.year * 12 + parsedDate.month;
        if (entryYearMonth > currentYearMonth) {
          return false;
        }
      }
    }
    // Fallback check on the `month` text column if entry_date is missing
    final monthText = (member['month'] ?? '').toString().toLowerCase().trim();
    if (monthText.isNotEmpty && (rawEntryDate == null || rawEntryDate.isEmpty)) {
      const monthOrder = {
        'january': 1, 'jan': 1,
        'february': 2, 'feb': 2,
        'march': 3, 'mar': 3,
        'april': 4, 'apr': 4,
        'may': 5,
        'june': 6, 'jun': 6,
        'july': 7, 'jul': 7,
        'august': 8, 'aug': 8,
        'september': 9, 'sep': 9, 'sept': 9,
        'october': 10, 'oct': 10,
        'november': 11, 'nov': 11,
        'december': 12, 'dec': 12,
      };
      final entryMonthNum = monthOrder[monthText];
      if (entryMonthNum != null) {
        // If entryMonthNum is ahead of referenceDate.month in the same calendar year
        if (entryMonthNum > referenceDate.month &&
            !(referenceDate.month == 11 && entryMonthNum == 12 &&
                (rawEntryDate ?? '').contains('2025'))) {
          return false;
        }
      }
    }

    return true;
  }
  Map<String, double> _extractPaymentAmounts(Map<String, dynamic> p) {
    final typeText =
    (p['payment_type'] ?? p['type'] ?? p['category'] ?? p['purpose'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    double rentVal =
    ((p['rent_amount'] ?? p['rent_paid'] ?? 0) as num).toDouble();
    double elecVal = ((p['electricity_bill'] ??
        p['electricity_paid'] ??
        p['electricity_amount'] ??
        0) as num)
        .toDouble();

    final double genericAmt =
    ((p['amount'] ?? p['paid_amount'] ?? p['paid'] ?? 0) as num).toDouble();

    // If neither specific rent nor electricity column was populated, use generic amount
    if (rentVal == 0 && elecVal == 0 && genericAmt > 0) {
      if (typeText.contains('elec')) {
        elecVal = genericAmt;
      } else {
        rentVal = genericAmt;
      }
    }

    return {
      'rent': rentVal,
      'elec': elecVal,
      'total': rentVal + elecVal,
    };
  }

  Map<String, double> _calculateMemberDueBreakdown(
      Map<String, dynamic> member,
      double defaultMonthlyElectricityShare,
      ) {
    final now = DateTime.now();
    final bool hasStartedCurrentMonth = _hasMemberStartedForMonth(member, now);

    // Current month rent & electricity share (0 if member hasn't started yet)
    final double monthlyRent = hasStartedCurrentMonth
        ? ((member['room_rent'] ??
        member['monthly_rent'] ??
        member['rent'] ??
        0) as num)
        .toDouble()
        : 0.0;

    final double memberElec =
    ((member['electricity_share'] ?? member['electricity_bill'] ?? 0) as num)
        .toDouble();
    final double monthlyElectricity = hasStartedCurrentMonth
        ? (memberElec > 0 ? memberElec : defaultMonthlyElectricityShare)
        : 0.0;

    // Previous / carried-over due
    final double previousDue =
    ((member['previous_due'] ?? 0) as num).toDouble();

    double currentMonthRentPaid = 0.0;
    double currentMonthElectricityPaid = 0.0;

    final List payments = (member['mess_member_payments'] as List?) ?? [];
    for (final rawPayment in payments) {
      if (rawPayment is! Map) continue;
      final p = Map<String, dynamic>.from(rawPayment);

      final dynamic monthField = p['month_year'] ??
          p['month'] ??
          p['payment_month'] ??
          p['paid_month'] ??
          p['payment_date'] ??
          p['created_at'];

      if (!_isSameMonthAndYear(monthField, now)) continue;

      final amounts = _extractPaymentAmounts(p);
      currentMonthRentPaid += amounts['rent'] ?? 0.0;
      currentMonthElectricityPaid += amounts['elec'] ?? 0.0;
    }

    final double unpaidCurrentRent =
    (monthlyRent - currentMonthRentPaid).clamp(0.0, double.infinity);
    final double unpaidCurrentElectricity =
    (monthlyElectricity - currentMonthElectricityPaid)
        .clamp(0.0, double.infinity);

    final double totalDue =
        previousDue + unpaidCurrentRent + unpaidCurrentElectricity;

    return {
      'previous_due': double.parse(previousDue.toStringAsFixed(2)),
      'unpaid_rent': double.parse(unpaidCurrentRent.toStringAsFixed(2)),
      'unpaid_electricity':
      double.parse(unpaidCurrentElectricity.toStringAsFixed(2)),
      'total_due': double.parse(totalDue.toStringAsFixed(2)),
    };
  }

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

      String? targetMessId = _resolvedMessId;
      String scopeKey = _scopeKeyFor(targetMessId, currentUserId);

      List membersList = [];
      List paymentsList = [];
      double monthlyElecShare = 0;

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

        var membersQuery = _supabase.from('mess_members').select('*');
        var billsQuery = _supabase.from('mess_electricity_bills').select('*');
        var setupQuery = _supabase
            .from('mess_setup')
            .select('monthly_electricity_bill, rent_per_room');

        if (targetMessId != null && targetMessId.isNotEmpty) {
          membersQuery = membersQuery.eq('mess_id', targetMessId);
          billsQuery = billsQuery.eq('mess_id', targetMessId);
          setupQuery = setupQuery.eq('id', targetMessId);
        } else {
          membersQuery = membersQuery.eq('owner_id', currentUserId);
          billsQuery = billsQuery.eq('owner_id', currentUserId);
          setupQuery = setupQuery.eq('owner_id', currentUserId);
        }

        final results = await Future.wait([
          membersQuery.order('name', ascending: false),
          billsQuery,
          setupQuery,
        ]);

        final membersResponse = results[0] as List;
        final billsResponse = results[1] as List;
        final setupResponse = results[2] as List;

        membersList = membersResponse
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
          membersList = membersList.where((m) {
            final memberEmail =
            (m['email'] ?? '').toString().toLowerCase().trim();
            return memberEmail.isEmpty || memberEmail != currentUserEmail;
          }).toList();
        }

        // Fill room rent in member row store rent individually
        for (final m in membersList) {
          final memberRent =
          ((m['room_rent'] ?? m['monthly_rent'] ?? m['rent'] ?? 0) as num)
              .toDouble();
          m['room_rent'] = memberRent;
        }

        // Dynamically calculate current month per-member electricity share
        final double setupElecRate = setupResponse.isNotEmpty
            ? ((setupResponse.first['monthly_electricity_bill'] ?? 0) as num).toDouble()
            : 0.0;

        final now = DateTime.now();
        double currentMonthTotalBills = 0.0;
        for (var b in billsResponse) {
          final amount = ((b['amount'] ?? 0) as num).toDouble();
          if (_isSameMonthAndYear(b['month_year'] ?? b['bill_month'] ?? b['bill_date'], now)) {
            currentMonthTotalBills += amount;
          }
        }

        final int eligibleElectricityMemberCount = membersList
            .where((m) => _hasMemberStartedForMonth(m, now))
            .length;

        if (setupElecRate > 0) {
          monthlyElecShare = setupElecRate;
        } else if (eligibleElectricityMemberCount > 0 && currentMonthTotalBills > 0) {
          monthlyElecShare = double.parse(
              (currentMonthTotalBills / eligibleElectricityMemberCount).toStringAsFixed(2));
        } else {
          monthlyElecShare = 0.0;
        }

        if (membersList.isNotEmpty) {
          final memberIds = membersList.map((m) => m['id']).toList();

          final paymentsResponse = await _supabase
              .from('mess_member_payments')
              .select('*')
              .filter('member_id', 'in', memberIds);

          paymentsList = paymentsResponse
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }

        await _cacheDataLocally(scopeKey, membersList, paymentsList);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
            "🌐 Network offline. Loading members from local cache... Error: $networkError");
        final cached = await _loadCachedDataLocally(scopeKey);
        membersList = (cached['members'] ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        paymentsList = (cached['payments'] ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
          membersList = membersList.where((m) {
            final memberEmail =
            (m['email'] ?? '').toString().toLowerCase().trim();
            return memberEmail.isEmpty || memberEmail != currentUserEmail;
          }).toList();
        }

        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Mutate each map inside membersList directly so UI receives calculated values
      for (int i = 0; i < membersList.length; i++) {
        final member = membersList[i];
        final memberPayments = paymentsList
            .where((p) => p['member_id'] == member['id'])
            .toList();
        member['mess_member_payments'] = memberPayments;

        final breakdown =
        _calculateMemberDueBreakdown(member, monthlyElecShare);
        member['previous_due_calc'] = breakdown['previous_due'];
        member['unpaid_rent_calc'] = breakdown['unpaid_rent'];
        member['unpaid_electricity_calc'] = breakdown['unpaid_electricity'];
        member['calculated_due'] = breakdown['total_due'];
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
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Exit & Archive'),
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
      final effectiveMessId =
      (member['mess_id'] ?? _resolvedMessId ?? widget.messId)
          ?.toString()
          .trim();
      final roomNumber = member['occupied_rooms']?.toString().trim();

      final archiveData = Map<String, dynamic>.from(member)
        ..remove('mess_member_payments')
        ..remove('previous_due_calc')
        ..remove('unpaid_rent_calc')
        ..remove('unpaid_electricity_calc')
        ..remove('calculated_due');

      if (effectiveMessId != null && effectiveMessId.isNotEmpty) {
        archiveData['mess_id'] = effectiveMessId;
      }
      archiveData['exited_at'] = DateTime.now().toIso8601String();

      await _supabase.from('mess_archive').upsert(archiveData);

      var deleteQuery =
      _supabase.from('mess_members').delete().eq('id', member['id']);
      if (effectiveMessId != null && effectiveMessId.isNotEmpty) {
        deleteQuery = deleteQuery.eq('mess_id', effectiveMessId);
      }
      await deleteQuery;

      // Free the room in mess_rooms if no other active member occupies it in this mess
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
    final double dueAmount =
        ((member['calculated_due'] ?? member['due']) as num?)?.toDouble() ?? 0;

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
                        initialAdvancePaid:
                        (member['advance_paid'] as num?)?.toDouble() ?? 0.0,
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
              if (member['occupation'] != null &&
                  member['occupation'].toString().isNotEmpty) ...[
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(member['occupation'],
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.withOpacity(0.08),
                  side: BorderSide(color: Colors.blue.withOpacity(0.2)),
                ),
                const SizedBox(height: 12),
              ],
              _buildDetailRow(
                  Icons.layers, 'Floor', _getFloorOrdinal(member['floor'])),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.meeting_room, 'Room',
                  member['occupied_rooms']?.toString() ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.family_restroom, "Parents Name",
                  member['parents_name'] ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.location_city, 'Home Town',
                  member['home_town'] ?? 'N/A'),
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
                onTap: () =>
                    _makePhoneCall(member['parents_mobile_number'] ?? ''),
              ),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.calendar_today, 'Entry Date',
                  member['entry_date'] ?? 'N/A'),
              const SizedBox(height: 6),
              _buildDetailRow(
                  Icons.date_range, 'Month', member['month'] ?? 'N/A'),
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
                        const Text('Advance Paid',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text('৳${advancePaid.round()}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                      ],
                    ),
                    Container(
                        height: 25,
                        width: 1,
                        color: Colors.grey.withOpacity(0.3)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Due Amount',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text('৳${dueAmount.round()}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                      ],
                    ),
                  ],
                ),
              ),
              if (member['remarks'] != null &&
                  member['remarks'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text('Remarks: ',
                        style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    Expanded(
                      child: Text(
                        member['remarks'],
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic),
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
    final dynamic monthField = p['month_year'] ??
        p['month'] ??
        p['payment_month'] ??
        p['paid_month'] ??
        p['payment_date'] ??
        p['created_at'];
    return _isSameMonthAndYear(monthField, now);
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
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
    final bool hasStartedCurrentMonth = _hasMemberStartedForMonth(member, now);

    double totalPaidFromLedger = 0.0;
    final Set<String> uniqueMonths = {};

    double currentMonthRentPaid = 0.0;
    double currentMonthElecPaid = 0.0;

    for (var rawP in payments) {
      if (rawP is! Map) continue;
      final p = Map<String, dynamic>.from(rawP);
      final amounts = _extractPaymentAmounts(p);

      final double rentPaid = amounts['rent']!;
      final double elecPaid = amounts['elec']!;
      totalPaidFromLedger += amounts['total']!;

      final monthYear =
      (p['month_year'] ?? p['month'] ?? p['payment_month'] ?? '')
          .toString()
          .trim();
      if (monthYear.isNotEmpty) {
        uniqueMonths.add(monthYear);
      }

      if (_isPaymentInCurrentMonth(p, now)) {
        currentMonthRentPaid += rentPaid;
        currentMonthElecPaid += elecPaid;
      }
    }

    final double profileDue = (member['due'] as num?)?.toDouble() ?? 0.0;
    final double expectedRent = hasStartedCurrentMonth
        ? ((member['room_rent'] as num?)?.toDouble() ?? 0.0)
        : 0.0;
    final double expectedElec =
    hasStartedCurrentMonth ? _currentMonthElectricityShare : 0.0;

    final double totalExpectedThisMonth = expectedRent + expectedElec;
    final double totalPaidThisMonth = currentMonthRentPaid + currentMonthElecPaid;

    final double unpaidThisMonth = totalExpectedThisMonth > 0
        ? (totalExpectedThisMonth - totalPaidThisMonth)
        .clamp(0.0, double.infinity)
        : 0.0;

    // Previous/carried-over due + current month unpaid rent & electricity only
    final double netDue =
        ((member['calculated_due'] ?? (profileDue + unpaidThisMonth)) as num?)
            ?.toDouble() ??
            0.0;

    final bool paidForCurrentMonth =
        _isFullyPaidForCurrentMonth(member, payments) && netDue <= 0;

    String unpaidLabel;
    if (netDue > 0) {
      unpaidLabel = 'Due: ${netDue.round()}';
    } else if (hasStartedCurrentMonth && currentMonthRentPaid < expectedRent) {
      unpaidLabel = 'Room Rent Unpaid';
    } else if (hasStartedCurrentMonth &&
        expectedElec > 0 &&
        currentMonthElecPaid < expectedElec) {
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
                    hasStartedCurrentMonth
                        ? 'Paid ($currentMonthKey)'
                        : 'Starts ${member['month'] ?? 'Future'}',
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