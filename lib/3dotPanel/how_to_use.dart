import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';

class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'How to Use App',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Top Welcome Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withOpacity(0.15),
                  primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: primaryColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: primaryColor.withOpacity(0.2),
                  child: Icon(Icons.menu_book_rounded, color: primaryColor, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete User Guide',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Follow these steps to set up your mess, track rooms, collect rent & utility bills, and manage daily meals smoothly.',
                        style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Step 1: Initial Mess Setup
          _buildGuideSection(
            stepNumber: '1',
            title: 'Initial Mess & Room Setup',
            icon: Icons.settings_suggest,
            color: Colors.indigo,
            items: [
              _GuidePoint(
                subtitle: 'Configure Total Rooms',
                description:
                'Go to your Mess Setup settings and enter the total number of rooms in your mess. This enables accurate occupancy tracking on your dashboard.',
              ),
              _GuidePoint(
                subtitle: 'Add Room Numbers',
                description:
                'Register your individual room numbers (e.g., 101, 102, 205) so you can assign members to specific rooms and floors.',
              ),
            ],
          ),

          // Step 2: Managing Members
          _buildGuideSection(
            stepNumber: '2',
            title: 'Adding & Managing Members',
            icon: Icons.people_alt,
            color: Colors.teal,
            items: [
              _GuidePoint(
                subtitle: 'Add New Members',
                description:
                'Tap "Add New Member" and fill in their name, mobile number, guardian contact, entry date, assigned floor, room number, monthly room rent, and any advance paid.',
              ),
              _GuidePoint(
                subtitle: 'Search & Quick Call',
                description:
                'Open "Member Details" to search members by name, room number, floor, or mobile. Tap any member card to view their full profile or tap their phone number to call directly.',
              ),
              _GuidePoint(
                subtitle: 'Edit or Exit/Archive Members',
                description:
                'Inside a member\'s detail popup, tap the 3-dot menu (⋮) to edit their info or select "Exit Member" when they leave. Exiting moves their record to Archives while keeping past payment history intact.',
              ),
            ],
          ),

          // Step 3: Room Occupancy & Transitions
          _buildGuideSection(
            stepNumber: '3',
            title: 'Room Occupancy & Member Handovers',
            icon: Icons.meeting_room,
            color: Colors.blue,
            items: [
              _GuidePoint(
                subtitle: 'Single vs. Transition Rooms',
                description:
                'In the "Occupied Rooms" tab, standard occupied rooms appear in Blue. If an outgoing member is leaving at month-end and a new member books the same room for next month, assign both to that room—it will highlight in Orange to flag an active transition.',
              ),
              _GuidePoint(
                subtitle: 'Completing a Handover',
                description:
                'Tap an Orange transition room to view both occupants. Once the outgoing member leaves at the end of the month, archive their profile so the room cleanly displays the new occupant.',
              ),
            ],
          ),

          // Step 4: Electricity Bills
          _buildGuideSection(
            stepNumber: '4',
            title: 'Electricity Bill Management',
            icon: Icons.electric_bolt,
            color: Colors.amber.shade800,
            items: [
              _GuidePoint(
                subtitle: 'Log Multiple Meter Bills',
                description:
                'Open "Electric Bill Details" to record bills by meter number, floor, date, and month. If you have multiple meters in the same month, add each bill separately.',
              ),
              _GuidePoint(
                subtitle: 'Automatic Per-Member Split',
                description:
                'The app automatically sums all electricity bills for the current month and divides the total equally across all active members.',
              ),
              _GuidePoint(
                subtitle: 'Sync to Monthly Dues',
                description:
                'Keep the "Update all members\' monthly due share" toggle ON to automatically include each member\'s electricity share in their monthly due calculation.',
              ),
            ],
          ),

          // Step 5: Rent Payments & Ledger
          _buildGuideSection(
            stepNumber: '5',
            title: 'Collecting Payments & Member Ledger',
            icon: Icons.receipt_long,
            color: Colors.green,
            items: [
              _GuidePoint(
                subtitle: 'Record Monthly Payments',
                description:
                'Open a member\'s profile, tap the 3-dot menu (⋮), and select "Payment Ledger". Tap to add a monthly payment, select the month, enter Rent Paid and Electricity Paid, and confirm the summary before saving.',
              ),
              _GuidePoint(
                subtitle: 'Track Paid vs. Due Status',
                description:
                'In "Member Details", members who have cleared both their room rent and electricity share for the current month show "Paid". Any remaining balance shows clearly in red as "Due".',
              ),
              _GuidePoint(
                subtitle: 'Dashboard Overview',
                description:
                'Your home Dashboard automatically totals "Monthly Total Paid", "All-Time Paid", "Rooms Occupied", and "Current Total Dues" across all active members.',
              ),
            ],
          ),

          // Step 6: Meal Management
          _buildGuideSection(
            stepNumber: '6',
            title: 'Daily Meal & Bazar Tracking',
            icon: Icons.restaurant_menu,
            color: Colors.deepOrange,
            items: [
              _GuidePoint(
                subtitle: 'Log Daily Meals & Deposits',
                description:
                'Use the "Manage Meal" card on the Dashboard to record daily meal counts (Breakfast, Lunch, Dinner), bazar expenses, and member meal deposits.',
              ),
              _GuidePoint(
                subtitle: 'Automatic Meal Rate Calculation',
                description:
                'The meal manager divides total bazar costs by total meals consumed to compute the exact meal rate and individual member meal balances.',
              ),
            ],
          ),

          // Step 7: Offline Mode & Sync
          _buildGuideSection(
            stepNumber: '7',
            title: 'Offline Support & Auto-Sync',
            icon: Icons.cloud_sync,
            color: Colors.blueGrey,
            items: [
              _GuidePoint(
                subtitle: 'View Data Without Internet',
                description:
                'Your dashboard stats, room lists, member profiles, and bill histories are cached locally. When offline, an orange "OFFLINE" badge appears so you can still check records anytime.',
              ),
              _GuidePoint(
                subtitle: 'Offline Payment Queuing',
                description:
                'If you record a payment while offline, it saves safely on your device and syncs automatically to the cloud once your internet connection returns. Pull down on any screen to refresh.',
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Pro Tips Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Best Practices for Accurate Dues',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• Enter all electricity meter bills for the month before collecting final monthly payments so the per-member share is up to date.\n'
                      '• Always verify the confirmation popup before saving a payment to avoid duplicate monthly entries.\n'
                      '• Archive departing members only after settling their final dues and advance refunds.',
                  style: TextStyle(fontSize: 12, height: 1.45, color: Colors.black87),
                ),
              ],
            ),
          ),

          const SizedBox(height: 70),
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

  Widget _buildGuideSection({
    required String stepNumber,
    required String title,
    required IconData icon,
    required Color color,
    required List<_GuidePoint> items,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: stepNumber == '1' || stepNumber == '2',
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Step $stepNumber',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: items.map((point) {
            return Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.subtitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          point.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _GuidePoint {
  final String subtitle;
  final String description;

  const _GuidePoint({
    required this.subtitle,
    required this.description,
  });
}