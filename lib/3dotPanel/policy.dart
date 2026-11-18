import 'package:flutter/material.dart';
import 'package:mess_sur/admobs/ads_test_banner.dart';

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy & Policy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Row(
              children: [
                Icon(Icons.verified_user_rounded, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Terms & Data Policies',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Last updated: November 2026',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 32),

            // Section 1
            _buildSection(
              title: '1. Data Isolation & Security',
              content:
              'All mess records, member profiles, room allocations, and financial ledgers are securely scoped to individual users using strict multi-tenant RLS. Your data is encrypted.',
            ),
            const SizedBox(height: 20),

            // Section 2
            _buildSection(
              title: '2. User Authentication',
              content:
              'Access to the platform is authenticated via secure tokens and verification methods. Users are responsible for maintaining the confidentiality of their login credentials and managing authorized access to their respective mess infrastructure.',
            ),
            const SizedBox(height: 20),

            // Section 3
            _buildSection(
              title: '3. Financial & Room Management',
              content:
              'Room configurations, advance deposits, and payment tracking features are provided for administrative convenience. Managers must ensure accuracy when logging member transactions and updating floor allocations.',
            ),
            const SizedBox(height: 20),

            // Section 4
            _buildSection(
              title: '4. System Updates & Support',
              content:
              'The application is continuously optimized for performance and reliability. For technical inquiries, bug reports, or administrative support, contact the system administrator directly.',
            ),
            const SizedBox(height: 32),

            // Footer Contact Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.support_agent, color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Need Assistance?',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Reach out to support at codninesx@gmail.com',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: MessTestBanner(),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}