import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/services/firebase_auth_rest_service.dart';
import 'package:ngo/screens/auth/login_screen.dart';
import 'package:ngo/screens/layout/main_layout.dart';
import 'package:ngo/screens/layout/staff_layout.dart';
import 'package:ngo/screens/layout/volunteer_layout.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: ServiceLocator().authRestService.authStateChanges,
      initialData: null, // Add initial data to prevent waiting
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF3B6D11),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<String?>(
            future: ServiceLocator().authService.getUserRole(snapshot.data!.uid),
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

              // If there's an error fetching role, show error
              if (roleSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Color(0xFFD32F2F),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading user data',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          roleSnapshot.error.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () async {
                            await ServiceLocator().authService.signOut();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B6D11),
                          ),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Role-based routing - default to admin if role not found
              final role = roleSnapshot.data ?? 'admin';
              
              print('User role: $role'); // Debug print
              
              switch (role) {
                case 'admin':
                  return const MainLayout();
                case 'staff':
                  return const StaffLayout();
                case 'volunteer':
                  return const VolunteerLayout();
                default:
                  // If role is not recognized, default to admin
                  return const MainLayout();
              }
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}
