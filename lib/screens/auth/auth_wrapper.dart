import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/services/firebase_auth_rest_service.dart';
import 'package:ngo/screens/auth/login_screen.dart';
import 'package:ngo/screens/layout/main_layout.dart';
import 'package:ngo/screens/layout/staff_layout.dart';
import 'package:ngo/screens/layout/volunteer_layout.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final Stream<AuthUser?> _authStateChanges;
  String? _cachedUid;
  Future<String?>? _roleFuture;

  @override
  void initState() {
    super.initState();
    _authStateChanges = ServiceLocator().authService.authStateChanges;
  }

  Future<String?> _roleForUser(String uid) {
    if (_cachedUid != uid || _roleFuture == null) {
      _cachedUid = uid;
      _roleFuture = ServiceLocator().authService.getUserRole(uid);
    }
    return _roleFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      // Only the cache-aware stream may release authenticated UI. Seeding
      // currentUser here bypasses account activation during restored login.
      stream: _authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final uid = snapshot.data!.uid;
          return FutureBuilder<String?>(
            future: _roleForUser(uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
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
                        TextButton(
                          onPressed: () => setState(() => _roleFuture = null),
                          child: const Text('Retry'),
                        ),
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

              // An unknown or temporarily unavailable role has no admin UI.
              final role = roleSnapshot.data ?? 'volunteer';

              switch (role) {
                case 'admin':
                  return const MainLayout();
                case 'staff':
                  return const StaffLayout();
                case 'volunteer':
                  return const VolunteerLayout();
                default:
                  return const VolunteerLayout();
              }
            },
          );
        }

        _cachedUid = null;
        _roleFuture = null;
        return const LoginScreen();
      },
    );
  }
}
