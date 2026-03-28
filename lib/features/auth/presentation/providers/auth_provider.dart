import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/auth_service.dart';

class AuthMutationState {
  final bool isLoading;
  final String? errorMessage;

  const AuthMutationState({
    required this.isLoading,
    required this.errorMessage,
  });

  factory AuthMutationState.initial() {
    return const AuthMutationState(isLoading: false, errorMessage: null);
  }
}

class AuthMutationNotifier extends StateNotifier<AuthMutationState> {
  final AuthService _service = AuthService();

  AuthMutationNotifier() : super(AuthMutationState.initial());

  Future<void> signup({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (password != confirmPassword) {
      state = const AuthMutationState(isLoading: false, errorMessage: 'Passwords do not match.');
      return;
    }

    if (!email.contains('edu')) {
      state = const AuthMutationState(
        isLoading: false,
        errorMessage: 'Email must belong to an educational institution.',
      );
      return;
    }

    state = const AuthMutationState(isLoading: true, errorMessage: null);
    try {
      await _service.signup(name: name, email: email, password: password);
      state = AuthMutationState.initial();
    } catch (e) {
      state = AuthMutationState(isLoading: false, errorMessage: _friendlyError(e));
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AuthMutationState(isLoading: true, errorMessage: null);
    try {
      await _service.login(email: email, password: password);
      state = AuthMutationState.initial();
    } catch (e) {
      state = const AuthMutationState(isLoading: false, errorMessage: 'Login failed. Please check your credentials.');
    }
  }

  Future<void> logout() async {
    await _service.logout();
  }

  String _friendlyError(Object e) {
    return 'Signup failed: ${e.toString()}';
  }
}

class AuthStatusNotifier extends AsyncNotifier<User?> {
  final AuthService _service = AuthService();
  StreamSubscription<User?>? _sub;

  @override
  FutureOr<User?> build() {
    final initial = _service.currentUser;
    _sub = _service.authStateChanges().listen((user) {
      state = AsyncValue.data(user);
    });
    ref.onDispose(() => _sub?.cancel());
    return initial;
  }
}

/// Provides current Firebase `User?`. Updates automatically when auth state changes.
final authStatusProvider = AsyncNotifierProvider<AuthStatusNotifier, User?>(() => AuthStatusNotifier());

/// Provides transient loading/error state for login/signup actions.
final authMutationProvider =
    StateNotifierProvider<AuthMutationNotifier, AuthMutationState>((ref) => AuthMutationNotifier());

