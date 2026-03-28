import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_textfield.dart';
import '../../../../core/widgets/loading_indicator.dart';
import '../providers/auth_provider.dart';
import '../../../../routes/app_routes.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController passwordController;
  late final TextEditingController confirmPasswordController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    emailController = TextEditingController();
    passwordController = TextEditingController();
    confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: authStatus.when(
        loading: () => const LoadingIndicator(text: 'Checking authentication...'),
        error: (e, _) => SafeArea(
          child: Center(
            child: Text('Authentication error: $e', textAlign: TextAlign.center),
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
                    'Create your account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    label: 'Name',
                    controller: nameController,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return 'Name is required.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Email',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmailEdu,
                    hintText: 'yourname@university.edu',
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Password',
                    controller: passwordController,
                    isPassword: true,
                    validator: Validators.validatePassword,
                  ),
                  const SizedBox(height: 12),
                  CustomTextField(
                    label: 'Confirm Password',
                    controller: confirmPasswordController,
                    isPassword: true,
                    validator: (v) => Validators.validateConfirmPassword(v, passwordController.text),
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
                    label: 'Create Account',
                    icon: Icons.person_add,
                    isLoading: mutationState.isLoading,
                    onPressed: () async {
                      if (_formKey.currentState?.validate() != true) return;
                      await ref.read(authMutationProvider.notifier).signup(
                            name: nameController.text.trim(),
                            email: emailController.text.trim(),
                            password: passwordController.text,
                            confirmPassword: confirmPasswordController.text,
                          );
                    },
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
                    child: const Text('Already have an account? Login'),
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

