import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://ngo-app-31653-default-rtdb.firebaseio.com/attendance/daily.json';
  final response = await http.get(Uri.parse(url));
  print(response.body);
}
