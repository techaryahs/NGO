import 'dart:io';
import 'package:file_picker/file_picker.dart';

String _getUniqueFilePath(String folder, String fileName) {
  final dotIndex = fileName.lastIndexOf('.');

  final baseName = dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);

  final extension = dotIndex == -1 ? '' : fileName.substring(dotIndex);

  String path = '$folder/$fileName';
  int count = 1;

  while (File(path).existsSync()) {
    path = '$folder/${baseName}($count)$extension';
    count++;
  }

  return path;
}

Future<String?> savePatientInfoWorkbook({
  required List<int> bytes,
  required String fileName,
}) async {
  final folder = await FilePicker.platform.getDirectoryPath();

  if (folder == null) {
    return null;
  }

  final finalName = fileName.endsWith('.xlsx') ? fileName : '$fileName.xlsx';

  // Create unique filename if file already exists
  final uniquePath = _getUniqueFilePath(folder, finalName);

  final file = File(uniquePath);

  await file.writeAsBytes(bytes, flush: true);

  return uniquePath;
}
