import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditMemberScreen extends StatefulWidget {
  final Map<String, dynamic> member;

  const EditMemberScreen({super.key, required this.member});

  @override
  State<EditMemberScreen> createState() => _EditMemberScreenState();
}

class _EditMemberScreenState extends State<EditMemberScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _parentsNameController;
  late final TextEditingController _occupationController;
  late final TextEditingController _homeTownController;
  late final TextEditingController _mobileController;
  late final TextEditingController _fatherMobileController;
  late final TextEditingController _floorController;
  late final TextEditingController _roomNumberController;
  late final TextEditingController _entryDateController;
  late final TextEditingController _monthController;
  late final TextEditingController _advancePaidController;
  late final TextEditingController _dueController;
  late final TextEditingController _remarksController;
  late final TextEditingController _roomRentController; // Add this line


  DateTime? _selectedEntryDate;
  bool _isLoading = false;
  bool _isOfflineMode = false;

  // Section-wise edit toggle flags
  bool _isEditingPersonal = false;
  bool _isEditingRoomAndDate = false;
  bool _isEditingFinancials = false;

  // Local Cache Keys matching ShowMembersDetailsScreen & ArchiveScreen
  static const String _cacheMembersKey = 'offline_cache_show_members_list';
  static const String _cacheArchiveKey = 'offline_cache_archive_members_list';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member['name'] ?? '');
    _parentsNameController = TextEditingController(text: widget.member['parents_name'] ?? '');
    _occupationController = TextEditingController(text: widget.member['occupation'] ?? '');
    _homeTownController = TextEditingController(text: widget.member['home_town'] ?? '');
    _mobileController = TextEditingController(text: widget.member['mobile_number'] ?? '');
    _fatherMobileController = TextEditingController(text: widget.member['parents_mobile_number'] ?? '');
    _floorController = TextEditingController(text: widget.member['floor']?.toString() ?? '');
    _roomNumberController = TextEditingController(text: widget.member['occupied_rooms']?.toString() ?? '');
    _entryDateController = TextEditingController(text: widget.member['entry_date'] ?? '');
    _monthController = TextEditingController(text: widget.member['month'] ?? '');
    _advancePaidController = TextEditingController(text: widget.member['advance_paid']?.toString() ?? '0');
    _dueController = TextEditingController(text: widget.member['due']?.toString() ?? '0');
    _remarksController = TextEditingController(text: widget.member['remarks'] ?? '');
    _roomRentController = TextEditingController(text: widget.member['room_rent']?.toString() ?? '0');

    if (widget.member['entry_date'] != null) {
      _selectedEntryDate = DateTime.tryParse(widget.member['entry_date']);
    }
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

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _selectEntryDate(BuildContext context) async {
    if (!_isEditingRoomAndDate) return;

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

  /// Syncs updated member details into local SharedPreferences caches
  Future<void> _updateCachedMemberLocally(dynamic memberId, Map<String, dynamic> updatedData) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 1. Update in active members cache
      final membersStr = prefs.getString(_cacheMembersKey);
      if (membersStr != null) {
        final List membersList = jsonDecode(membersStr) as List;
        for (int i = 0; i < membersList.length; i++) {
          if (membersList[i]['id'] == memberId) {
            membersList[i] = {...membersList[i], ...updatedData};
            break;
          }
        }
        await prefs.setString(_cacheMembersKey, jsonEncode(membersList));
      }

      // 2. Update in archive members cache if present
      final archiveStr = prefs.getString(_cacheArchiveKey);
      if (archiveStr != null) {
        final List archiveList = jsonDecode(archiveStr) as List;
        for (int i = 0; i < archiveList.length; i++) {
          if (archiveList[i]['id'] == memberId) {
            archiveList[i] = {...archiveList[i], ...updatedData};
            break;
          }
        }
        await prefs.setString(_cacheArchiveKey, jsonEncode(archiveList));
      }
    } catch (e) {
      debugPrint("Error updating member in local cache: $e");
    }
  }

  Future<void> _updateMember() async {
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
      final newAdvancePaid = double.tryParse(_advancePaidController.text.trim()) ?? 0;
      final memberId = widget.member['id'];

      final updatedData = {
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
        'advance_paid': newAdvancePaid,
        'due': double.tryParse(_dueController.text.trim()) ?? 0,
        'remarks': _remarksController.text.trim(),
        'room_rent': double.tryParse(_roomRentController.text.trim()) ?? 0,
      };

      try {
        // 1. Ensure updated room exists in mess_rooms (scoped to current owner)
        if (roomNumber.isNotEmpty) {
          final existingRoom = await supabase
              .from('mess_rooms')
              .select('id')
              .eq('owner_id', currentUserId)
              .eq('occupied_rooms', roomNumber)
              .maybeSingle();

          if (existingRoom == null) {
            await supabase.from('mess_rooms').insert({
              'owner_id': currentUserId,
              'occupied_rooms': roomNumber,
              'floor': floorNumber,
              'room_type': 'double',
            });
          }
        }

        // 2. Update member details in active table 'mess_members'
        await supabase
            .from('mess_members')
            .update(updatedData)
            .eq('id', memberId)
            .eq('owner_id', currentUserId);

        // 3. ALSO update 'mess_archive' just in case an archive record exists for this ID
        await supabase
            .from('mess_archive')
            .update(updatedData)
            .eq('id', memberId)
            .eq('owner_id', currentUserId);

        if (mounted) setState(() => _isOfflineMode = false);
      } catch (networkError) {
        // Network offline -> Handle gracefully via local cache fallback
        debugPrint("Network offline. Updating member in local cache... Error: $networkError");
        if (mounted) setState(() => _isOfflineMode = true);
      }

      // Always keep local cache synchronized
      await _updateCachedMemberLocally(memberId, updatedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineMode
                  ? 'Offline mode: Member changes saved locally!'
                  : 'Member details updated successfully!',
            ),
            backgroundColor: _isOfflineMode ? Colors.orange : Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error updating member: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating member: $e')),
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
            const Text('Edit Member', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
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
              // --- SECTION 1: PERSONAL & CONTACT DETAILS ---
              _buildSectionHeaderWithToggle(
                title: 'Personal & Contact Details',
                icon: Icons.person,
                isEditing: _isEditingPersonal,
                onToggle: () => setState(() => _isEditingPersonal = !_isEditingPersonal),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.person,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter member name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentsNameController,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Parents Name',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.family_restroom,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter parents name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _occupationController,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Occupation',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.work,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter occupation' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _homeTownController,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Home Town',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.location_city,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter home town' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.phone,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter mobile number' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fatherMobileController,
                keyboardType: TextInputType.phone,
                readOnly: !_isEditingPersonal,
                style: TextStyle(
                  color: _isEditingPersonal ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Parents Mobile Number',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingPersonal ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.phone_android,
                    color: _isEditingPersonal ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingPersonal ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter parents mobile number' : null,
              ),
              const SizedBox(height: 24),

              // --- SECTION 2: ROOM & ENTRY DETAILS ---
              _buildSectionHeaderWithToggle(
                title: 'Room & Entry Details',
                icon: Icons.meeting_room,
                isEditing: _isEditingRoomAndDate,
                onToggle: () => setState(() => _isEditingRoomAndDate = !_isEditingRoomAndDate),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _floorController,
                      keyboardType: TextInputType.number,
                      readOnly: !_isEditingRoomAndDate,
                      style: TextStyle(
                        color: _isEditingRoomAndDate ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Floor (e.g. 2)',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingRoomAndDate ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.layers,
                          color: _isEditingRoomAndDate ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingRoomAndDate ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Enter floor' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roomNumberController,
                      keyboardType: TextInputType.text,
                      readOnly: !_isEditingRoomAndDate,
                      style: TextStyle(
                        color: _isEditingRoomAndDate ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Room No (e.g. 201)',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingRoomAndDate ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.meeting_room,
                          color: _isEditingRoomAndDate ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingRoomAndDate ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Enter room' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _entryDateController,
                readOnly: true,
                onTap: () => _selectEntryDate(context),
                style: TextStyle(
                  color: _isEditingRoomAndDate ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Entry Date',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingRoomAndDate ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.calendar_today,
                    color: _isEditingRoomAndDate ? Colors.blue : Colors.grey[500],
                  ),
                  suffixIcon: _isEditingRoomAndDate ? const Icon(Icons.arrow_drop_down) : null,
                  filled: true,
                  fillColor: !_isEditingRoomAndDate ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please select entry date' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _monthController,
                readOnly: !_isEditingRoomAndDate,
                style: TextStyle(
                  color: _isEditingRoomAndDate ? Colors.black87 : Colors.grey[700],
                ),
                decoration: InputDecoration(
                  labelText: 'Month (e.g., November 2026)',
                  labelStyle: TextStyle(color: Colors.grey[600]),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isEditingRoomAndDate ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                  ),
                  prefixIcon: Icon(
                    Icons.date_range,
                    color: _isEditingRoomAndDate ? Colors.blue : Colors.grey[500],
                  ),
                  filled: true,
                  fillColor: !_isEditingRoomAndDate ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter month' : null,
              ),
              const SizedBox(height: 24),

              // --- SECTION 3: FINANCIALS & REMARKS ---
              _buildSectionHeaderWithToggle(
                title: 'Financials & Remarks',
                icon: Icons.payments,
                isEditing: _isEditingFinancials,
                onToggle: () => setState(() => _isEditingFinancials = !_isEditingFinancials),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _advancePaidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: !_isEditingFinancials,
                      style: TextStyle(
                        color: _isEditingFinancials ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Advance',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFinancials ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.attach_money,
                          color: _isEditingFinancials ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFinancials ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _roomRentController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: !_isEditingFinancials,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _dueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      readOnly: !_isEditingFinancials,
                      style: TextStyle(
                        color: _isEditingFinancials ? Colors.black87 : Colors.grey[700],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Due',
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isEditingFinancials ? Colors.grey[400]! : Colors.grey[300]!,
                          ),
                        ),
                        prefixIcon: Icon(
                          Icons.money_off,
                          color: _isEditingFinancials ? Colors.blue : Colors.grey[500],
                        ),
                        filled: true,
                        fillColor: !_isEditingFinancials ? Colors.grey[200]?.withOpacity(0.6) : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 28),
              SafeArea(
                top: false,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateMember,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator.adaptive(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                        : const Text('Update Member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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