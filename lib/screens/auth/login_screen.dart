import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';
import 'package:ngo/screens/auth/signup_screen.dart';
import 'package:ngo/screens/auth/auth_wrapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showSnackBar("Please fill in all fields", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final result = await ServiceLocator().authService.signIn(
      email: emailController.text.trim(),
      password: passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }

    if (result['success']) {
      if (mounted) {
        _showSnackBar("Login Successful", isError: false);
        // Wait a moment for the snackbar to show, then navigate
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          // Navigate to AuthWrapper which will determine the correct layout
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AuthWrapper()),
          );
        }
      }
    } else {
      _showSnackBar(result['message'], isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF3B6D11),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Nature gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8F5E0),
                  Color(0xFFD4ECD9),
                  Color(0xFFC6E4D0),
                ],
              ),
            ),
          ),

          // Decorative leaf blobs
          Positioned(
            top: -60,
            left: -60,
            child: _LeafBlob(size: 220, color: const Color(0xFF3B6D11), rotation: 0.5),
          ),
          Positioned(
            bottom: -40,
            right: -40,
            child: _LeafBlob(size: 160, color: const Color(0xFF0F6E56), rotation: -0.35),
          ),
          Positioned(
            bottom: 120,
            left: 20,
            child: _LeafBlob(size: 90, color: const Color(0xFF639922), rotation: 1.0),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF639922).withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF3DE),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFC0DD97),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: Color(0xFF3B6D11),
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Title
                      const Text(
                        "NGO Management System",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B6D11),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Non Government Organization",
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF639922),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Email field
                      _NatureInputField(
                        controller: emailController,
                        label: "Email Address",
                        hint: "Enter email address",
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      _NatureInputField(
                        controller: passwordController,
                        label: "Password",
                        hint: "Enter password",
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFF639922),
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF639922),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                          child: const Text(
                            "Forgot password?",
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Divider
                      const Divider(color: Color(0xFFC0DD97), thickness: 0.5),
                      const SizedBox(height: 16),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : login,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: Text(
                            _isLoading ? "Signing in..." : "Sign in",
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B6D11),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sign up link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(fontSize: 13, color: Color(0xFF639922)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SignupScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF3B6D11),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              "Sign up",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Footer note
                      const Text(
                        "Secure access · Patient data protected",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable input field ─────────────────────────────────────────────────────

class _NatureInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;

  const _NatureInputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF27500A),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: Color(0xFF27500A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: const Color(0xFF97C459).withOpacity(0.8), fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF639922), size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF4F9F0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC0DD97), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF639922), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Decorative leaf blob ─────────────────────────────────────────────────────

class _LeafBlob extends StatelessWidget {
  final double size;
  final Color color;
  final double rotation;

  const _LeafBlob({required this.size, required this.color, required this.rotation});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(size * 0.5),
            bottomRight: Radius.circular(size * 0.5),
          ),
        ),
      ),
    );
  }
}
