import 'package:flutter/foundation.dart'; // REQUIRED for kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Opens the secure Google Login browser
  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      // Smart Redirect: Uses default web routing for Chrome, and deep links for Android/iOS
      redirectTo: kIsWeb ? null : 'avory://login-callback',
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
