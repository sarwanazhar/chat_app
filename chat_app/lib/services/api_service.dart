import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ApiService {
  final String baseUrl;
  final StorageService _storage = StorageService();

  ApiService({this.baseUrl = 'http://10.0.2.2:4000/api'});

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Registration failed');
    }
    return data;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Login failed');
    }
    return data;
  }

  Future<List<dynamic>> getRooms() async {
    final headers = await _headers();
    final res = await http.get(Uri.parse('$baseUrl/rooms'), headers: headers);
    if (res.statusCode >= 400) {
      throw Exception('Failed to fetch rooms');
    }
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createRoom(String name) async {
    final headers = await _headers();
    final res = await http.post(
      Uri.parse('$baseUrl/rooms'),
      headers: headers,
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode >= 400) {
      throw Exception('Failed to create room');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
