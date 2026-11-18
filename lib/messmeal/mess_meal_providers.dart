import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MealProviderScreen extends StatefulWidget {
  const MealProviderScreen({super.key});

  @override
  State<MealProviderScreen> createState() => _MealProviderScreenState();
}

class _MealProviderScreenState extends State<MealProviderScreen> {
  final _supabase = Supabase.instance.client;

  List _providers = [];
  List _filteredProviders = [];
  bool _isLoading = true;
  bool _isOffline = false;

  final TextEditingController _searchController = TextEditingController();

  String? get _currentUserId => _supabase.auth.currentUser?.id;
  static const String _cacheKey = 'cached_all_meal_providers';

  @override
  void initState() {
    super.initState();
    _fetchProviders();
    _searchController.addListener(_filterProviders);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProviders() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredProviders = List.from(_providers);
      } else {
        _filteredProviders = _providers.where((provider) {
          final name = (provider['name'] ?? '').toString().toLowerCase();
          final phone = (provider['phone_number'] ?? '').toString().toLowerCase();
          final location = (provider['location'] ?? '').toString().toLowerCase();

          return name.contains(query) || phone.contains(query) || location.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _fetchProviders() async {
    setState(() => _isLoading = true);

    try {
      final response = await _supabase
          .from('mess_meal_providers')
          .select()
          .order('created_at', ascending: false);

      final fetched = List.from(response);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(fetched));

      if (mounted) {
        setState(() {
          _providers = fetched;
          _filterProviders(); // Apply search filter to newly fetched data
          _isOffline = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching meal providers: $e');
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
          _providers = List.from(decoded);
          _filterProviders();
          _isOffline = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _providers = [];
          _filteredProviders = [];
          _isOffline = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanNumber.isEmpty) return;

    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer for $phoneNumber')),
      );
    }
  }

  Future<void> _deleteProvider(Map<String, dynamic> provider) async {
    if (provider['owner_id'] != _currentUserId) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Provider'),
        content: Text('Remove "${provider['name']}" from meal providers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase
          .from('mess_meal_providers')
          .delete()
          .eq('id', provider['id'])
          .eq('owner_id', _currentUserId!);
      await _fetchProviders();
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _showAddEditProviderDialog({Map<String, dynamic>? existingProvider}) {
    final userId = _currentUserId;
    if (userId == null) return;

    if (existingProvider != null && existingProvider['owner_id'] != userId) {
      return;
    }

    final nameController =
    TextEditingController(text: existingProvider?['name'] ?? '');
    final phoneController =
    TextEditingController(text: existingProvider?['phone_number'] ?? '');
    final locationController =
    TextEditingController(text: existingProvider?['location'] ?? '');

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          existingProvider == null ? 'Add Meal Provider' : 'Edit Meal Provider',
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Provider Name',
                    hintText: 'e.g. Mayer Doa Catering',
                    prefixIcon: Icon(Icons.storefront_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Please enter provider name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact / Phone Number',
                    hintText: 'e.g. 017XXXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Please enter phone number'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: locationController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Location / Address',
                    hintText: 'e.g. Talaimari, Rajshahi',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Please enter location'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final payload = {
                'owner_id': userId,
                'name': nameController.text.trim(),
                'phone_number': phoneController.text.trim(),
                'location': locationController.text.trim(),
              };

              try {
                if (existingProvider == null) {
                  await _supabase.from('mess_meal_providers').insert(payload);
                } else {
                  await _supabase
                      .from('mess_meal_providers')
                      .update(payload)
                      .eq('id', existingProvider['id'])
                      .eq('owner_id', userId);
                }
                await _fetchProviders();
              } catch (e) {
                debugPrint('Offline save fallback: $e');
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  if (existingProvider == null) {
                    _providers.insert(0, {
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      ...payload,
                    });
                  } else {
                    final idx = _providers.indexWhere(
                            (p) => p['id'] == existingProvider['id']);
                    if (idx != -1) {
                      _providers[idx] = {...existingProvider, ...payload};
                    }
                  }
                  _filterProviders();
                  _isOffline = true;
                });
                await prefs.setString(_cacheKey, jsonEncode(_providers));
              }

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Meal Providers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        onPressed: () => _showAddEditProviderDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Provider'),
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Offline mode: Showing locally cached meal providers.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator(
              onRefresh: _fetchProviders,
              child: _filteredProviders.isEmpty
                  ? ListView(
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.search_off,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'No meal providers added yet'
                          : 'No matching providers found',
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 15),
                    ),
                  ),
                ],
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: _filteredProviders.length,
                separatorBuilder: (_, __) =>
                const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final provider = _filteredProviders[index];
                  final name = provider['name'] ?? 'N/A';
                  final phone = provider['phone_number'] ?? '';
                  final location = provider['location'] ?? 'N/A';
                  final bool isCreator =
                      provider['owner_id'] == _currentUserId;

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                Colors.orange.shade50,
                                child: const Icon(
                                  Icons.room_service,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isCreator)
                                PopupMenuButton<String>(
                                  onSelected: (val) {
                                    if (val == 'edit') {
                                      _showAddEditProviderDialog(
                                          existingProvider:
                                          provider);
                                    } else if (val == 'delete') {
                                      _deleteProvider(provider);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit,
                                              size: 18,
                                              color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete,
                                              size: 18,
                                              color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Delete',
                                              style: TextStyle(
                                                  color:
                                                  Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  location,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _makePhoneCall(phone),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call,
                                      size: 16,
                                      color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text(
                                    phone,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green,
                                      decoration:
                                      TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
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
}