import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import './main_navigation.dart';

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
          final email = session.user.email ?? '';

          // THE BOUNCER: Check if it's a valid university email OR a developer VIP email
          if (email.endsWith('.ac.ae') ||
              email.endsWith('.ac.uk') ||
              email == 'kjzapier@gmail.com' ||
              email == 'iamavorythegreat@gmail.com' ||
              email == 'business.avory@gmail.com') {
            // <--- ADD YOUR EMAIL HERE
            return const MainNavigation(); // <-- CHANGE THIS LINE! // Welcome in!
          } else {
            // Access Denied Screen
            return Scaffold(
              backgroundColor: const Color(0xFFFAFAFA),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.gpp_bad_rounded,
                        color: Colors.redAccent,
                        size: 80,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Access Denied',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Avory is exclusive to verified university students. The email you used ($email) is not a valid student account.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed: () async {
                          // Log them out so they can try again with a school email
                          await Supabase.instance.client.auth.signOut();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Log Out & Try Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        } else {
          // No session found, show the login screen
          return const RegisterScreen();
        }
      },
    );
  }
}
