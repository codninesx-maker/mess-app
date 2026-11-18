import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LogedInMembersList extends StatefulWidget {
  const LogedInMembersList({super.key});

  @override
  State<LogedInMembersList> createState() =>
      _LogedInMembersListState();
}

class _LogedInMembersListState extends State<LogedInMembersList> {
  final _supabase = Supabase.instance.client;
  static const String _cacheKey = 'cached_otp_logged_in_members';

  List _members = [];
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fixed: requested 'mobile_number' to match your mess_members table schema
      final response = await _supabase
          .from('mess_members')
          .select('id, name, email, mobile_number, login_method, last_sign_in_at')
          .eq('login_method', 'email_otp')
          .not('last_sign_in_at', 'is', null)
          .order('last_sign_in_at', ascending: false);

      final fetchedList = List.from(response);

      // Save to local cache for offline fallback
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(fetchedList));

      if (mounted) {
        setState(() {
          _members = fetchedList;
          _isOffline = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching OTP logged-in members: $e');
      await _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString(_cacheKey);

    if (cachedStr != null) {
      final decoded = jsonDecode(cachedStr) as List;
      if (mounted) {
        setState(() {
          _members = List.from(decoded);
          _isOffline = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isOffline = true;
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Unknown';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final date = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$date at $time';
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logged-In Members'),
      ),
      body: Column(
        children: [
          // Offline Status Banner
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline mode: Showing cached member login data.',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator(
              onRefresh: _loadMembers,
              child: _members.isEmpty
                  ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 150),
                  Icon(Icons.mark_email_read_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No members logged in via Email OTP yet.',
                      style: TextStyle(
                          fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ],
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _members.length,
                separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final name = member['name'] ?? 'Unnamed Member';
                  final email = member['email'] ?? 'No Email';
                  final phone = member['mobile_number'] ?? 'No Phone';
                  final lastLogin =
                  _formatDateTime(member['last_sign_in_at']);

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Text(
                          name.isNotEmpty
                              ? name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.email_outlined,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(phone,
                                  style: const TextStyle(
                                      fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Last OTP Login: $lastLogin',
                                style:
                                const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Chip(
                        label: const Text(
                          'OTP',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.green.shade100,
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}