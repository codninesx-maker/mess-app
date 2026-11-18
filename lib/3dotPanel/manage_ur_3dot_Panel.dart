import 'package:flutter/material.dart';
import 'package:mess_sur/3dotPanel/AdminPanelScreen.dart';
import 'package:mess_sur/3dotPanel/how_to_use.dart';
import 'package:mess_sur/3dotPanel/policy.dart';
import 'package:mess_sur/signin/otp_login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'about.dart';

class ManageYourThreeDotPanel extends StatelessWidget {
  const ManageYourThreeDotPanel({super.key});

  bool get _isAdmin {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return email?.toLowerCase() == 'codninesx@gmail.com';
  }

  Future<void> _signOut(BuildContext context) async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out of your account?'),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      try {
        // Attempt network sign out, but fallback gracefully if offline
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint("Offline sign-out notice: $e");
      }

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const OtpLoginScreen()),
              (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'Unknown User';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Account Info Header (Non-clickable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userEmail,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAdmin ? 'Super Admin' : 'Admin Mess Owner',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isAdmin ? Colors.orange[800] : Colors.grey[600],
                          fontWeight:
                          _isAdmin ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Admin Control Panel Option (Visible only for codninesx@gmail.com)
          if (_isAdmin) ...[
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.orange,
                size: 20,
              ),
              title: const Text(
                'Admin Panel',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(context); // Close popup card first
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminMenuScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 8),
          ],
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: Icon(
              Icons.menu_book_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            title: const Text(
              'How to Use App',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              Navigator.pop(context); // Close popup card first
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HowToUseScreen(),
                ),
              );
            },
          ),
          // Privacy & Policy Option
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: Icon(
              Icons.privacy_tip_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            title: const Text(
              'Privacy & Policy',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              Navigator.pop(context); // Close popup card first
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PolicyScreen(),
                ),
              );
            },
          ),

          // About App Option
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            title: const Text(
              'About App',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              Navigator.pop(context); // Close popup card first
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AboutScreen(),
                ),
              );
            },
          ),
          const Divider(height: 8),

          // Sign Out Option
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
              size: 20,
            ),
            title: const Text(
              'Sign Out',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.red,
                fontSize: 13,
              ),
            ),
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}