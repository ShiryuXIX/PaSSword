import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseSetup {
  static const projectId = 'gestor-pass-b60d6';
  static const apiKey = 'AIzaSyD8cvB7m7EvzjGsLlCmuu7mo-xfcvVBLj4';
  static const messagingSenderId = '899324045825';
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static bool get isConfigured =>
      androidAppId.startsWith('1:') &&
      androidAppId.contains(':android:') &&
      googleServerClientId.endsWith('.apps.googleusercontent.com');

  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'Falta configurar la aplicación Android y el cliente OAuth de Google.',
      );
    }

    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: apiKey,
        appId: androidAppId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      ),
    );
    await GoogleSignIn.instance.initialize(
      serverClientId: googleServerClientId,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }
}
