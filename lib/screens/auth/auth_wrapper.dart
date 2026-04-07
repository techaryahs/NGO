import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ngo/services/auth_service.dart';
import 'package:ngo/screens/auth/login_screen.dart';
import 'package:ngo/screens/layout/main_layout.dart';
import 'package:ngo/screens/layout/staff_layout.dart';
import 'package:ngo/screens/layout/volunteer_layout.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF3B6D11),
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return FutureBuilder<String?>(
            future: AuthService().getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF3B6D11),
                    ),
                  ),
                );
              }

              // Role-based routing
              final role = roleSnapshot.data;
              switch (role) {
                case 'admin':
                  return const MainLayout();
                case 'staff':
                  return const StaffLayout();
                case 'volunteer':
                  return const VolunteerLayout();
                default:
                  return const LoginScreen();
              }
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
