import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kSuperAdminEmail = 'codninesx@gmail.com';

bool isSuperAdminUser(User? user) {
  return user?.email?.trim().toLowerCase() == kSuperAdminEmail;
}

class DeleteMessAndMemberService {
  DeleteMessAndMemberService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String? _normalizeId(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  void _requireSuperAdmin() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User not authenticated');
    }
    if (!isSuperAdminUser(user)) {
      throw StateError('Only super admin ($kSuperAdminEmail) can delete records.');
    }
  }

  /// Completely deletes a single member and their payment records.
  /// Allowed only for the super admin.
  Future<void> deleteMemberCompletely({
    required String memberId,
    String? messId,
  }) async {
    _requireSuperAdmin();

    final cleanMemberId = _normalizeId(memberId);
    if (cleanMemberId == null) {
      throw ArgumentError('Invalid memberId');
    }

    final cleanMessId = _normalizeId(messId);

    // Look up by id first so we always find the member even if messId was stale/null
    final memberRow = await _supabase
        .from('mess_members')
        .select('id, mess_id, occupied_rooms')
        .eq('id', cleanMemberId)
        .maybeSingle();

    final effectiveMessId =
        cleanMessId ?? _normalizeId(memberRow?['mess_id']?.toString());
    final roomNumber = _normalizeId(memberRow?['occupied_rooms']?.toString());

    await _supabase
        .from('mess_member_payments')
        .delete()
        .eq('member_id', cleanMemberId);

    final deletedRows = await _supabase
        .from('mess_members')
        .delete()
        .eq('id', cleanMemberId)
        .select('id');

    if ((deletedRows as List).isEmpty) {
      throw StateError(
        'No mess_members row was deleted for id=$cleanMemberId (check RLS DELETE policy on mess_members).',
      );
    }

    // Free room in mess_rooms if no other active member remains in that room
    if (effectiveMessId != null && roomNumber != null) {
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
  }

  Future<void> deleteMessCompletely({
    required String messId,
  }) async {
    _requireSuperAdmin();

    final cleanMessId = _normalizeId(messId);
    if (cleanMessId == null) {
      throw ArgumentError('Invalid messId');
    }

    final membersRows = await _supabase
        .from('mess_members')
        .select('id')
        .eq('mess_id', cleanMessId);

    final memberIds = (membersRows as List)
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    if (memberIds.isNotEmpty) {
      await _supabase
          .from('mess_member_payments')
          .delete()
          .inFilter('member_id', memberIds);
    }

    await _supabase.from('mess_members').delete().eq('mess_id', cleanMessId);
    await _supabase.from('mess_rooms').delete().eq('mess_id', cleanMessId);
    await _supabase
        .from('mess_electricity_bills')
        .delete()
        .eq('mess_id', cleanMessId);
    await _supabase.from('mess_archive').delete().eq('mess_id', cleanMessId);

    final deletedRows = await _supabase
        .from('mess_setup')
        .delete()
        .eq('id', cleanMessId)
        .select('id');

    if ((deletedRows as List).isEmpty) {
      throw StateError(
        'No mess_setup row was deleted for id=$cleanMessId (check RLS DELETE policy).',
      );
    }
  }
}

class _DeleteConfirmDialog extends StatefulWidget {

  const _DeleteConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmButtonText,
  });

  final String title;
  final String message;
  final String confirmButtonText;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _matchesWord = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.delete_forever, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          const Text(
            'Type DELETE to confirm:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'DELETE',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              final matches = value.trim() == 'DELETE';
              if (matches != _matchesWord) {
                setState(() => _matchesWord = matches);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _matchesWord ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmButtonText),
        ),
      ],
    );
  }
}

