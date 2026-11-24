import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditMessSetupScreen extends StatefulWidget {
  final String? messId;
  final bool createNew;
  final Map<String, dynamic> initialSetup;

  const EditMessSetupScreen({super.key, required this.initialSetup, this.messId,
    this.createNew = false,});

  @override
  State<EditMessSetupScreen> createState() => _EditMessSetupScreenState();
}

class _EditMessSetupScreenState extends State<EditMessSetupScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _messNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _totalFloorsController;
  late final TextEditingController _totalRoomsController;
  late final TextEditingController _rentPerRoomController;
  late final TextEditingController _advanceAmountController;
  late final TextEditingController _remarksController;
  late final TextEditingController _roomRentController; // Fixed: Now declared as late final

  final Map<int, TextEditingController> _floorRoomCountControllers = {};
  final Map<int, TextEditingController> _floorRangeControllers = {};

  bool _isLoading = false;
  bool _isFetchingRooms = true;
  bool _isOfflineMode = false;

  // Section-wise edit toggle flags
  bool _isEditingBasic = false;
  bool _isEditingFloors = false;
  bool _isEditingFinancials = false;

  // Local Cache Keys
  static const String _cacheSetupKey = 'offline_cache_mess_setup_data';
  static const String _cacheRoomsKey = 'offline_cache_mess_setup_rooms';
  String? get _effectiveMessId {
    final raw = widget.messId ?? widget.initialSetup['id']?.toString();
    final trimmed = raw?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  String _setupCacheKeyFor(String scopeKey) => 'offline_cache_mess_setup_data_$scopeKey';
  String _roomsCacheKeyFor(String scopeKey) => 'offline_cache_mess_setup_rooms_$scopeKey';

  @override
  void initState() {
    super.initState();
    final s = widget.initialSetup;
    _messNameController = TextEditingController(text: s['mess_name'] ?? '');
    _addressController = TextEditingController(text: s['address'] ?? '');
    _contactPhoneController = TextEditingController(text: s['contact_phone'] ?? '');
    _totalFloorsController = TextEditingController(text: s['total_floors']?.toString() ?? '1');
    _totalRoomsController = TextEditingController(text: s['total_rooms']?.toString() ?? '1');
    _rentPerRoomController = TextEditingController(text: s['rent_per_room']?.toString() ?? '0.0');
    _advanceAmountController = TextEditingController(text: s['advance_amount']?.toString() ?? '0.0');
    _remarksController = TextEditingController(text: s['remarks'] ?? '');

    // Fixed: Initialized _roomRentController properly using s['rent_per_room'] or default value
    _roomRentController = TextEditingController(text: s['rent_per_room']?.toString() ?? '0.0');

    _fetchExistingRooms();

    _totalFloorsController.addListener(_rebuildFloorBreakdownControllers);
    _totalRoomsController.addListener(_rebuildFloorBreakdownControllers);
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
    _rentPerRoomController.dispose();
    _advanceAmountController.dispose();
    _remarksController.dispose();
    _roomRentController.dispose(); // Fixed: Disposed properly here

    for (var c in _floorRoomCountControllers.values) c.dispose();
    for (var c in _floorRangeControllers.values) c.dispose();

    super.dispose();
  }

  Future<void> _cacheRoomsLocally(String scopeKey, List rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomsCacheKeyFor(scopeKey), jsonEncode(rooms));
  }

  Future<List> _loadCachedRoomsLocally(String scopeKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final roomsStr = prefs.getString(_roomsCacheKeyFor(scopeKey));
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

  List _generateCustomFloorRooms(
      int totalFloors,
      String currentUserId,
      String? messId,
      Set<String> occupiedRoomNumbers,
      ) {
    final List allGeneratedRooms = [];
    for (int floorNum = 1; floorNum <= totalFloors; floorNum++) {
      final countController = _floorRoomCountControllers[floorNum];
      final inputText = (countController?.text ?? '').trim();
      if (inputText.isEmpty) continue;

      final int roomCount = int.tryParse(inputText) ?? 0;
      if (roomCount <= 0) continue;

      for (int seq = 1; seq <= roomCount; seq++) {
        final String roomNo = "$floorNum${seq.toString().padLeft(2, '0')}";
        final bool isOccupied = occupiedRoomNumbers.contains(roomNo);
        allGeneratedRooms.add({
          'owner_id': currentUserId,
          if (messId != null && messId.isNotEmpty) 'mess_id': messId,
          'occupied_rooms': roomNo,
          'empty_rooms': isOccupied ? null : roomNo,
          'is_occupied': isOccupied,
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

  Future<void> _fetchExistingRooms() async {
    if (widget.createNew) {
      _messNameController.clear();
      _addressController.clear();
      _contactPhoneController.clear();
      _totalFloorsController.clear();
      _totalRoomsController.clear();
      _rentPerRoomController.clear();
      _advanceAmountController.clear();
      _roomRentController.clear();
      _remarksController.clear();

      for (final c in _floorRoomCountControllers.values) {
        c.dispose();
      }
      for (final c in _floorRangeControllers.values) {
        c.dispose();
      }
      _floorRoomCountControllers.clear();
      _floorRangeControllers.clear();

      if (mounted) {
        setState(() {
          _isOfflineMode = false;
          _isFetchingRooms = false;
        });
      }
      return;
    }
    try {
      final user = _supabase.auth.currentUser;
      final currentUserId = user?.id;
      if (currentUserId == null) {
        if (mounted) setState(() => _isFetchingRooms = false);
        return;
      }

      List roomsResponse = [];

      final messId = _effectiveMessId;
      final cacheScopeKey = messId ?? 'owner_$currentUserId';

      try {
        var query = _supabase.from('mess_rooms').select('*');
        if (messId != null) {
          query = query.eq('mess_id', messId);
        } else {
          query = query.eq('owner_id', currentUserId);
        }
        roomsResponse = await query.order('floor', ascending: true);

        await _cacheRoomsLocally(cacheScopeKey, roomsResponse);
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint("🌐 Network offline. Loading rooms from local cache... Error: $networkError");
        roomsResponse = await _loadCachedRoomsLocally(cacheScopeKey);
        if (mounted) setState(() => _isOfflineMode = true);
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
      debugPrint("Quietly handled room fetch error: $e");
      int floors = int.tryParse(_totalFloorsController.text.trim()) ?? 1;
      int rooms = int.tryParse(_totalRoomsController.text.trim()) ?? 1;
      _buildDefaultControllers(floors, rooms);
    } finally {
      if (mounted) {
        setState(() => _isFetchingRooms = false);
      }
    }
  }

  Future<void> _updateMessSetup() async {
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
        'remarks': _remarksController.text.trim(),
      };

      final String? configId =
      (widget.messId ?? widget.initialSetup['id'])?.toString().trim();
      if (configId == null || configId.isEmpty) {
        throw 'Mess setup ID not found.';
      }

      List customRooms = [];

      try {
        await _supabase
            .from('mess_setup')
            .update(payload)
            .eq('id', configId)
            .eq('owner_id', currentUserId);

        // Only recreate rooms for THIS mess when floor/room layout was edited
        if (_isEditingFloors) {
          final membersRows = await _supabase
              .from('mess_members')
              .select('occupied_rooms')
              .eq('mess_id', configId)
              .not('occupied_rooms', 'is', null);

          final Set<String> occupiedRoomNumbers = (membersRows as List)
              .map((m) => m['occupied_rooms']?.toString().trim() ?? '')
              .where((r) => r.isNotEmpty)
              .toSet();

          customRooms = _generateCustomFloorRooms(
            totalFloors,
            currentUserId,
            configId,
            occupiedRoomNumbers,
          );

          if (customRooms.isNotEmpty) {
            await _supabase
                .from('mess_rooms')
                .delete()
                .eq('mess_id', configId);

            await _supabase.from('mess_rooms').insert(customRooms);
          }
        }

        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        debugPrint(
          "🌐 Network offline while updating setup. Saving locally... Error: $networkError",
        );
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Scope local cache by configId (mess_id)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_cacheSetupKey}_$configId',
        jsonEncode({...widget.initialSetup, ...payload}),
      );
      if (customRooms.isNotEmpty) {
        await prefs.setString(
          '${_cacheRoomsKey}_$configId',
          jsonEncode(customRooms),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineMode
                  ? 'Offline mode: Mess setup updated locally!'
                  : 'Mess setup updated successfully!',
            ),
            backgroundColor: _isOfflineMode ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Failed to update setup: $e");
      final errorMessage = e.toString().toLowerCase();
      final bool isOffline = errorMessage.contains('socketexception') ||
          errorMessage.contains('failed host lookup') ||
          errorMessage.contains('clientexception');
      if (mounted && !isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setup: $e')),
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
              'Edit Mess Setup',
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
      body: _isFetchingRooms
          ? const Center(child: CircularProgressIndicator.adaptive())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- SECTION 1: BASIC INFO ---
              _buildSectionHeaderWithToggle(
                title: 'Basic Information',
                icon: Icons.business,
                isEditing: _isEditingBasic,
                onToggle: () => setState(() => _isEditingBasic = !_isEditingBasic),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messNameController,
                readOnly: !_isEditingBasic,
                style: TextStyle(
                  color: _isEditingBasic ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Mess / Hostel Name',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingBasic ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.business,
                    color: _isEditingBasic ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingBasic ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter mess name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                readOnly: !_isEditingBasic,
                style: TextStyle(
                  color: _isEditingBasic ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Address / Location',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingBasic ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.location_on,
                    color: _isEditingBasic ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingBasic ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                readOnly: !_isEditingBasic,
                style: TextStyle(
                  color: _isEditingBasic ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Manager Contact Phone',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingBasic ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.phone,
                    color: _isEditingBasic ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingBasic ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              // --- SECTION 2: FLOORS & ROOMS ---
              _buildSectionHeaderWithToggle(
                title: 'Floors & Room Layout',
                icon: Icons.layers,
                isEditing: _isEditingFloors,
                onToggle: () => setState(() => _isEditingFloors = !_isEditingFloors),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalFloorsController,
                      keyboardType: TextInputType.number,
                      readOnly: !_isEditingFloors,
                      style: TextStyle(
                        color: _isEditingFloors ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Floors',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFloors ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.layers,
                          color: _isEditingFloors ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFloors ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter floors' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalRoomsController,
                      keyboardType: TextInputType.number,
                      readOnly: !_isEditingFloors,
                      style: TextStyle(
                        color: _isEditingFloors ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Rooms',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFloors ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.meeting_room,
                          color: _isEditingFloors ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFloors ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
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
                        'Floor Breakdown & Room Ranges',
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
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: TextFormField(
                                    controller: countController,
                                    keyboardType: TextInputType.number,
                                    readOnly: !_isEditingFloors,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _isEditingFloors ? Colors.black87 : Colors.grey[700],
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Rooms',
                                      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: const OutlineInputBorder(),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: _isEditingFloors ? Colors.grey[400]! : Colors.grey[300]!,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: !_isEditingFloors ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: rangeController,
                                    readOnly: !_isEditingFloors,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _isEditingFloors ? Colors.black87 : Colors.grey[700],
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Range / Label',
                                      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 11),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: const OutlineInputBorder(),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                          color: _isEditingFloors ? Colors.grey[400]! : Colors.grey[300]!,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: !_isEditingFloors ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
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

              // --- SECTION 3: FINANCIALS ---
              _buildSectionHeaderWithToggle(
                title: 'Financials',
                icon: Icons.payments,
                isEditing: _isEditingFinancials,
                onToggle: () => setState(() => _isEditingFinancials = !_isEditingFinancials),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _advanceAmountController,
                      readOnly: !_isEditingFinancials,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        color: _isEditingFinancials ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Advance Deposit',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFinancials ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.account_balance_wallet,
                          color: _isEditingFinancials ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFinancials ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roomRentController,
                      readOnly: !_isEditingFinancials,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        color: _isEditingFinancials ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Room Rent',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFinancials ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.home_outlined,
                          color: _isEditingFinancials ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFinancials ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _remarksController,
                maxLines: 2,
                readOnly: !_isEditingFinancials,
                style: TextStyle(
                  color: _isEditingFinancials ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Remarks',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingFinancials ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.note,
                    color: _isEditingFinancials ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingFinancials ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              SafeArea(
                top: false,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateMessSetup,
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
                      'Update Mess Setup',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Widget _buildSectionHeaderWithToggle({
    required String title,
    required IconData icon,
    required bool isEditing,
    required VoidCallback onToggle,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        IconButton(
          icon: Icon(
            isEditing ? Icons.check_circle : Icons.edit,
            color: isEditing ? Colors.green : Colors.blue,
            size: 20,
          ),
          tooltip: isEditing ? 'Done Editing' : 'Edit $title',
          onPressed: onToggle,
        ),
      ],
    );
  }
}