import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth/login_page.dart';
import 'home/home_dashboard.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } on FirebaseException catch (error) {
    debugPrint('Firebase is not configured yet: ${error.message}');
  } catch (error) {
    debugPrint('Authentication setup is incomplete: $error');
  }

  if (firebaseReady) {
    try {
      await GoogleSignIn.instance.initialize();
    } on GoogleSignInException catch (error) {
      debugPrint('Google Sign-In could not initialize: ${error.description}');
    } catch (error) {
      debugPrint('Google Sign-In setup is incomplete: $error');
    }
  }

  runApp(CbpakApp(firebaseReady: firebaseReady));
}

class CbpakApp extends StatelessWidget {
  const CbpakApp({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBPAK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          primary: AppColors.blue,
          secondary: AppColors.orange,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          hintStyle: const TextStyle(color: Color(0xFF9AA3B2)),
          prefixIconColor: const Color(0xFF738097),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E9EF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E9EF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD94A4A)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD94A4A), width: 1.5),
          ),
        ),
      ),
      home: AuthGate(firebaseReady: firebaseReady),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({required this.firebaseReady, super.key});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return const LoginPage(firebaseReady: false);
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage(firebaseReady: true);
        }

        return SignedInPage(user: user);
      },
    );
  }
}

class SignedInPage extends StatelessWidget {
  const SignedInPage({required this.user, super.key});
  final User user;
  @override
  Widget build(BuildContext context) => HomeDashboard(user: user);
}
