import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_models.dart';
import 'auth_service.dart';
import 'auth_session.dart';

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
    if (currentUser!.role == UserRole.SYSTEM_ADMIN) return true;
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
    AuthSession.onUnauthorized = logout;
    init();
  }

  Future<void> init() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final storedToken = prefs.getString(kTokenKey);
      final storedUserRaw = prefs.getString(kCurrentUserKey);

      if (storedToken != null && storedToken.isNotEmpty) {
        AuthSession.token = storedToken;
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

        if (_authService != null) {
          try {
            await fetchCurrentUser();
          } catch (_) {
            await logout();
          }
        }
      } else {
        state = state.copyWith(isInitialized: true);
      }
    } catch (_) {
      state = state.copyWith(isInitialized: true);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      if (_authService != null) {
        final res =
            await _authService!.login({'email': email, 'password': password});
        saveSession(res.token);

        // NOTE: don't trust `res.user` even when present — some roles (e.g.
        // CLINIC_ADMIN / SYSTEM_ADMIN) can come back from /auth/login with a
        // partial user object that has no `role` field, which UserModel then
        // silently defaults to UserRole.PATIENT. That was routing admins
        // into the patient dashboard. /users/me is the source of truth for
        // the full profile (role included), same as the Angular reference
        // (auth.service.ts always does login().pipe(switchMap(fetchCurrentUser))),
        // so always resolve it here instead of branching on res.user.
        await fetchCurrentUser();
        return;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> register(Map<String, dynamic> payload) async {
    state = state.copyWith(isLoading: true);
    try {
      if (_authService != null) {
        final res = await _authService!.register(payload);
        saveSession(res.token);

        // Same reasoning as login(): always hydrate from /users/me so role
        // is never silently defaulted.
        await fetchCurrentUser();
        return;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> updateUserProfile(Map<String, dynamic> dto) async {
    state = state.copyWith(isLoading: true);
    try {
      if (_authService != null) {
        final updatedUser = await _authService!.updateUserProfile(dto);
        state = state.copyWith(currentUser: updatedUser, isLoading: false);
        try {
          final prefs = _prefs ?? await SharedPreferences.getInstance();
          await prefs.setString(kCurrentUserKey, jsonEncode(updatedUser.toJson()));
        } catch (_) {}
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
      print('AuthNotifier.fetchCurrentUser failed, currentUser stays null: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> logout() async {
    state = AuthState(isInitialized: true);
    AuthSession.token = null;
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove(kTokenKey);
      await prefs.remove(kCurrentUserKey);
    } catch (_) {}
  }

  void saveSession(String token) {
    state = state.copyWith(token: token);
    AuthSession.token = token;
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
