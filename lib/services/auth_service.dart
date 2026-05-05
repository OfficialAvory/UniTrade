import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Opens the secure Google Login browser
  Future<void> signInWithGoogle() async {
    // 1. Determine exactly where we are right now
    String? webRedirectUrl;
    if (kIsWeb) {
      // If we are testing on our computer, go to localhost.
      // Otherwise, go to the live GitHub site!
      webRedirectUrl =
          kDebugMode
              ? 'http://localhost:3000'
              : 'https://OfficialAvory.github.io/UniTrade/';
    }

    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? webRedirectUrl : 'avory://login-callback',
    );
  }

  /// Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Checks if the current logged-in user is verified
  Future<bool> isUserVerified() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      // Assuming your table is called 'profiles'. Change to 'users' if needed.
      final data =
          await _supabase
              .from('profiles')
              .select('is_verified')
              .eq('id', user.id)
              .single();

      return data['is_verified'] == true;
    } catch (e) {
      debugPrint('Error fetching verification status: $e');
      // If there's an error (e.g., profile doesn't exist yet), assume they are unverified
      return false;
    }
  }
}
