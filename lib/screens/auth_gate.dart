import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart'; // <-- Added this import
import 'register_screen.dart';
import './main_navigation.dart';
import 'verification_screen.dart'; // <-- We will build this file next!

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            ),
          );
        }

        final session = snapshot.data?.session;

        if (session != null) {
          // USER IS LOGGED IN! Now, let's ask the database if they are verified.
          return FutureBuilder<bool>(
            future: AuthService().isUserVerified(),
            builder: (context, verifySnapshot) {
              if (verifySnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple),
                  ),
                );
              }

              final isVerified = verifySnapshot.data ?? false;

              if (isVerified) {
                // The database says true! Welcome in.
                return const MainNavigation();
              } else {
                // The database says false. Send them to the document upload screen.
                return const VerificationScreen();
              }
            },
          );
        } else {
          // No session found, show the login screen
          return const RegisterScreen();
        }
      },
    );
  }
}
