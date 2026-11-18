import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/3dotPanel/view_mess_details.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessOwnerList extends StatefulWidget {
  const MessOwnerList({super.key});

  @override
  State<MessOwnerList> createState() => _MessOwnerControlState();
}

class _MessOwnerControlState extends State<MessOwnerList> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isOfflineMode = false;
  List _messList = [];
  List _filteredMessList = [];
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();

  // Local cache key
  static const String _cacheMessListKey = 'offline_cache_mess_owner_list';

  @override
  void initState() {
    super.initState();
    _fetchAllMesses();
    _searchController.addListener(_filterMesses);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Save mess list locally to SharedPreferences
  Future<void> _cacheMessListLocally(List list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheMessListKey, jsonEncode(list));
  }

  /// Load cached mess list locally when offline
  Future<List> _loadCachedMessListLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cached = prefs.getString(_cacheMessListKey);
      if (cached != null) {
        return jsonDecode(cached) as List;
      }
    } catch (e) {
      debugPrint("Error reading local mess owner cache: $e");
    }
    return [];
  }

  Future<void> _fetchAllMesses() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      List responseList = [];

      try {
        // Attempt online fetch from Supabase
        final response = await _supabase
            .from('mess_setup')
            .select()
            .order('created_at', ascending: false);

        responseList = List.from(response);

        // Cache fresh data locally
        await _cacheMessListLocally(responseList);

        if (!mounted) return;
        setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Offline / Socket fallback
        debugPrint("🌐 Network offline. Loading mess owners from local cache... Error: $networkError");
        responseList = await _loadCachedMessListLocally();

        if (!mounted) return;
        setState(() => _isOfflineMode = true);
      }

      if (!mounted) return;
      setState(() {
        _messList = responseList;
        _filteredMessList = _messList;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterMesses() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredMessList = _messList;
      } else {
        _filteredMessList = _messList.where((mess) {
          final messName = (mess['mess_name'] ?? '').toString().toLowerCase();
          final address = (mess['address'] ?? '').toString().toLowerCase();
          final contactPhone = (mess['contact_phone'] ?? '').toString().toLowerCase();
          final ownerId = (mess['owner_id'] ?? '').toString().toLowerCase();

          return messName.contains(query) ||
              address.contains(query) ||
              contactPhone.contains(query) ||
              ownerId.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Mess Owner List',
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
          // Search Bar Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, address, or owner ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _errorMessage != null
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Error loading mess accounts:\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchAllMesses,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
                : _filteredMessList.isEmpty
                ? Center(
              child: Text(
                _searchController.text.isNotEmpty
                    ? 'No matching mess accounts found.'
                    : 'No mess accounts found.',
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
            )
                : RefreshIndicator(
              onRefresh: _fetchAllMesses,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                itemCount: _filteredMessList.length,
                itemBuilder: (context, index) {
                  final mess = _filteredMessList[index];
                  final messName = mess['mess_name'] ?? 'Unnamed Mess';
                  final address = mess['address'] ?? 'No Address';
                  final contactPhone = mess['contact_phone'] ?? 'N/A';
                  final createdAt = mess['created_at'] != null
                      ? mess['created_at'].toString().split('T').first
                      : 'N/A';

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.2),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ViewMessDetailsScreen(messData: mess),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.15),
                              child: Icon(
                                Icons.home_work_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    messName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          address,
                                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Phone: $contactPhone',
                                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Created: $createdAt',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios, size: 16),
                              color: Theme.of(context).colorScheme.primary,
                              tooltip: 'View Details',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ViewMessDetailsScreen(messData: mess),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
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