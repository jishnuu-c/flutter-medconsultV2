import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_models.dart';
import 'auth_service.dart';

const String kTokenKey = 'medconsult_token';
const String kCurrentUserKey = 'medconsult_user';

class AuthState {
  final String? token;
  final UserModel? currentUser;
  final bool isLoading;
  final bool isInitialized;

  AuthState({
    this.token,
    this.currentUser,
    this.isLoading = false,
    this.isInitialized = false,
  });

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  bool hasRole(List<UserRole> roles) {
    if (currentUser == null) return false;
    return roles.contains(currentUser!.role);
  }

  AuthState copyWith({
    String? token,
    UserModel? currentUser,
    bool? isLoading,
    bool? isInitialized,
  }) {
    return AuthState(
      token: token ?? this.token,
      currentUser: currentUser ?? this.currentUser,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService? _authService;
  final SharedPreferences? _prefs;

  AuthNotifier({AuthService? authService, SharedPreferences? prefs})
      : _authService = authService,
        _prefs = prefs,
        super(AuthState()) {
    init();
  }

  Future<void> init() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final storedToken = prefs.getString(kTokenKey);
      final storedUserRaw = prefs.getString(kCurrentUserKey);

      if (storedToken != null && storedToken.isNotEmpty) {
        UserModel? user;
        if (storedUserRaw != null && storedUserRaw.isNotEmpty) {
          try {
            user = UserModel.fromJson(jsonDecode(storedUserRaw));
          } catch (_) {}
        }

        state = state.copyWith(
          token: storedToken,
          currentUser: user,
          isInitialized: true,
        );

        if (user == null && _authService != null) {
          await fetchCurrentUser();
        }
      } else {
        state = state.copyWith(isInitialized: true);
      }
    } catch (_) {
      state = state.copyWith(isInitialized: true);
    }
  }

  Future<void> login(String email, String password) async {
    if (_authService == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final res = await _authService!.login({'email': email, 'password': password});
      saveSession(res.token);

      if (res.user != null) {
        state = state.copyWith(currentUser: res.user, isLoading: false);
        try {
          final prefs = _prefs ?? await SharedPreferences.getInstance();
          await prefs.setString(kCurrentUserKey, jsonEncode(res.user!.toJson()));
        } catch (_) {}
      } else {
        await fetchCurrentUser();
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> register(Map<String, dynamic> payload) async {
    if (_authService == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final res = await _authService!.register(payload);
      saveSession(res.token);

      if (res.user != null) {
        state = state.copyWith(currentUser: res.user, isLoading: false);
        try {
          final prefs = _prefs ?? await SharedPreferences.getInstance();
          await prefs.setString(kCurrentUserKey, jsonEncode(res.user!.toJson()));
        } catch (_) {}
      } else {
        await fetchCurrentUser();
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> fetchCurrentUser() async {
    if (_authService == null) return;
    try {
      final user = await _authService!.fetchCurrentUser();
      state = state.copyWith(currentUser: user, isLoading: false);
      try {
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        await prefs.setString(kCurrentUserKey, jsonEncode(user.toJson()));
      } catch (_) {}
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> logout() async {
    state = AuthState(isInitialized: true);
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove(kTokenKey);
      await prefs.remove(kCurrentUserKey);
    } catch (_) {}
  }

  void saveSession(String token) {
    state = state.copyWith(token: token);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(kTokenKey, token);
    }).catchError((_) {});
  }
}

final StateNotifierProvider<AuthNotifier, AuthState> authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService: authService);
});
