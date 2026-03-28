class Validators {
  static String? validateEmailEdu(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required.';
    final ok = v.contains('edu');
    if (!ok) return 'Email must belong to an educational institution.';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    final v = value ?? '';
    if (v.isEmpty) return 'Confirm your password.';
    if (v != password) return 'Passwords do not match.';
    return null;
  }
}

