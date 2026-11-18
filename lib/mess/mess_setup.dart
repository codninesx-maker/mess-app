import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessSetupScreen extends StatefulWidget {
  const MessSetupScreen({super.key});

  @override
  State<MessSetupScreen> createState() => _MessSetupScreenState();
}

class _MessSetupScreenState extends State<MessSetupScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _messNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _totalFloorsController = TextEditingController();
  final _totalRoomsController = TextEditingController();
  final _advanceAmountController = TextEditingController();
  final _roomRentController = TextEditingController(); // Unified controller for room rent
  final _rulesController = TextEditingController();

  final Map<int, TextEditingController> _floorRoomCountControllers = {};
  final Map<int, TextEditingController> _floorRangeControllers = {};

  bool _isLoading = false;
  bool _isFetchingInitialData = true;
  bool _isOfflineMode = false;
  String? _existingConfigId;

  // Local Cache Keys
  static const String _cacheSetupKey = 'offline_cache_mess_setup_data';
  static const String _cacheRoomsKey = 'offline_cache_mess_setup_rooms';

  @override
  void initState() {
    super.initState();
    _fetchExistingSetup().then((_) {
      _totalFloorsController.addListener(_rebuildFloorBreakdownControllers);
      _totalRoomsController.addListener(_rebuildFloorBreakdownControllers);
    });
  }

  @override
  void dispose() {
    _totalFloorsController.removeListener(_rebuildFloorBreakdownControllers);
    _totalRoomsController.removeListener(_rebuildFloorBreakdownControllers);

    _messNameController.dispose();
    _addressController.dispose();
    _contactPhoneController.dispose();
    _totalFloorsController.dispose();
    _totalRoomsController.dispose();
    _advanceAmountController.dispose();
    _roomRentController.dispose(); // Properly disposed only once in dispose()
    _rulesController.dispose();

    for (var c in _floorRoomCountControllers.values) {
      c.dispose();
    }
    for (var c in _floorRangeControllers.values) {
      c.dispose();
    }

    super.dispose();
  }

  Future<void> _cacheDataLocally(Map<String, dynamic>? setup, List rooms) async {
    final prefs = await SharedPreferences.getInstance();
    if (setup != null) {
      await prefs.setString(_cacheSetupKey, jsonEncode(setup));
    }
    await prefs.setString(_cacheRoomsKey, jsonEncode(rooms));
  }

  Future? _loadCachedSetupLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final setupStr = prefs.getString(_cacheSetupKey);
      if (setupStr != null) {
        return jsonDecode(setupStr) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error reading local setup cache: $e");
    }
    return null;
  }

  Future<List> _loadCachedRoomsLocally() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final roomsStr = prefs.getString(_cacheRoomsKey);
      if (roomsStr != null) {
        return jsonDecode(roomsStr) as List;
      }
    } catch (e) {
      debugPrint("Error reading local rooms cache: $e");
    }
    return [];
  }

  List<String> _generateAllMessRooms(int totalFloors, int totalRooms) {
    List<String> allRooms = [];
    if (totalFloors <= 0 || totalRooms <= 0) return allRooms;

    int roomsPerFloor = (totalRooms / totalFloors).ceil();
    if (roomsPerFloor <= 0) roomsPerFloor = 9;

    for (int floor = 1; floor <= totalFloors; floor++) {
      for (int seq = 1; seq <= roomsPerFloor; seq++) {
        if (allRooms.length >= totalRooms) break;
        String roomNo = "$floor${seq.toString().padLeft(2, '0')}";
        allRooms.add(roomNo);
      }
    }
    return allRooms;
  }

  void _buildDefaultControllers(int floors, int rooms) {
    final generatedRooms = _generateAllMessRooms(floors, rooms);
    final Map<int, List<String>> floorGroups = {};
    for (String r in generatedRooms) {
      int floorNum = int.tryParse(r[0]) ?? 1;
      floorGroups.putIfAbsent(floorNum, () => []).add(r);
    }

    for (int f = 1; f <= floors; f++) {
      final floorRooms = floorGroups[f] ?? [];
      final defaultCount = floorRooms.length.toString();
      final defaultRange = floorRooms.isNotEmpty
          ? (floorRooms.length == 1 ? floorRooms.first : '${floorRooms.first}-${floorRooms.last}')
          : 'N/A';

      if (!_floorRoomCountControllers.containsKey(f)) {
        _floorRoomCountControllers[f] = TextEditingController(text: defaultCount);
      } else if (_floorRoomCountControllers[f]!.text.isEmpty) {
        _floorRoomCountControllers[f]!.text = defaultCount;
      }

      if (!_floorRangeControllers.containsKey(f)) {
        _floorRangeControllers[f] = TextEditingController(text: defaultRange);
      }
    }
  }

  void _rebuildFloorBreakdownControllers() {
    final int floors = int.tryParse(_totalFloorsController.text.trim()) ?? 0;
    final int rooms = int.tryParse(_totalRoomsController.text.trim()) ?? 0;

    if (floors <= 0 || rooms <= 0) {
      if (mounted) setState(() {});
      return;
    }

    _buildDefaultControllers(floors, rooms);

    _floorRoomCountControllers.removeWhere((key, value) => key > floors);
    _floorRangeControllers.removeWhere((key, value) => key > floors);

    if (mounted) setState(() {});
  }

  List _generateCustomFloorRooms(int totalFloors, String currentUserId) {
    List allGeneratedRooms = [];

    for (int floorNum = 1; floorNum <= totalFloors; floorNum++) {
      final rangeText = _floorRangeControllers[floorNum]?.text.trim() ?? '';
      final countText = _floorRoomCountControllers[floorNum]?.text.trim() ?? '';
      int roomCount = int.tryParse(countText) ?? 0;

      List<String> floorRoomNumbers = [];

      // 1. Parse custom ranges or comma-separated labels (e.g., "501-513" or "201, 202, 205")
      if (rangeText.isNotEmpty && rangeText != 'N/A') {
        if (rangeText.contains('-')) {
          final parts = rangeText.split('-');
          if (parts.length == 2) {
            final start = int.tryParse(parts[0].trim());
            final end = int.tryParse(parts[1].trim());
            if (start != null && end != null && end >= start) {
              for (int r = start; r <= end; r++) {
                floorRoomNumbers.add(r.toString());
              }
            }
          }
        } else if (rangeText.contains(',')) {
          floorRoomNumbers = rangeText
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        } else {
          floorRoomNumbers.add(rangeText);
        }
      }

      // 2. Fallback to sequential generation if no valid range string was provided
      if (floorRoomNumbers.isEmpty && roomCount > 0) {
        for (int seq = 1; seq <= roomCount; seq++) {
          floorRoomNumbers.add("$floorNum${seq.toString().padLeft(2, '0')}");
        }
      }

      // 3. Build database records for insertion
      for (String roomNo in floorRoomNumbers) {
        allGeneratedRooms.add({
          'owner_id': currentUserId,
          'occupied_rooms': roomNo,
          'empty_rooms': roomNo,
          'floor': floorNum,
          'room_type': 'double',
        });
      }
    }
    return allGeneratedRooms;
  }

  String _getFloorOrdinal(int f) {
    if (f == 1) return '1st Floor';
    if (f == 2) return '2nd Floor';
    if (f == 3) return '3rd Floor';
    return '${f}th Floor';
  }

  Future<void> _fetchExistingSetup() async {
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) {
        if (mounted) setState(() => _isFetchingInitialData = false);
        return;
      }

      Map<String, dynamic>? setupResponse;
      List roomsResponse = [];

      try {
        setupResponse = await _supabase
            .from('mess_setup')
            .select('*')
            .eq('owner_id', currentUserId)
            .limit(1)
            .maybeSingle();

        roomsResponse = await _supabase
            .from('mess_rooms')
            .select('*')
            .eq('owner_id', currentUserId)
            .order('floor', ascending: true);

        await _cacheDataLocally(setupResponse, roomsResponse);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint("🌐 Network offline. Loading setup from local cache safely... Error: $networkError");
        setupResponse = await _loadCachedSetupLocally();
        roomsResponse = await _loadCachedRoomsLocally();
        if (mounted) setState(() => _isOfflineMode = true);
      }

      if (setupResponse != null && mounted) {
        setState(() {
          _existingConfigId = setupResponse?['id']?.toString();
          _messNameController.text = setupResponse?['mess_name'] ?? '';
          _addressController.text = setupResponse?['address'] ?? '';
          _contactPhoneController.text = setupResponse?['contact_phone'] ?? '';
          _totalFloorsController.text = setupResponse?['total_floors']?.toString() ?? '1';
          _totalRoomsController.text = setupResponse?['total_rooms']?.toString() ?? '1';
          _roomRentController.text = (setupResponse?['rent_per_room'] ?? setupResponse?['room_rent'])?.toString() ?? '0.0';
          _advanceAmountController.text = setupResponse?['advance_amount']?.toString() ?? '0.0';
          _rulesController.text = setupResponse?['rules'] ?? '';
        });
      }

      if (roomsResponse.isNotEmpty) {
        final Map<int, List<String>> floorRoomsMap = {};
        for (var row in roomsResponse) {
          int floor = row['floor'] ?? 1;
          String roomNo = row['occupied_rooms'] ?? row['empty_rooms'] ?? '';
          if (roomNo.isNotEmpty) {
            floorRoomsMap.putIfAbsent(floor, () => []).add(roomNo);
          }
        }

        floorRoomsMap.forEach((floor, rooms) {
          rooms.sort();
          _floorRoomCountControllers[floor] = TextEditingController(text: rooms.length.toString());
          String rangeText = rooms.length == 1 ? rooms.first : '${rooms.first}-${rooms.last}';
          _floorRangeControllers[floor] = TextEditingController(text: rangeText);
        });
      } else {
        int floors = int.tryParse(_totalFloorsController.text.trim()) ?? 1;
        int rooms = int.tryParse(_totalRoomsController.text.trim()) ?? 1;
        _buildDefaultControllers(floors, rooms);
      }
    } catch (e) {
      debugPrint("Quietly handled setup initialization error: $e");
      int floors = int.tryParse(_totalFloorsController.text.trim()) ?? 1;
      int rooms = int.tryParse(_totalRoomsController.text.trim()) ?? 1;
      _buildDefaultControllers(floors, rooms);
    } finally {
      if (mounted) {
        setState(() => _isFetchingInitialData = false);
      }
    }
  }

  Future<void> _saveMessSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) throw 'User not authenticated.';

      final totalRooms = int.tryParse(_totalRoomsController.text.trim()) ?? 1;
      final totalFloors = int.tryParse(_totalFloorsController.text.trim()) ?? 1;

      final payload = {
        'owner_id': currentUserId,
        'mess_name': _messNameController.text.trim(),
        'address': _addressController.text.trim(),
        'contact_phone': _contactPhoneController.text.trim(),
        'total_floors': totalFloors,
        'total_rooms': totalRooms,
        'rent_per_room': double.tryParse(_roomRentController.text.trim()) ?? 0.0,
        'advance_amount': double.tryParse(_advanceAmountController.text.trim()) ?? 0.0,
        'rules': _rulesController.text.trim(),
      };

      final customRooms = _generateCustomFloorRooms(totalFloors, currentUserId);

      try {
        if (_existingConfigId != null) {
          await _supabase
              .from('mess_setup')
              .update(payload)
              .eq('id', _existingConfigId!)
              .eq('owner_id', currentUserId);
        } else {
          final inserted = await _supabase
              .from('mess_setup')
              .insert(payload)
              .select()
              .single();
          _existingConfigId = inserted['id']?.toString();
        }

        if (customRooms.isNotEmpty) {
          await _supabase
              .from('mess_rooms')
              .delete()
              .eq('owner_id', currentUserId);

          for (var roomData in customRooms) {
            await _supabase.from('mess_rooms').insert(roomData);
          }
        }
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint("🌐 Network offline while saving setup. Saving locally... Error: $networkError");
        if (mounted) setState(() => _isOfflineMode = true);
      }

      await _cacheDataLocally(payload, customRooms);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineMode
                  ? 'Offline mode: Mess setup saved locally!'
                  : 'Mess setup and floor mappings saved successfully!',
            ),
            backgroundColor: _isOfflineMode ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Failed to save setup: $e");
      final errorMessage = e.toString().toLowerCase();
      final bool isOffline = errorMessage.contains('socketexception') ||
          errorMessage.contains('failed host lookup') ||
          errorMessage.contains('clientexception');
      if (mounted && !isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setup: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final int floors = int.tryParse(_totalFloorsController.text.trim()) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Mess Setup',
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
      body: _isFetchingInitialData
          ? const Center(child: CircularProgressIndicator.adaptive())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _messNameController,
                decoration: const InputDecoration(
                  labelText: 'Mess / Hostel Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter mess name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address / Location',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Manager Contact Phone',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalFloorsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total Floors',
                        hintText: 'e.g. 6',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.layers),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter floors' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalRoomsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total Rooms',
                        hintText: 'e.g. 47',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.meeting_room),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter rooms' : null,
                    ),
                  ),
                ],
              ),
              if (floors > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Edit Floor Breakdown & Room Ranges',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: floors,
                        itemBuilder: (context, index) {
                          final int floorNum = index + 1;

                          _floorRoomCountControllers.putIfAbsent(
                            floorNum,
                                () => TextEditingController(text: ''),
                          );
                          _floorRangeControllers.putIfAbsent(
                            floorNum,
                                () => TextEditingController(text: ''),
                          );

                          final countController = _floorRoomCountControllers[floorNum];
                          final rangeController = _floorRangeControllers[floorNum];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 75,
                                  child: Text(
                                    _getFloorOrdinal(floorNum),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: TextFormField(
                                    controller: countController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Rooms',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: rangeController,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Range / Label',
                                      hintText: 'e.g. 501-513',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Row for Advance Deposit and Room Rent on the same line
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _advanceAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Advance Deposit',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance_wallet),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roomRentController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Room Rent',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home_outlined),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _rulesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Remarks',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.assignment),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              SafeArea(
                top: false,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveMessSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                        : const Text(
                      'Save Setup Configuration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}