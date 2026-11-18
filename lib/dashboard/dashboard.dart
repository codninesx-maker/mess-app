import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/3dotPanel/manage_ur_3dot_Panel.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:mess_sur/mess/manage_ur_mess_card.dart';
import 'package:mess_sur/messmeal/ManageMealCard.dart';
import 'package:mess_sur/signin/otp_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;

  List _rooms = [];
  List _members = [];
  int _totalConfiguredRooms = 0;

  double _totalPaidAll = 0;
  double _currentMonthPaid = 0;
  double _totalDue = 0;

  bool get _isAdmin {
    final email = _supabase.auth.currentUser?.email;
    return email?.toLowerCase() == 'codninesx@gmail.com';
  }

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // --- LOCAL CACHE KEYS ---
  static const String _cacheRoomsKey = 'offline_cache_rooms';
  static const String _cacheSetupKey = 'offline_cache_setup';
  static const String _cacheMembersKey = 'offline_cache_members';
  static const String _cachePaymentsKey = 'offline_cache_payments';

  /// Save fetched data to local SharedPreferences
  Future<void> _cacheDataLocally({
    required List rooms,
    required List setup,
    required List members,
    required List payments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheRoomsKey, jsonEncode(rooms));
    await prefs.setString(_cacheSetupKey, jsonEncode(setup));
    await prefs.setString(_cacheMembersKey, jsonEncode(members));
    await prefs.setString(_cachePaymentsKey, jsonEncode(payments));
  }

  /// Load cached data from local SharedPreferences when offline
  Future _loadCachedDataLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rooms = jsonDecode(prefs.getString(_cacheRoomsKey) ?? '[]') as List;
      final setup = jsonDecode(prefs.getString(_cacheSetupKey) ?? '[]') as List;
      final members = jsonDecode(prefs.getString(_cacheMembersKey) ?? '[]') as List;
      final payments = jsonDecode(prefs.getString(_cachePaymentsKey) ?? '[]') as List;
      return {
        'rooms': rooms,
        'setup': setup,
        'members': members,
        'payments': payments,
      };
    } catch (e) {
      debugPrint("Error reading local cache: $e");
      return {'rooms': [], 'setup': [], 'members': [], 'payments': []};
    }
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) {
        if (mounted) {
          setState(() {
            _rooms = [];
            _members = [];
            _totalConfiguredRooms = 0;
            _totalPaidAll = 0;
            _currentMonthPaid = 0;
            _totalDue = 0;
            _isLoading = false;
          });
        }
        return;
      }

      List roomsResponse = [];
      List setupResponse = [];
      List membersResponse = [];
      List paymentsResponse = [];

      try {
        final results = await Future.wait([
          _supabase
              .from('mess_rooms')
              .select('*')
              .eq('owner_id', currentUserId)
              .order('created_at', ascending: true),
          _supabase
              .from('mess_setup')
              .select('*')
              .eq('owner_id', currentUserId),
          _supabase
              .from('mess_members')
              .select('*')
              .eq('owner_id', currentUserId)
              .order('name', ascending: true),
          _supabase
              .from('mess_member_payments')
              .select('member_id, month_year, total_paid, rent_amount, electricity_bill, created_at, payment_date')
              .eq('owner_id', currentUserId),
        ]);

        roomsResponse = results[0] as List;
        setupResponse = results[1] as List;
        membersResponse = results[2] as List;
        paymentsResponse = results[3] as List;

        await _cacheDataLocally(
          rooms: roomsResponse,
          setup: setupResponse,
          members: membersResponse,
          payments: paymentsResponse,
        );

        if (mounted) setState(() => _isOfflineMode = false);
      } catch (e) {
        debugPrint("Error fetching dashboard data (falling back to cache): $e");

        final cachedData = await _loadCachedDataLocally();
        roomsResponse = cachedData['rooms'] ?? [];
        setupResponse = cachedData['setup'] ?? [];
        membersResponse = cachedData['members'] ?? [];
        paymentsResponse = cachedData['payments'] ?? [];

        final errorMessage = e.toString().toLowerCase();
        final bool isOffline = errorMessage.contains('socketexception') ||
            errorMessage.contains('failed host lookup') ||
            errorMessage.contains('clientexception');

        if (mounted) {
          setState(() {
            _isOfflineMode = true;
          });

          if (!isOffline) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to load dashboard data: $e')),
            );
          }
        }
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

      // --- CALCULATIONS ---
      int configuredRoomsSum = 0;
      double setupElectricityBillShare = 0;

      for (var row in setupResponse) {
        configuredRoomsSum += (row['total_rooms'] as num?)?.toInt() ?? 0;
        setupElectricityBillShare += (row['monthly_electricity_bill'] as num?)?.toDouble() ?? 0;
      }

      double allTimePayments = 0;
      double currentMonthPayments = 0;
      final now = DateTime.now();

      for (var p in paymentsResponse) {
        final totalPaid = (p['total_paid'] as num?)?.toDouble() ??
            (((p['rent_amount'] as num?)?.toDouble() ?? 0) +
                ((p['electricity_bill'] as num?)?.toDouble() ?? 0));

        allTimePayments += totalPaid;

        final dateStr = p['payment_date'] ?? p['created_at'];
        if (dateStr != null) {
          final paymentDate = DateTime.tryParse(dateStr.toString());
          if (paymentDate != null &&
              paymentDate.year == now.year &&
              paymentDate.month == now.month) {
            currentMonthPayments += totalPaid;
          }
        }
      }

      // --- CURRENT MONTH TOTAL DUE (RENT & UTILITIES ONLY) ---
      double calculatedDue = 0;
      for (var member in membersResponse) {
        final memberId = member['id']?.toString().trim();
        final double profileDue = (member['due'] as num?)?.toDouble() ?? 0;
        final double expectedRent = (member['room_rent'] as num?)?.toDouble() ?? 0;

        final double totalExpectedThisMonth = expectedRent + setupElectricityBillShare;
        double memberPaidThisMonth = 0.0;

        for (var p in paymentsResponse) {
          final paymentMemberId = p['member_id']?.toString().trim();

          if (paymentMemberId != null && paymentMemberId == memberId) {
            final rawDate = p['payment_date'] ?? p['created_at'];
            final monthYearStr = (p['month_year'] ?? '').toString().toLowerCase().trim();
            bool isThisMonth = false;

            if (rawDate != null) {
              final parsedDate = DateTime.tryParse(rawDate.toString());
              if (parsedDate != null && parsedDate.year == now.year && parsedDate.month == now.month) {
                isThisMonth = true;
              }
            }

            if (!isThisMonth && monthYearStr.isNotEmpty) {
              final currentMonthName = _getMonthName(now.month).toLowerCase();
              final currentShortName = _getShortMonthName(now.month).toLowerCase();
              final currentYearStr = now.year.toString();

              if (monthYearStr.contains(currentYearStr) &&
                  (monthYearStr.contains(now.month.toString()) ||
                      monthYearStr.contains(currentMonthName) ||
                      monthYearStr.contains(currentShortName))) {
                isThisMonth = true;
              }
            }

            if (isThisMonth) {
              final pTotal = (p['total_paid'] as num?)?.toDouble() ??
                  (((p['rent_amount'] as num?)?.toDouble() ?? 0) +
                      ((p['electricity_bill'] as num?)?.toDouble() ?? 0));
              memberPaidThisMonth += pTotal;
            }
          }
        }

        double unpaidThisMonth = totalExpectedThisMonth > 0
            ? (totalExpectedThisMonth - memberPaidThisMonth).clamp(0.0, double.infinity)
            : 0.0;

        double memberTotalDue = profileDue + unpaidThisMonth;
        calculatedDue += memberTotalDue;
      }

      debugPrint("FINAL CALCULATED TOTAL DUE: $calculatedDue");

      if (mounted) {
        setState(() {
          _rooms = List.from(roomsResponse);
          _members = List.from(membersResponse);
          _totalConfiguredRooms = configuredRoomsSum;
          _totalPaidAll = allTimePayments;
          _currentMonthPaid = currentMonthPayments;
          _totalDue = calculatedDue;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error in dashboard initialization: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Returns clean round figure numbers
  String _formatCurrency(double amount) {
    return '${amount.round()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'MESS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
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
            if (_isAdmin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Text(
                  'ADMIN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Menu',
            onPressed: () {
              showGeneralDialog(
                context: context,
                barrierDismissible: true,
                barrierLabel: 'Menu',
                barrierColor: Colors.black54.withOpacity(0.3),
                transitionDuration: const Duration(milliseconds: 200),
                pageBuilder: (context, animation, secondaryAnimation) {
                  return const SizedBox.shrink();
                },
                transitionBuilder: (context, animation, secondaryAnimation, child) {
                  return ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                    alignment: Alignment.topRight,
                    child: FadeTransition(
                      opacity: animation,
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(color: Colors.transparent),
                          ),
                          Positioned(
                            top: 56,
                            right: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: 310,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const ManageYourThreeDotPanel(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
        onRefresh: _fetchDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildStatsGrid(),
            const SizedBox(height: 24),
            ManageMessCard(
              onMemberAdded: _fetchDashboardData,
              ownerId: _supabase.auth.currentUser?.id,
              ownerEmail: _supabase.auth.currentUser?.email,
            ),
            const SizedBox(height: 16),
            ManageMealCard(
              onMealUpdated: _fetchDashboardData,
              ownerId: _supabase.auth.currentUser?.id,
              ownerEmail: _supabase.auth.currentUser?.email,
            ),
            const SizedBox(height: 80),
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

  Widget _buildStatsGrid() {
    final int targetTotal =
    _totalConfiguredRooms > 0 ? _totalConfiguredRooms : _rooms.length;

    final Set<String> occupiedRoomNumbers = {};
    for (var member in _members) {
      final roomNo = member['occupied_rooms']?.toString().trim();
      if (roomNo != null && roomNo.isNotEmpty) {
        occupiedRoomNumbers.add(roomNo);
      }
    }
    final int occupiedRoomsCount = occupiedRoomNumbers.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statBox(
                context,
                icon: Icons.calendar_month,
                label: 'Monthly Total Paid',
                value: _formatCurrency(_currentMonthPaid),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statBox(
                context,
                icon: Icons.meeting_room_outlined,
                label: 'Rooms Occupied',
                value: '$occupiedRoomsCount / $targetTotal',
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statBox(
                context,
                icon: Icons.account_balance_wallet,
                label: 'Total Paid (All-Time)',
                value: _formatCurrency(_totalPaidAll),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statBox(
                context,
                icon: Icons.money_off,
                label: 'Current Total Dues',
                value: _formatCurrency(_totalDue),
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}