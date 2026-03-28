import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/firebase_config.dart';
import 'routes/app_routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseConfig.init();

  runApp(const ProviderScope(child: SmartAtteApp()));
}

class SmartAtteApp extends ConsumerWidget {
  const SmartAtteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = AppRoutes.router;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Attendance',
      initialRoute: AppRoutes.login,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      onGenerateRoute: router,
    );
  }
}

