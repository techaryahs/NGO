import 'dart:html' as html;

Future<String?> savePatientInfoWorkbook({
  required List<int> bytes,
  required String fileName,
}) async {
  final normalizedFileName = fileName.toLowerCase().endsWith('.xlsx')
      ? fileName
      : '$fileName.xlsx';
  final blob = html.Blob([
    bytes,
  ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = normalizedFileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  return normalizedFileName;
}
