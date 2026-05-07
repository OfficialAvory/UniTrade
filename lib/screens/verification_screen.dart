import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class VerificationScreen extends StatefulWidget {
  // Accept the pending status from AuthGate
  final bool isInitiallyPending;

  const VerificationScreen({
    super.key,
    this.isInitiallyPending = false,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with TickerProviderStateMixin {
  // FIXED: Use XFile instead of File (dart:io not supported on web)
  XFile? _selectedImage;
  bool _isUploading = false;
  late bool _isSubmitted;

  final _supabase = Supabase.instance.client;

  late AnimationController _entranceController;
  late AnimationController _floatingController;

  @override
  void initState() {
    super.initState();

    _isSubmitted = widget.isInitiallyPending;

    // Entrance Animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _entranceController.forward();

    // Background Floating Animation
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

  // Helper for staggered slide-up animations
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
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        // FIXED: Store as XFile directly — no File() wrapper
        _selectedImage = pickedFile;
      });
    }
  }

  void _removeImage() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _uploadDocument() async {
    if (_selectedImage == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${user.id}/proof_$timestamp.jpg';

      // FIXED: Read as bytes — works on ALL platforms (web, mobile, desktop)
      final bytes = await _selectedImage!.readAsBytes();

      // FIXED: Use uploadBinary with bytes instead of upload with File
      await _supabase.storage
          .from('verifications')
          .uploadBinary(filePath, bytes);

      // Upsert the Database Profile Table so Admin can see it
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'verification_document': filePath,
        'is_verified': false,
      });

      // Reset animation controller and show success screen
      _entranceController.reset();
      setState(() => _isSubmitted = true);
      _entranceController.forward();
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Upload failed: ${e.toString()}')),
              ],
            ),
            backgroundColor: kPremiumRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.lightImpact();
    await _supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      extendBodyBehindAppBar: true,
      appBar: _isSubmitted
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                TextButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: kTextSecondary,
                    size: 18,
                  ),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: kTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: Stack(
        children: [
          // Animated Background Blob 1
          AnimatedBuilder(
            animation: _floatingController,
            builder: (context, child) {
              return Positioned(
                top: -100 +
                    (math.sin(_floatingController.value * math.pi) * 20),
                right: -100 +
                    (math.cos(_floatingController.value * math.pi) * 10),
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
                bottom: -50 +
                    (math.cos(_floatingController.value * math.pi) * 20),
                left: -100 +
                    (math.sin(_floatingController.value * math.pi) * 15),
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

          // Glassmorphism effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60.0, sigmaY: 60.0),
            child: Container(color: Colors.transparent),
          ),

          // Main Content changes based on the _isSubmitted flag
          _isSubmitted ? _buildSuccessView() : _buildUploadView(),
        ],
      ),
    );
  }

  // --- VIEW 1: UPLOAD SCREEN ---
  Widget _buildUploadView() {
    final size = MediaQuery.of(context).size;

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: size.height * 0.02),

            // Icon Header
            _buildAnimatedWidget(
              startDelay: 0.0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kPremiumRed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: kPremiumRed,
                    size: 56,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Typography
            _buildAnimatedWidget(
              startDelay: 0.1,
              child: const Text(
                'Student Verification',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            _buildAnimatedWidget(
              startDelay: 0.2,
              child: const Text(
                'To maintain a safe and trusted marketplace, please upload proof of enrollment. This can be a Student ID, class schedule, or portal screenshot.',
                style: TextStyle(
                  fontSize: 15,
                  color: kTextSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),

            // Image Dropzone / Preview Area
            _buildAnimatedWidget(
              startDelay: 0.3,
              child: _selectedImage != null
                  ? _buildImagePreview()
                  : _buildImageDropzone(),
            ),

            const SizedBox(height: 40),

            // Submit Button
            _buildAnimatedWidget(
              startDelay: 0.4,
              child: SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: (_selectedImage == null || _isUploading)
                      ? null
                      : _uploadDocument,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPremiumRed,
                    disabledBackgroundColor: kPremiumRed.withOpacity(0.3),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text(
                          'Submit for Review',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // The empty state where the user taps to pick an image
  Widget _buildImageDropzone() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kPremiumRed.withOpacity(0.2), width: 2),
          boxShadow: [
            BoxShadow(
              color: kPremiumRed.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPremiumRed.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo_rounded,
                color: kPremiumRed,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap to select document',
              style: TextStyle(
                color: kPremiumRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'JPG, PNG or HEIC',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // FIXED: Use Image.network with XFile.path — works cross-platform
  Widget _buildImagePreview() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            // FIXED: Image.network works on web; XFile.path is a blob URL on web
            child: Image.network(
              _selectedImage!.path,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: kBackground,
                child: const Center(
                  child: Icon(Icons.image_rounded,
                      size: 48, color: kTextSecondary),
                ),
              ),
            ),
          ),
          // Dark gradient overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.transparent,
                  Colors.black.withOpacity(0.2),
                ],
              ),
            ),
          ),
          // Remove Button
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(30),
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: _removeImage,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded,
                          size: 16, color: kTextPrimary),
                      SizedBox(width: 6),
                      Text(
                        'Remove',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW 2: SUCCESS SCREEN ---
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAnimatedWidget(
              startDelay: 0.0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green.shade500,
                  size: 80,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildAnimatedWidget(
              startDelay: 0.2,
              child: const Text(
                'Document Submitted!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: kTextPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            _buildAnimatedWidget(
              startDelay: 0.3,
              child: const Text(
                'Your proof of enrollment is under review.\nTo ensure marketplace safety, our team will verify your account shortly. Check back soon!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: kTextSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 48),
            _buildAnimatedWidget(
              startDelay: 0.4,
              child: TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded, color: kPremiumRed),
                label: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: kPremiumRed,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  backgroundColor: kPremiumRed.withOpacity(0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
