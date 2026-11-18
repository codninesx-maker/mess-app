import 'package:flutter/material.dart';
import 'package:mess_sur/3dotPanel/OthersScreen.dart';
import 'package:mess_sur/messmeal/meal_details_screen.dart';
import 'package:mess_sur/messmeal/mess_meal_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageMealCard extends StatelessWidget {
  final VoidCallback? onMealUpdated;
  final String? ownerId;
  final String? ownerEmail;

  const ManageMealCard({
    super.key,
    this.onMealUpdated,
    this.ownerId,
    this.ownerEmail,
  });

  // Helper to guarantee we always have the active user's ID
  String? get _effectiveOwnerId =>
      ownerId ?? Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.orange.shade50, // Light orange background color
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
            items: [
              PopupMenuItem<int>(
                value: 1,
                child: SizedBox(
                  width: 200, // Adjust this width to make the menu card wider
                  child: Row(
                    children: const [
                      Icon(Icons.restaurant_menu, size: 20, color: Colors.green),
                      SizedBox(width: 12),
                      Text('Your Meal Details'),
                    ],
                  ),
                ),
              ),
              PopupMenuItem<int>(
                value: 2,
                child: SizedBox(
                  width: 200, // Match the same width here
                  child: Row(
                    children: const [
                      Icon(Icons.room_service, size: 20, color: Colors.orange),
                      SizedBox(width: 12),
                      Text('Your Meal Providers'),
                    ],
                  ),
                ),
              ),
            ],
          ).then((int? selectedValue) async {
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
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MealDetailsScreen(),
                ),
              );
              if (onMealUpdated != null) {
                onMealUpdated!();
              }
            } else if (selectedValue == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MealProviderScreen(),
                ),
              );
            }
          });
        },
        child: const ListTile(
          leading: Icon(Icons.room_service, color: Colors.orange),
          title: Text(
            'Manage Your Meals',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('Track daily 3 meals, per-meal rate, and expenses'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ),
    );
  }
}