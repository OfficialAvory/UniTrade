import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Needed for HapticFeedback
import 'dart:ui';
import 'dart:math' as math; // Needed for the floating math
import '../services/auth_service.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

// Added TickerProviderStateMixin for animations
class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  bool _isLoading = false;

  // Animation Controllers
  late AnimationController _entranceController;
  late AnimationController _floatingController;

  @override
  void initState() {
    super.initState();

    // 1. Entrance Animation (Runs once on load)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _entranceController.forward();

    // 2. Floating Background Animation (Loops continuously)
    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    // Add a light haptic tap for a premium tactile feel
    HapticFeedback.lightImpact();

    setState(() => _isLoading = true);
    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(e.toString())),
              ],
            ),
            backgroundColor: kPremiumRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper method for staggered slide-up animations
  Widget _buildAnimatedWidget({
    required Widget child,
    required double startDelay,
  }) {
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(startDelay, 1.0, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2), // Starts slightly lower
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kBackground,
      body: Stack(
        children: [
          // Animated Background Blob 1
          AnimatedBuilder(
            animation: _floatingController,
            builder: (context, child) {
              return Positioned(
                top:
                    -100 + (math.sin(_floatingController.value * math.pi) * 20),
                right:
                    -100 + (math.cos(_floatingController.value * math.pi) * 10),
                child: child!,
              );
            },
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPremiumRed.withOpacity(0.12),
              ),
            ),
          ),

          // Animated Background Blob 2
          AnimatedBuilder(
            animation: _floatingController,
            builder: (context, child) {
              return Positioned(
                bottom:
                    -50 + (math.cos(_floatingController.value * math.pi) * 20),
                left:
                    -100 + (math.sin(_floatingController.value * math.pi) * 15),
                child: child!,
              );
            },
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF5350).withOpacity(0.1),
              ),
            ),
          ),

          // Glassmorphism effect over the blobs
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0),
            child: Container(color: Colors.transparent),
          ),

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: size.height * 0.12),

                    // Staggered Item 1: Logo
                    _buildAnimatedWidget(
                      startDelay: 0.0,
                      child: Center(
                        child: Container(
                          height: 90,
                          width: 90,
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: kPremiumRed.withOpacity(0.15),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: LinearGradient(
                                    colors: [
                                      kPremiumRed.withOpacity(0.08),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.school_rounded,
                                color: kPremiumRed,
                                size: 48,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Staggered Item 2: Typography
                    _buildAnimatedWidget(
                      startDelay: 0.2,
                      child: Column(
                        children: [
                          const Text(
                            'Join UniTrade',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              color: kTextPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'The exclusive marketplace for verified university students to buy, sell, and rent.',
                            style: TextStyle(
                              fontSize: 16,
                              color: kTextSecondary,
                              height: 1.5,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.06),

                    // Staggered Item 3: Trust Indicators
                    _buildAnimatedWidget(
                      startDelay: 0.4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildTrustBadge(
                            Icons.verified_user_rounded,
                            'Verified',
                          ),
                          _buildTrustBadge(
                            Icons.lock_outline_rounded,
                            'Secure',
                          ),
                          _buildTrustBadge(Icons.local_offer_rounded, 'Local'),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.08),

                    // Staggered Item 4: Button & Footer
                    _buildAnimatedWidget(
                      startDelay: 0.6,
                      child: Column(
                        children: [
                          _buildGoogleButton(),
                          const SizedBox(height: 32),
                          const Text(
                            'By continuing, you agree to UniTrade\'s\nTerms of Service & Privacy Policy',
                            style: TextStyle(
                              fontSize: 13,
                              color: kTextSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadge(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kSurface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: kPremiumRed, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: kTextPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _signInWithGoogle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
            ),
            child:
                _isLoading
                    ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: kPremiumRed,
                          strokeWidth: 3,
                        ),
                      ),
                    )
                    : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}
