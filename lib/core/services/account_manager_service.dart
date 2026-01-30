import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BpsAccount {
  final String username;
  final String password;
  final String? name;
  
  // Runtime only property, not persisted
  DateTime? rateLimitUntil;

  BpsAccount({
    required this.username,
    required this.password,
    this.name,
    this.rateLimitUntil,
  });

  bool get isRateLimited {
    if (rateLimitUntil == null) return false;
    return DateTime.now().isBefore(rateLimitUntil!);
  }
  
  String get rateLimitStatus {
    if (!isRateLimited) return '';
    final diff = rateLimitUntil!.difference(DateTime.now());
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    return 'Limit: ${minutes}m ${seconds}s';
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'name': name,
  };

  factory BpsAccount.fromJson(Map<String, dynamic> json) {
    return BpsAccount(
      username: json['username'],
      password: json['password'],
      name: json['name'],
    );
  }
}

class AccountManagerService {
  static final AccountManagerService _instance =
      AccountManagerService._internal();

  factory AccountManagerService() {
    return _instance;
  }

  AccountManagerService._internal() {
    loadAccounts();
  }

  // Temporary in-memory list. In a real app, this should be secure storage.
  // User asked for "list akun", we can provide a way to add them.
  final List<BpsAccount> _accounts = [
    // Placeholder - user will need to add accounts via UI or code
  ];
  
  // Listeners for UI updates when limit status changes
  final List<VoidCallback> _listeners = [];
  
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }
  
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
  
  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  int _currentIndex = 0;

  List<BpsAccount> get accounts => List.unmodifiable(_accounts);

  void markAccountRateLimited(String username, Duration duration) {
    final index = _accounts.indexWhere((a) => a.username == username);
    if (index != -1) {
      _accounts[index].rateLimitUntil = DateTime.now().add(duration);
      debugPrint('Account $username rate limited until ${_accounts[index].rateLimitUntil}');
      _notifyListeners();
    }
  }

  BpsAccount? getNextAvailableAccount(String? currentUsername) {
    if (_accounts.isEmpty) return null;

    // Cari akun yang tidak limit dan bukan currentUsername
    // Kita coba cari mulai dari current index + 1
    int startIndex = 0;
    if (currentUsername != null) {
      final idx = _accounts.indexWhere((a) => a.username == currentUsername);
      if (idx != -1) {
        startIndex = (idx + 1) % _accounts.length;
      }
    }
    
    // Loop satu putaran penuh untuk mencari
    for (int i = 0; i < _accounts.length; i++) {
      final index = (startIndex + i) % _accounts.length;
      final account = _accounts[index];
      
      // Skip current user
      if (account.username == currentUsername) continue;
      
      // Check limit
      if (!account.isRateLimited) {
        _currentIndex = index; // Update current index
        return account;
      }
    }
    
    return null; // Semua akun limit atau cuma ada 1 akun dan sedang dipakai
  }
  
  bool get isAllAccountsRateLimited {
    if (_accounts.isEmpty) return false;
    return _accounts.every((a) => a.isRateLimited);
  }

  Future<void> loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('bps_accounts_list');
      if (data != null) {
        final List<dynamic> jsonList = jsonDecode(data);
        _accounts.clear();
        _accounts.addAll(jsonList.map((e) => BpsAccount.fromJson(e)).toList());
      }
    } catch (e) {
      debugPrint('Error loading accounts: $e');
    }
  }

  Future<void> _saveAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String data = jsonEncode(_accounts.map((e) => e.toJson()).toList());
      await prefs.setString('bps_accounts_list', data);
    } catch (e) {
      debugPrint('Error saving accounts: $e');
    }
  }

  Future<void> addAccount(
    String username,
    String password, {
    String? name,
  }) async {
    // Check if exists
    final exists = _accounts.any((a) => a.username == username);
    if (!exists) {
      _accounts.add(
        BpsAccount(username: username, password: password, name: name),
      );
      await _saveAccounts();
    }
  }

  Future<void> removeAccount(String username) async {
    _accounts.removeWhere((a) => a.username == username);
    if (_currentIndex >= _accounts.length) {
      _currentIndex = 0;
    }
    await _saveAccounts();
  }

  BpsAccount? get currentAccount {
    if (_accounts.isEmpty) return null;
    if (_currentIndex >= _accounts.length) _currentIndex = 0;
    return _accounts[_currentIndex];
  }

  BpsAccount? get nextAccount {
    if (_accounts.isEmpty) return null;
    _currentIndex = (_currentIndex + 1) % _accounts.length;
    return _accounts[_currentIndex];
  }

  void resetIndex() {
    _currentIndex = 0;
  }

  // Pre-fill with some dummy or user provided accounts if any
  void setAccounts(List<BpsAccount> newAccounts) {
    _accounts.clear();
    _accounts.addAll(newAccounts);
    _currentIndex = 0;
  }
}
