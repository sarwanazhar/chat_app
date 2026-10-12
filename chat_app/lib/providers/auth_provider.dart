import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  String? _token;
  String? _userId;
  String? _username;
  bool _isLoading = false;
  String? _error;

  String? get token => _token;
  String? get userId => _userId;
  String? get username => _username;
  bool get isAuthenticated => _token != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> tryAutoLogin() async {
    _token = await _storageService.getToken();
    _userId = await _storageService.getUserId();
    _username = await _storageService.getUsername();
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _apiService.login(username, password);
      _token = res['token'];
      _userId = res['user']['id'];
      _username = res['user']['username'];

      await _storageService.saveAuthData(
        token: _token!,
        userId: _userId!,
        username: _username!,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _apiService.register(username, password);
      _token = res['token'];
      _userId = res['user']['id'];
      _username = res['user']['username'];

      await _storageService.saveAuthData(
        token: _token!,
        userId: _userId!,
        username: _username!,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    await _storageService.clearAuthData();
    notifyListeners();
  }
}
