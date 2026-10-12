import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';

  Future<void> saveAuthData({
    required String token,
    required String userId,
    required String username,
  }) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyUsername, value: username);
  }

  Future<String?> getToken() async => await _storage.read(key: _keyToken);
  Future<String?> getUserId() async => await _storage.read(key: _keyUserId);
  Future<String?> getUsername() async => await _storage.read(key: _keyUsername);

  Future<void> clearAuthData() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyUsername);
  }
}
