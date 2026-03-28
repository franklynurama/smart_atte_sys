import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

/// Central place for Firebase initialization.
/// You can later expand this to use platform-specific options if needed.
class FirebaseConfig {
  static Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

