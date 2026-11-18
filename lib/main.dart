import 'package:flutter/material.dart';
import 'package:mess_sur/dashboard/dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'signin/otp_login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qemnvggvsleaayfkesdy.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlbW52Z2d2c2xlYWF5Zmtlc2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEwOTc3MTIsImV4cCI6MjA4NjY3MzcxMn0.Qj6h_h9xUIj2-Ex8Xf72kkIfXQw94367CZxeKlarXGw',
  );

  runApp(const MessManagerApp());
}

class MessManagerApp extends StatelessWidget {
  const MessManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    // Only skip login if a real email-authenticated user session exists
    final isAuthenticated = user != null && !user.isAnonymous;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mess & Hostel Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: isAuthenticated ? const DashboardScreen() : const OtpLoginScreen(),
    );
  }
}