/// Shows a confirmation dialog requiring "DELETE" and permanently deletes a single member.
/// Restricted to super admin only.
Future<bool> confirmAndDeleteMember(
    BuildContext context, {
      required String memberId,
      required String memberName,
      String? messId,
      DeleteMessAndMemberService? service,
    }) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (!isSuperAdminUser(currentUser)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access denied: Only super admin can delete members.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DeleteConfirmDialog(
      title: 'Delete Member Permanently',
      message:
      'Permanently delete "$memberName" and all of their payment records? This cannot be undone.',
      confirmButtonText: 'Delete Forever',
    ),
  ) ??
      false;

  if (!confirmed) return false;

  try {
    await (service ?? DeleteMessAndMemberService()).deleteMemberCompletely(
      memberId: memberId,
      messId: messId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$memberName" deleted permanently.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    return true;
  } catch (e) {
    debugPrint('Error deleting member permanently: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete member: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return false;
  }
}

/// Shows a confirmation dialog requiring "DELETE" and permanently wipes
/// the entire mess and all associated records. Restricted to super admin only.
Future<bool> confirmAndDeleteMess(
    BuildContext context, {
      required String messId,
      required String messName,
      DeleteMessAndMemberService? service,
    }) async {
  final currentUser = Supabase.instance.client.auth.currentUser;
  if (!isSuperAdminUser(currentUser)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access denied: Only super admin can delete messes.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DeleteConfirmDialog(
      title: 'Delete Entire Mess',
      message:
      'This will permanently delete "$messName" along with all rooms, members, payment history, electricity bills, and archive records.',
      confirmButtonText: 'Delete Mess',
    ),
  ) ??
      false;

  if (!confirmed) return false;

  try {
    await (service ?? DeleteMessAndMemberService())
        .deleteMessCompletely(messId: messId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$messName" and all related data deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    return true;
  } catch (e) {
    debugPrint('Error deleting mess permanently: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete mess: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return false;
  }
}

class DeleteMessAndMemberScreen extends StatefulWidget {
  final String? messId;
  final String? messName;

  const DeleteMessAndMemberScreen({
    super.key,
    this.messId,
    this.messName,
  });

  @override
  State<DeleteMessAndMemberScreen> createState() =>
      _DeleteMessAndMemberScreenState();
}

class _DeleteMessAndMemberScreenState extends State<DeleteMessAndMemberScreen> {
  final _supabase = Supabase.instance.client;
  final _service = DeleteMessAndMemberService();

  bool _isLoading = true;
  List _messes = [];
  List _members = [];
  String? _selectedMessId;

  bool get _isSuperAdmin => isSuperAdminUser(_supabase.auth.currentUser);

  String? _cleanArg(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    _selectedMessId = _cleanArg(widget.messId);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DeleteMessAndMemberScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextMessId = _cleanArg(widget.messId);
    if (nextMessId != _cleanArg(oldWidget.messId) && nextMessId != null) {
      _selectedMessId = nextMessId;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null || !isSuperAdminUser(user)) {
        if (mounted) {
          setState(() {
            _messes = [];
            _members = [];
            _selectedMessId = null;
            _isLoading = false;
          });
        }
        return;
      }

      final messRows = await _supabase
          .from('mess_setup')
          .select('id, mess_name, address, owner_id')
          .order('mess_name', ascending: true);

      final messesList = (messRows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final messIds = messesList
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .toList();

      List membersList = [];
      if (messIds.isNotEmpty) {
        final memberRows = await _supabase
            .from('mess_members')
            .select('id, name, occupied_rooms, mess_id')
            .inFilter('mess_id', messIds)
            .order('name', ascending: true);

        membersList = (memberRows as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _messes = messesList;
        _members = membersList;
        if (_selectedMessId != null &&
            !_messes.any((m) => m['id']?.toString() == _selectedMessId)) {
          _selectedMessId = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading messes/members for deletion: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load records: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _messNameForId(String? messId) {
    if (messId == null) return 'Unknown Mess';
    final match = _messes.where((m) => m['id']?.toString() == messId).toList();
    if (match.isEmpty) {
      final cleanArgName = _cleanArg(widget.messName);
      if (cleanArgName != null && messId == _cleanArg(widget.messId)) {
        return cleanArgName;
      }
      return messId;
    }
    return match.first['mess_name']?.toString() ?? messId;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && !_isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Delete Mess & Members',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  'Super Admin Only',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Only the super admin account can view or permanently delete messes and members.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final visibleMembers = _selectedMessId == null
        ? _members
        : _members
        .where((m) => m['mess_id']?.toString() == _selectedMessId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Delete Mess & Members',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'Messes (Complete Wipe)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            if (_messes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No messes found.'),
                ),
              )
            else
              ..._messes.map((mess) {
                final messId = mess['id'].toString();
                final messName =
                    mess['mess_name']?.toString() ?? 'Unnamed Mess';
                final isSelected = _selectedMessId == messId;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.blue
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: ListTile(
                    selected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedMessId = isSelected ? null : messId;
                      });
                    },
                    leading: const Icon(
                      Icons.home_work_outlined,
                      color: Colors.red,
                    ),
                    title: Text(
                      messName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      mess['address']?.toString().isNotEmpty == true
                          ? mess['address'].toString()
                          : 'ID: $messId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever,
                          color: Colors.red),
                      tooltip: 'Delete Mess Permanently',
                      onPressed: () async {
                        final deleted = await confirmAndDeleteMess(
                          context,
                          messId: messId,
                          messName: messName,
                          service: _service,
                        );
                        if (deleted) {
                          await _loadData();
                        }
                      },
                    ),
                  ),
                );
              }),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedMessId == null
                      ? 'All Members (${visibleMembers.length})'
                      : 'Members in ${_messNameForId(_selectedMessId)} (${visibleMembers.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_selectedMessId != null)
                  TextButton(
                    onPressed: () =>
                        setState(() => _selectedMessId = null),
                    child: const Text('Show All'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (visibleMembers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No members found.'),
                ),
              )
            else
              ...visibleMembers.map((member) {
                final memberId = member['id'].toString();
                final memberName =
                    member['name']?.toString() ?? 'Unnamed Member';
                final room = member['occupied_rooms']?.toString() ?? 'N/A';
                final mId = member['mess_id']?.toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.person_remove_outlined,
                        color: Colors.red),
                    title: Text(
                      memberName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Room $room • ${_messNameForId(mId)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      tooltip: 'Delete Member Permanently',
                      onPressed: () async {
                        final deleted = await confirmAndDeleteMember(
                          context,
                          memberId: memberId,
                          memberName: memberName,
                          messId: mId,
                          service: _service,
                        );
                        if (deleted) {
                          await _loadData();
                        }
                      },
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}