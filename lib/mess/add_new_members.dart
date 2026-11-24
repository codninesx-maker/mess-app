import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddMembersScreen extends StatefulWidget {
  final String? messId;
  final String? initialRoomNo;
  final int? initialFloor;
  const AddMembersScreen({
    super.key,
    this.messId,
    this.initialRoomNo,
    this.initialFloor,
  });

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _parentsNameController = TextEditingController();
  final _occupationController = TextEditingController();
  final _homeTownController = TextEditingController();
  final _mobileController = TextEditingController();
  final _fatherMobileController = TextEditingController();
  final _roomRentController = TextEditingController();

  // Editable Floor & Room Controllers
  final _floorController = TextEditingController();
  final _roomNumberController = TextEditingController();

  final _entryDateController = TextEditingController();
  final _monthController = TextEditingController();
  final _advancePaidController = TextEditingController();
  final _dueController = TextEditingController();
  final _remarksController = TextEditingController();

  DateTime? _selectedEntryDate;
  bool _isLoading = false;
  bool _isOfflineMode = false;

  // Local Cache Keys
  static const String _cacheMembersKey = 'offline_cache_show_members_list';
  String _membersCacheKeyForMess(String? messId, String ownerId) {
    final scope = (messId != null && messId.isNotEmpty) ? messId : ownerId;
    return '${_cacheMembersKey}_$scope';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedEntryDate = now;
    _entryDateController.text = _formatDate(_selectedEntryDate!);

    _monthOptions = _buildMonthOptions(now);
    final defaultMonth = '${_monthNames[now.month - 1]} ${now.year}';
    _selectedMonth = _monthOptions.contains(defaultMonth)
        ? defaultMonth
        : _monthOptions.first;
    _monthController.text = _selectedMonth!;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _parentsNameController.dispose();
    _occupationController.dispose();
    _homeTownController.dispose();
    _mobileController.dispose();
    _fatherMobileController.dispose();
    _floorController.dispose();
    _roomNumberController.dispose();
    _entryDateController.dispose();
    _monthController.dispose();
    _advancePaidController.dispose();
    _dueController.dispose();
    _remarksController.dispose();
    _roomRentController.dispose();
    super.dispose();
  }

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late final List<String> _monthOptions;
  String? _selectedMonth;

  List<String> _buildMonthOptions(DateTime anchorDate) {
    final Set<String> uniqueMonths = {};
    for (final y in [anchorDate.year, anchorDate.year + 1]) {
      for (final m in _monthNames) {
        uniqueMonths.add('$m $y');
      }
    }
    return uniqueMonths.toList();
  }


  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _selectEntryDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedEntryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedEntryDate) {
      setState(() {
        _selectedEntryDate = picked;
        _entryDateController.text = _formatDate(picked);
      });
    }
  }

  // Helper to save new member locally into SharedPreferences cache when offline
  Future<void> _cacheNewMemberLocally(
      Map<String, dynamic> newMember, {
        String? messId,
        required String ownerId,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 1. Update general cached members list
      final cachedStr = prefs.getString(_cacheMembersKey);
      final List membersList =
      cachedStr != null ? List.from(jsonDecode(cachedStr) as List) : [];
      membersList.insert(0, newMember);
      await prefs.setString(_cacheMembersKey, jsonEncode(membersList));

      // 2. Also update mess-scoped cache if messId is known
      final scopedKey = _membersCacheKeyForMess(messId, ownerId);
      final scopedStr = prefs.getString(scopedKey);
      final List scopedList =
      scopedStr != null ? List.from(jsonDecode(scopedStr) as List) : [];
      scopedList.insert(0, newMember);
      await prefs.setString(scopedKey, jsonEncode(scopedList));
    } catch (e) {
      debugPrint("Error caching new member locally: $e");
    }
  }

  Future<void> _saveMember() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final currentUserId = user?.id;

      if (currentUserId == null) {
        throw 'User not authenticated.';
      }

      final roomNumber = _roomNumberController.text.trim();
      final floorNumber = int.tryParse(_floorController.text.trim()) ?? 1;
      final double advanceAmount =
          double.tryParse(_advancePaidController.text.trim()) ?? 0;
      final double dueAmount =
          double.tryParse(_dueController.text.trim()) ?? 0;
      final double roomRentAmount =
          double.tryParse(_roomRentController.text.trim()) ?? 0;

      String? activeMessId =
      (widget.messId != null && widget.messId!.isNotEmpty)
          ? widget.messId
          : null;

      final newMemberData = <String, dynamic>{
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        if (activeMessId != null) 'mess_id': activeMessId,
        'owner_id': currentUserId,
        'name': _nameController.text.trim(),
        'parents_name': _parentsNameController.text.trim(),
        'occupation': _occupationController.text.trim(),
        'home_town': _homeTownController.text.trim(),
        'mobile_number': _mobileController.text.trim(),
        'parents_mobile_number': _fatherMobileController.text.trim(),
        'floor': floorNumber,
        'occupied_rooms': roomNumber,
        'entry_date': _entryDateController.text.trim(),
        'month': _monthController.text.trim(),
        'advance_paid': advanceAmount,
        'due': dueAmount,
        'remarks': _remarksController.text.trim(),
        'mess_member_payments': [],
        'room_rent': roomRentAmount,
      };

      try {
        if (activeMessId == null) {
          final setupRow = await supabase
              .from('mess_setup')
              .select('id')
              .eq('owner_id', currentUserId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          activeMessId = setupRow?['id']?.toString();
          if (activeMessId != null && activeMessId.isNotEmpty) {
            newMemberData['mess_id'] = activeMessId;
          }
        }

        // 1. Auto-create or mark room occupied (online), scoped by mess_id
        if (roomNumber.isNotEmpty) {
          var roomLookup = supabase
              .from('mess_rooms')
              .select('id')
              .eq('occupied_rooms', roomNumber);

          if (activeMessId != null && activeMessId.isNotEmpty) {
            roomLookup = roomLookup.eq('mess_id', activeMessId);
          } else {
            roomLookup = roomLookup.eq('owner_id', currentUserId);
          }

          final existingRoom = await roomLookup.maybeSingle();

          if (existingRoom == null) {
            await supabase.from('mess_rooms').insert({
              if (activeMessId != null && activeMessId.isNotEmpty)
                'mess_id': activeMessId,
              'owner_id': currentUserId,
              'occupied_rooms': roomNumber,
              'empty_rooms': roomNumber,
              'floor': floorNumber,
              'is_occupied': true,
            });
          } else {
            await supabase
                .from('mess_rooms')
                .update({'is_occupied': true})
                .eq('id', existingRoom['id']);
          }
        }

        // 2. Insert member online with mess_id and grab actual generated UUID
        final memberResponse = await supabase
            .from('mess_members')
            .insert({
          if (activeMessId != null && activeMessId.isNotEmpty)
            'mess_id': activeMessId,
          'owner_id': currentUserId,
          'name': newMemberData['name'],
          'parents_name': newMemberData['parents_name'],
          'occupation': newMemberData['occupation'],
          'home_town': newMemberData['home_town'],
          'mobile_number': newMemberData['mobile_number'],
          'parents_mobile_number': newMemberData['parents_mobile_number'],
          'floor': floorNumber,
          'occupied_rooms': roomNumber,
          'entry_date': newMemberData['entry_date'],
          'month': newMemberData['month'],
          'advance_paid': advanceAmount,
          'due': dueAmount,
          'remarks': newMemberData['remarks'],
          'room_rent': roomRentAmount,
        })
            .select()
            .single();

        newMemberData['id'] = memberResponse['id'];
        if (memberResponse['mess_id'] != null) {
          newMemberData['mess_id'] = memberResponse['mess_id'];
        }
        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError, stackTrace) {
        debugPrint("❌ AddMembersScreen cloud save failed: $networkError");
        debugPrint("$stackTrace");
        if (mounted) {
          setState(() => _isOfflineMode = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cloud save failed: $networkError'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      await _cacheNewMemberLocally(
        newMemberData,
        messId: activeMessId,
        ownerId: currentUserId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOfflineMode
                ? 'Offline mode: Member saved locally!'
                : 'Member and initial payment record saved successfully!'),
            backgroundColor: _isOfflineMode ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding member: $e')),
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Add New Member',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.person, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter member name'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentsNameController,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Parents Name',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.family_restroom, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter parents name'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _occupationController,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Occupation',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.work, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter occupation'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _homeTownController,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Home Town',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.location_city, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter home town'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.phone, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter mobile number'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fatherMobileController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: "Parents Mobile Number",
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.phone_android, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? "Please enter parents mobile number"
                    : null,
              ),
              const SizedBox(height: 16),

              // Floor & Room Input Fields Side-by-Side
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _floorController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Floor (e.g. 2)',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        prefixIcon: const Icon(Icons.layers, color: Colors.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Enter floor'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roomNumberController,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Room No (e.g. 201)',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        prefixIcon: const Icon(Icons.meeting_room, color: Colors.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Enter room'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Entry Date Picker Field
              TextFormField(
                controller: _entryDateController,
                readOnly: true,
                onTap: () => _selectEntryDate(context),
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Entry Date',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.calendar_today, color: Colors.blue),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please select entry date'
                    : null,
              ),
              const SizedBox(height: 16),
              // Month Dropdown Field
              DropdownButtonFormField<String>(
                value: _selectedMonth,
                isDense: true,
                isExpanded: true,
                itemHeight: 48,
                menuMaxHeight: 240,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Month',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  labelStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(
                    Icons.date_range,
                    color: Colors.blue,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: _monthOptions
                    .map(
                      (monthLabel) => DropdownMenuItem<String>(
                    value: monthLabel,
                    child: Text(
                      monthLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedMonth = value;
                    _monthController.text = value;
                  });
                },
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Please select month'
                    : null,
              ),
              const SizedBox(height: 16),

              // Financial Fields (Advance, Room Rent & Due)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _advancePaidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Advance',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        prefixIcon: const Icon(Icons.attach_money, color: Colors.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _roomRentController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Room Rent',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        prefixIcon: const Icon(Icons.home_outlined, color: Colors.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _dueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Due',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[400]!),
                        ),
                        prefixIcon: const Icon(Icons.money_off, color: Colors.blue),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Remarks Field
              TextFormField(
                controller: _remarksController,
                maxLines: 2,
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Remarks',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  prefixIcon: const Icon(Icons.note, color: Colors.blue),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              SafeArea(
                top: false,
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveMember,
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
                      'Save Member',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}