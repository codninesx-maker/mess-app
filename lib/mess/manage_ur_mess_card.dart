import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mess_sur/mess/electric_bill_details.dart';
import 'package:mess_sur/mess/show_members_details.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'MonthCollectionScreen.dart';
import 'add_new_members.dart';
import 'archive.dart';
import 'edit_mess_setup.dart';
import 'mess_setup.dart';
import 'room_status.dart';

class ManageMessCard extends StatefulWidget {
  final VoidCallback? onMemberAdded;
  final String? ownerId;
  final String? ownerEmail;

  const ManageMessCard({
    super.key,
    this.onMemberAdded,
    this.ownerId,
    this.ownerEmail,
  });

  @override
  State<ManageMessCard> createState() => _ManageMessCardState();
}

class _ManageMessCardState extends State<ManageMessCard> {
  Timer? _setupTapTimer;
  int _setupTapCount = 0;
  Offset _lastTapGlobalPosition = Offset.zero;

  String? get _effectiveOwnerId =>
      widget.ownerId ?? Supabase.instance.client.auth.currentUser?.id;

  String _setupCacheKey(String ownerId) => 'offline_cache_mess_setup_data_$ownerId';
  String _allSetupsCacheKey(String ownerId) => 'offline_cache_all_mess_setups_$ownerId';

  @override
  void dispose() {
    _setupTapTimer?.cancel();
    super.dispose();
  }

