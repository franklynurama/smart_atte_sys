import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_textfield.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../providers/auth_provider.dart';
import '../../../../routes/app_routes.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController emailController;
  late final TextEditingController passwordController;

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    passwordController = TextEditingController();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final mutationState = ref.watch(authMutationProvider);
    final authStatus = ref.watch(authStatusProvider);

    ref.listen(authStatusProvider, (previous, next) {
      final user = next.value;
      if (user != null && context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
      }
    });

    String? emailValidator(String? v) {
      final value = v?.trim() ?? '';
      if (value.isEmpty) return 'Email is required.';
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(value)) return 'Enter a valid email address.';
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: authStatus.when(
        loading: () => const LoadingIndicator(text: 'Checking authentication...'),
        error: (e, _) => SafeArea(
          child: Center(
            child: Text(
              'Authentication error: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Welcome back.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'Email',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: emailValidator,
                    hintText: 'yourname@university.edu',
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Password',
                    controller: passwordController,
                    isPassword: true,
                    validator: Validators.validatePassword,
                  ),
                  const SizedBox(height: 16),
                  if (mutationState.errorMessage != null) ...[
                    Text(
                      mutationState.errorMessage!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  CustomButton(
                    label: 'Login',
                    icon: Icons.login,
                    isLoading: mutationState.isLoading,
                    onPressed: () async {
                      if (_formKey.currentState?.validate() != true) return;
                      await ref.read(authMutationProvider.notifier).login(
                            email: emailController.text.trim(),
                            password: passwordController.text,
                          );
                    },
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.signup);
                    },
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

