import 'package:flutter/material.dart';
import 'package:ngo/services/service_locator.dart';

class AdminTestPage extends StatefulWidget {
  const AdminTestPage({super.key});

  @override
  State<AdminTestPage> createState() => _AdminTestPageState();
}

class _AdminTestPageState extends State<AdminTestPage> {
  List<Map<String, dynamic>> admins = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAdmins();
  }

  Future<void> fetchAdmins() async {
    try {
      final data = await ServiceLocator().authService.getAllAdmins();

      setState(() {
        admins = data;
        isLoading = false;
      });
    } catch (e) {
      print(e);
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Users"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : admins.isEmpty
          ? const Center(
        child: Text("No admin found"),
      )
          : ListView.builder(
        itemCount: admins.length,
        itemBuilder: (context, index) {
          final admin = admins[index];

          return ListTile(
            title: Text(admin['name'] ?? 'No Name'),
            subtitle: Text(admin['email'] ?? 'No Email'),
            trailing: Text(admin['role']),
          );
        },
      ),
    );
  }
}