  Future<List> _loadAllSetupsData(
      String currentOwnerId,
      ) async {
    List setups = [];
    final allKey = _allSetupsCacheKey(currentOwnerId);
    final singleKey = _setupCacheKey(currentOwnerId);

    try {
      final response = await Supabase.instance.client
          .from('mess_setup')
          .select('*')
          .eq('owner_id', currentOwnerId)
          .order('created_at', ascending: false);

      setups = (response as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final prefs = await SharedPreferences.getInstance();
      if (setups.isNotEmpty) {
        await prefs.setString(allKey, jsonEncode(setups));
        await prefs.setString(singleKey, jsonEncode(setups.first));
      } else {
        await prefs.remove(allKey);
        await prefs.remove(singleKey);
      }
    } catch (networkError) {
      debugPrint(
        "🌐 Network offline in ManageMessCard. Loading setups from cache... Error: $networkError",
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        final allCachedStr = prefs.getString(allKey);
        if (allCachedStr != null) {
          final decoded = jsonDecode(allCachedStr);
          if (decoded is List) {
            setups = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } else {
          final singleCachedStr = prefs.getString(singleKey);
          if (singleCachedStr != null) {
            final decoded = jsonDecode(singleCachedStr);
            if (decoded is Map<String, dynamic>) {
              setups = [decoded];
            }
          }
        }
      } catch (cacheError) {
        debugPrint("Error reading local setups cache: $cacheError");
      }
    }

    return setups;
  }

  Future? _selectMessIfNeeded(
      String currentOwnerId, {
        Offset? fallbackPosition,
      }) async {
    final setups = await _loadAllSetupsData(currentOwnerId);
    if (!mounted) return null;

    if (setups.length == 1) {
      return setups.first;
    }
    if (setups.length > 1) {
      return await _showMessSubMenuCard(
        setups,
        fallbackPosition ?? _lastTapGlobalPosition,
      );
    }
    return null;
  }

  Future? _showMessSubMenuCard(
      List setups,
      Offset? fallbackPosition,
      ) async {
    final RenderBox? overlay =
    Overlay.of(context).context.findRenderObject() as RenderBox?;
    final RenderBox? cardBox = context.findRenderObject() as RenderBox?;

    if (overlay == null) return null;
    Rect targetRect;
    if (cardBox != null && cardBox.hasSize) {
      final Offset cardTopLeft = cardBox.localToGlobal(Offset.zero, ancestor: overlay);
      final Size cardSize = cardBox.size;
      // Anchor right near/above the "Manage Your Mess" card
      targetRect = Rect.fromLTWH(
        cardTopLeft.dx + 16,
        cardTopLeft.dy,
        cardSize.width - 32,
        cardSize.height,
      );
    } else {
      final Offset pos = fallbackPosition ?? Offset.zero;
      targetRect = Rect.fromPoints(pos, pos);
    }
    final RelativeRect position = RelativeRect.fromRect(
      targetRect,
      Offset.zero & overlay.size,
    );

    // Value: 0..setups.length-1 = select mess index, -1 = create new mess
    final int? choice = await showMenu<int>(
      context: context,
      position: position,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: [
        const PopupMenuItem<int>(
          enabled: false,
          height: 34,
          child: Text(
            'Select Mess',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        ...List.generate(setups.length, (index) {
          final mess = setups[index];
          final name = (mess['mess_name'] ?? 'Unnamed Mess').toString();
          final floors = mess['total_floors'] ?? 1;
          final rooms = mess['total_rooms'] ?? 1;

          return PopupMenuItem<int>(
            value: index,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apartment, size: 19, color: Colors.orange),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '$floors Floors • $rooms Rooms',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          );
        }),
        const PopupMenuDivider(height: 3),
      ],
    );
    if (choice == null || !mounted) return null;
    if (choice == -1) {
      await _navigateToSetup(forceNewSetup: true);
      return null;
    }
    if (choice >= 0 && choice < setups.length) {
      return setups[choice];
    }
    return null;
  }

  Future<void> _navigateToSetup({required bool forceNewSetup}) async {
    final currentOwnerId = _effectiveOwnerId;
    if (currentOwnerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User session not found. Please log in again.'),
          ),
        );
      }
      return;
    }

    if (forceNewSetup) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MessSetupScreen(createNew: true),
        ),
      );
      if (result == true && widget.onMemberAdded != null) {
        widget.onMemberAdded!();
      }
      return;
    }

    final setups = await _loadAllSetupsData(currentOwnerId);
    if (!mounted) return;

    Map<String, dynamic>? selectedSetup;
    if (setups.isEmpty) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MessSetupScreen(createNew: true),
        ),
      );
      if (result == true && widget.onMemberAdded != null) {
        widget.onMemberAdded!();
      }
      return;
    } else if (setups.length == 1) {
      selectedSetup = setups.first;
    } else {
      selectedSetup =
      await _showMessSubMenuCard(setups, _lastTapGlobalPosition);
      if (selectedSetup == null || !mounted) return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _setupCacheKey(currentOwnerId),
      jsonEncode(selectedSetup),
    );

    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditMessSetupScreen(
          initialSetup: selectedSetup!,
        ),
      ),
    );

    if (result == true && widget.onMemberAdded != null) {
      widget.onMemberAdded!();
    }
  }

  void _handleMessSetupMenuTap(BuildContext menuContext) {
    _setupTapCount += 1;
    _setupTapTimer?.cancel();

    if (_setupTapCount >= 3) {
      _setupTapCount = 0;
      if (menuContext.mounted && Navigator.canPop(menuContext)) {
        Navigator.pop(menuContext);
      }
      _navigateToSetup(forceNewSetup: true);
      return;
    }

    _setupTapTimer = Timer(const Duration(milliseconds: 320), () {
      final count = _setupTapCount;
      _setupTapCount = 0;
      if (!mounted) return;

      if (count == 1) {
        if (menuContext.mounted && Navigator.canPop(menuContext)) {
          Navigator.pop(menuContext);
        }
        _navigateToSetup(forceNewSetup: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      child: GestureDetector(
        onTapDown: (TapDownDetails details) {
          _lastTapGlobalPosition = details.globalPosition;

          final RenderBox overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
          final RelativeRect position = RelativeRect.fromRect(
            Rect.fromPoints(details.globalPosition, details.globalPosition),
            Offset.zero & overlay.size,
          );

          showMenu<int>(
            context: context,
            position: position,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            items: [
              PopupMenuItem<int>(
                padding: EdgeInsets.zero,
                child: Builder(
                  builder: (menuContext) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                    _lastTapGlobalPosition = d.globalPosition,
                    onTap: () => _handleMessSetupMenuTap(menuContext),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            size: 20,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Mess Setup',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 20, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Show members details'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined,
                        size: 20, color: Colors.green),
                    SizedBox(width: 12),
                    Text('Add new members'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 4,
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined,
                        size: 20, color: Colors.purple),
                    SizedBox(width: 12),
                    Text('Archived Members'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 5,
                child: Row(
                  children: [
                    Icon(Icons.door_sliding_outlined,
                        size: 20, color: Colors.teal),
                    SizedBox(width: 12),
                    Text('Room Status'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 6,
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 20, color: Colors.indigo),
                    SizedBox(width: 12),
                    Text('Month-Wise Collections'),
                  ],
                ),
              ),
              const PopupMenuItem<int>(
                value: 7,
                child: Row(
                  children: [
                    Icon(Icons.electric_bolt, size: 20, color: Colors.amber),
                    SizedBox(width: 12),
                    Text('Electric Bill Details'),
                  ],
                ),
              ),
            ],
          ).then((int? selectedValue) async {
            if (selectedValue == null) return;
            final currentOwnerId = _effectiveOwnerId;
            if (currentOwnerId == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User session not found. Please log in again.'),
                  ),
                );
              }
              return;
            }

            if (selectedValue == 1) {
              final setups = await _loadAllSetupsData(currentOwnerId);
              if (!context.mounted) return;

              Map<String, dynamic>? selectedMess;
              if (setups.length == 1) {
                selectedMess = setups.first;
              } else if (setups.length > 1) {
                selectedMess =
                await _showMessSubMenuCard(setups, _lastTapGlobalPosition);
                if (selectedMess == null || !context.mounted) return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShowMembersDetailsScreen(
                    messId: selectedMess?['id']?.toString(),
                    messName: selectedMess?['mess_name']?.toString(),
                  ),
                ),
              );
            } else if (selectedValue == 2) {
              final setups = await _loadAllSetupsData(currentOwnerId);
              if (!context.mounted) return;

              Map<String, dynamic>? selectedMess;
              if (setups.length == 1) {
                selectedMess = setups.first;
              } else if (setups.length > 1) {
                selectedMess = await _showMessSubMenuCard(
                    setups, _lastTapGlobalPosition);
                if (selectedMess == null || !context.mounted) return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddMembersScreen(
                    messId: selectedMess?['id']?.toString(),
                  ),
                ),
              ).then((result) {
                if (result == true && widget.onMemberAdded != null) {
                  widget.onMemberAdded!();
                }
              });
            } else if (selectedValue == 4) {
              final setups = await _loadAllSetupsData(currentOwnerId);
              if (!context.mounted) return;

              Map<String, dynamic>? selectedMess;
              if (setups.length == 1) {
                selectedMess = setups.first;
              } else if (setups.length > 1) {
                selectedMess =
                await _showMessSubMenuCard(setups, _lastTapGlobalPosition);
                if (selectedMess == null || !context.mounted) return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ArchiveScreen(
                    messId: selectedMess?['id']?.toString(),
                    messName: selectedMess?['mess_name']?.toString(),
                  ),
                ),
              );
            } else if (selectedValue == 5) {
              final setups = await _loadAllSetupsData(currentOwnerId);
              if (!context.mounted) return;

              Map<String, dynamic>? selectedMess;
              if (setups.length == 1) {
                selectedMess = setups.first;
              } else if (setups.length > 1) {
                selectedMess = await _showMessSubMenuCard(
                    setups, _lastTapGlobalPosition);
                if (selectedMess == null || !context.mounted) return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomStatusScreen(
                    messId: selectedMess?['id']?.toString(),
                    messName: selectedMess?['mess_name']?.toString(),
                  ),
                ),
              );
            } else if (selectedValue == 6) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MonthCollectionScreen(),
                ),
              );
            } else if (selectedValue == 7) {
              final setups = await _loadAllSetupsData(currentOwnerId);
              if (!context.mounted) return;

              Map<String, dynamic>? selectedMess;
              if (setups.length == 1) {
                selectedMess = setups.first;
              } else if (setups.length > 1) {
                selectedMess = await _showMessSubMenuCard(setups, _lastTapGlobalPosition);
                if (selectedMess == null || !context.mounted) return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ElectricBillDetailsScreen(
                    messId: selectedMess?['id']?.toString(),
                    messName: selectedMess?['mess_name']?.toString(),
                  ),
                ),
              ).then((_) {
                if (widget.onMemberAdded != null) {
                  widget.onMemberAdded!();
                }
              });
            }
          });
        },
        child: const ListTile(
          leading: Icon(Icons.people_alt),
          title: Text(
            'Manage Your Mess',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
              'View details, room status, add members, or check archive'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ),
    );
  }
}