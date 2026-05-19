import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:url_launcher/url_launcher.dart';

/// Helper utility for exporting NGO expense data to CSV, Excel, and HTML/PDF
class ExportUtility {
  /// Export data rows to a standard CSV file using a native save-file dialog.
  static Future<void> exportToCSV({
    required BuildContext context,
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String defaultFileName,
  }) async {
    try {
      // 1. Generate CSV content
      final csvBuffer = StringBuffer();
      
      // Write headers
      csvBuffer.writeln(headers.map((h) => '"${h.replaceAll('"', '""')}"').join(','));
      
      // Write rows
      for (final row in rows) {
        csvBuffer.writeln(row.map((val) {
          final str = val?.toString() ?? '';
          return '"${str.replaceAll('"', '""')}"';
        }).join(','));
      }
      
      // 2. Open Save File Dialog
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Report',
        fileName: defaultFileName.endsWith('.csv') ? defaultFileName : '$defaultFileName.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );

      if (outputPath == null) return; // User cancelled

      // 3. Write file
      final file = File(outputPath);
      await file.writeAsString(csvBuffer.toString());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported to $outputPath'),
            backgroundColor: const Color(0xFF3B6D11),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting CSV: $e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  /// Export data rows to an Excel workbook using a native save-file dialog.
  static Future<void> exportToExcel({
    required BuildContext context,
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String defaultFileName,
  }) async {
    try {
      // 1. Generate Excel content
      final excel = Excel.createExcel();
      final sheet = excel[sheetName];
      
      // Append headers
      sheet.appendRow(headers.map((h) => TextCellValue(h.toString())).toList());
      
      // Append rows
      for (final row in rows) {
        sheet.appendRow(row.map((val) {
          final strVal = val?.toString() ?? '';
          final doubleVal = double.tryParse(strVal);
          if (doubleVal != null) {
            if (doubleVal == doubleVal.toInt().toDouble()) {
              return IntCellValue(doubleVal.toInt());
            }
            return DoubleCellValue(doubleVal);
          }
          return TextCellValue(strVal);
        }).toList());
      }
      
      // Delete default 'Sheet1' if it's different to prevent empty tabs
      if (sheetName != 'Sheet1') {
        excel.delete('Sheet1');
      }

      // 2. Open Save File Dialog
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel Report',
        fileName: defaultFileName.endsWith('.xlsx') ? defaultFileName : '$defaultFileName.xlsx',
        allowedExtensions: ['xlsx'],
        type: FileType.custom,
      );

      if (outputPath == null) return; // User cancelled

      // 3. Save bytes
      final bytes = excel.save();
      if (bytes != null) {
        final file = File(outputPath);
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported to $outputPath'),
            backgroundColor: const Color(0xFF3B6D11),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting Excel: $e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }

  /// Generate a high-fidelity styled HTML document and launch it in the browser for print-to-PDF.
  static Future<void> exportToPDF({
    required BuildContext context,
    required String reportTitle,
    required String subtitle,
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String defaultFileName,
  }) async {
    try {
      // 1. Generate HTML with Premium Green Theme Styling
      final htmlBuffer = StringBuffer();
      final now = DateTime.now();
      final timestamp = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

      htmlBuffer.write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$reportTitle</title>
  <style>
    body {
      font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, Roboto, sans-serif;
      color: #27500A;
      margin: 40px;
      padding: 0;
      background-color: #ffffff;
    }
    .header-container {
      border-bottom: 2px solid #3B6D11;
      padding-bottom: 20px;
      margin-bottom: 30px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .title-block h1 {
      margin: 0;
      font-size: 26px;
      color: #3B6D11;
      font-weight: 600;
    }
    .title-block p {
      margin: 5px 0 0 0;
      font-size: 14px;
      color: #639922;
    }
    .meta-block {
      text-align: right;
      font-size: 12px;
      color: #757575;
    }
    .meta-block p {
      margin: 4px 0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 10px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    }
    th {
      background-color: #F4F9F0;
      color: #27500A;
      font-weight: 600;
      text-align: left;
      padding: 12px 14px;
      border: 1px solid #C0DD97;
      font-size: 13px;
    }
    td {
      padding: 10px 14px;
      border: 1px solid #E2EED3;
      font-size: 13px;
      color: #333333;
    }
    tr:nth-child(even) {
      background-color: #FAFDF7;
    }
    .footer {
      margin-top: 50px;
      border-top: 1px solid #E2EED3;
      padding-top: 15px;
      text-align: center;
      font-size: 11px;
      color: #888888;
    }
    .badge {
      display: inline-block;
      padding: 3px 8px;
      border-radius: 4px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
    }
    .badge-paid { background-color: #E8F5E9; color: #2E7D32; }
    .badge-pending { background-color: #FFEBEE; color: #C62828; }
    .badge-partial { background-color: #FFF8E1; color: #F57F17; }
    
    @media print {
      body { margin: 20px; }
      .no-print { display: none; }
    }
  </style>
</head>
<body>
  <div class="header-container">
    <div class="title-block">
      <h1>$reportTitle</h1>
      <p>$subtitle</p>
    </div>
    <div class="meta-block">
      <p><strong>NGO System</strong> Operations Portal</p>
      <p>Generated: $timestamp</p>
    </div>
  </div>

  <table>
    <thead>
      <tr>
''');

      for (final header in headers) {
        htmlBuffer.write('        <th>$header</th>\n');
      }

      htmlBuffer.write('''
      </tr>
    </thead>
    <tbody>
''');

      for (final row in rows) {
        htmlBuffer.write('      <tr>\n');
        for (final val in row) {
          final valStr = val?.toString() ?? '';
          
          // Style badges dynamically for visual excelence
          if (valStr == 'Paid') {
            htmlBuffer.write('        <td><span class="badge badge-paid">Paid</span></td>\n');
          } else if (valStr == 'Pending') {
            htmlBuffer.write('        <td><span class="badge badge-pending">Pending</span></td>\n');
          } else if (valStr == 'Partial') {
            htmlBuffer.write('        <td><span class="badge badge-partial">Partial</span></td>\n');
          } else {
            htmlBuffer.write('        <td>$valStr</td>\n');
          }
        }
        htmlBuffer.write('      </tr>\n');
      }

      htmlBuffer.write('''
    </tbody>
  </table>

  <div class="footer">
    <p>Confidential operational report for NGO administrative review. Generated securely within the NGO desktop application.</p>
  </div>
</body>
</html>
''');

      // 2. Write to a temporary file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${defaultFileName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}_${now.millisecondsSinceEpoch}.html');
      await tempFile.writeAsString(htmlBuffer.toString());

      // 3. Open in default system browser
      final uri = Uri.file(tempFile.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.print_rounded, color: Color(0xFF3B6D11)),
                  SizedBox(width: 10),
                  Text("Print PDF Report"),
                ],
              ),
              content: const Text(
                "Your styled print-preview report has been generated and opened in your web browser.\n\n"
                "Please press Cmd + P (on Mac) or Ctrl + P (on Windows) in the browser window to select 'Save as PDF' or print directly.",
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B6D11),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Could not launch print HTML report: ${tempFile.path}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF print preview: $e'),
            backgroundColor: const Color(0xFFD32F2F),
          ),
        );
      }
    }
  }
}
