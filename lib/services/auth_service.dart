import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Opens the secure Google Login browser
  Future<void> signInWithGoogle() async {
    String? webRedirectUrl;
    if (kIsWeb) {
      webRedirectUrl =
          kDebugMode
              ? 'http://localhost:3000'
              // FIX: Domain must be completely lowercase!
              : 'https://officialavory.github.io/UniTrade/';
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
      final data =
          await _supabase
              .from('profiles')
              .select('is_verified')
              .eq('id', user.id)
              .single();

      return data['is_verified'] == true;
    } catch (e) {
      debugPrint('Error fetching verification status: $e');
      return false;
    }
  }
}
