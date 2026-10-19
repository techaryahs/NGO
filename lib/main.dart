import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ngo/config/app_config.dart';
import 'package:ngo/screens/auth/auth_wrapper.dart';
import 'package:ngo/services/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load configuration from root .env asset
  await dotenv.load(fileName: '.env');

  // 2. Validate configuration before any services initialize
  AppConfig.validate();

  // 3. Initialize services with authoritative configuration from .env
  final services = ServiceLocator();
  services.initialize(
    projectId: AppConfig.firebaseProjectId,
    apiKey: AppConfig.firebaseApiKey,
    databaseUrl: AppConfig.firebaseDatabaseUrl,
  );
  await services.initializePersistentCache();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NGO Management System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6D11)),
      ),
      home: const AuthWrapper(),
    );
  }
}
