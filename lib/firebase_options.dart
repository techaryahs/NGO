// This file is intentionally kept as a compatibility shim.
//
// All application and Firebase configuration is managed by:
//
//   lib/config/app_config.dart
//
// which reads values directly from the root `.env` file via flutter_dotenv.
//
// There is exactly ONE source of configuration (.env) and ONE access layer (AppConfig).

export 'config/app_config.dart';
