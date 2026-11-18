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

class ManageMessCard extends StatelessWidget {
  final VoidCallback? onMemberAdded;
  final String? ownerId;
  final String? ownerEmail;

  const ManageMessCard({
    super.key,
    this.onMemberAdded,
    this.ownerId,
    this.ownerEmail,
  });

  // Helper to guarantee we always have the active owner's ID
  String? get _effectiveOwnerId =>
      ownerId ?? Supabase.instance.client.auth.currentUser?.id;

  // Local Cache Key for offline setup navigation check
  static const String _cacheSetupKey = 'offline_cache_mess_setup_data';

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
            items: const [
              PopupMenuItem<int>(
                value: 3,
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 20, color: Colors.orange),
                    SizedBox(width: 12),
                    Text('Mess Setup'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 20, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Show members details'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, size: 20, color: Colors.green),
                    SizedBox(width: 12),
                    Text('Add new members'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 4,
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 20, color: Colors.purple),
                    SizedBox(width: 12),
                    Text('Archived Members'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 5,
                child: Row(
                  children: [
                    Icon(Icons.door_sliding_outlined, size: 20, color: Colors.teal),
                    SizedBox(width: 12),
                    Text('Room Status'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 6,
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 20, color: Colors.indigo),
                    SizedBox(width: 12),
                    Text('Month-Wise Collections'),
                  ],
                ),
              ),
              PopupMenuItem<int>(
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
            final currentOwnerId = _effectiveOwnerId;

            if (currentOwnerId == null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User session not found. Please log in again.')),
                );
              }
              return;
            }

            if (selectedValue == 3) {
              Map<String, dynamic>? setupData;

              try {
                // 1. Attempt online fetch strictly scoped to the logged-in owner's ID
                setupData = await Supabase.instance.client
                    .from('mess_setup')
                    .select('*')
                    .eq('owner_id', currentOwnerId)
                    .maybeSingle();

                // Save to local cache for offline usage
                if (setupData != null) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(_cacheSetupKey, jsonEncode(setupData));
                }
              } catch (networkError) {
                // 2. Silently fallback to local SharedPreferences cache when offline
                debugPrint("🌐 Network offline in ManageMessCard. Loading setup from cache... Error: $networkError");
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final cachedStr = prefs.getString(_cacheSetupKey);
                  if (cachedStr != null) {
                    final decoded = jsonDecode(cachedStr);
                    if (decoded is Map<String, dynamic>) {
                      setupData = decoded;
                    }
                  }
                } catch (cacheError) {
                  debugPrint("Error reading local setup cache: $cacheError");
                }
              }

              if (!context.mounted) return;

              final bool? result;
              final localSetup = setupData; // Non-nullable promotion reference

              if (localSetup == null) {
                // No setup found anywhere -> Open MessSetupScreen
                result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MessSetupScreen(),
                  ),
                );
              } else {
                // Setup exists -> Open EditMessSetupScreen with guaranteed non-null map
                result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditMessSetupScreen(
                      initialSetup: localSetup,
                    ),
                  ),
                );
              }

              if (result == true && onMemberAdded != null) {
                onMemberAdded!();
              }
            } else if (selectedValue == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShowMembersDetailsScreen(),
                ),
              );
            } else if (selectedValue == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddMembersScreen(),
                ),
              ).then((result) {
                if (result == true && onMemberAdded != null) {
                  onMemberAdded!();
                }
              });
            } else if (selectedValue == 4) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ArchiveScreen(),
                ),
              );
            } else if (selectedValue == 5) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RoomStatusScreen(),
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ElectricBillDetailsScreen(),
                ),
              ).then((_) {
                if (onMemberAdded != null) {
                  onMemberAdded!();
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
          subtitle: Text('View details, room status, add members, or check archive'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ),
    );
  }
}