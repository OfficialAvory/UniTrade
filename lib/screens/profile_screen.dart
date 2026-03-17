import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'saved_items_screen.dart';
import 'my_listings_screen.dart';
import 'my_transactions_screen.dart';

// NEW IMPORTS FOR ACCOUNT SETTINGS
import 'edit_profile_screen.dart';
import 'payment_payouts_screen.dart';
import 'security_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _fullName = '';
  String _email = '';

  int _activeListingsCount = 0;
  int _transactionCount = 0;
  double _averageRating = 0.0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchProfileDashboardData();
  }

  Future<void> _fetchProfileDashboardData() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;

      // 1. Profile Data
      final profileData =
          await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', user.id)
              .maybeSingle();

      // 2. Active Listings Count
      final listingsData = await supabase
          .from('listings')
          .select('id')
          .eq('seller_id', user.id);

      // 3. Transactions Count
      final transactionsData = await supabase
          .from('chats')
          .select('id')
          .neq('payment_status', 'pending')
          .or('buyer_id.eq.${user.id},seller_id.eq.${user.id}');

      // 4. Reviews Data
      final reviewsData = await supabase
          .from('reviews')
          .select('rating')
          .eq('seller_id', user.id);

      double totalStars = 0;
      for (var review in reviewsData) {
        totalStars += (review['rating'] as num).toDouble();
      }
      final avgRating =
          reviewsData.isNotEmpty ? (totalStars / reviewsData.length) : 0.0;

      if (mounted) {
        setState(() {
          _email = user.email ?? 'No Email';
          _fullName =
              profileData != null
                  ? (profileData['full_name'] ?? 'Student')
                  : 'Student';

          _activeListingsCount = listingsData.length;
          _transactionCount = transactionsData.length;

          _averageRating = avgRating;
          _reviewCount = reviewsData.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPremiumRed)),
      );
    }

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'Account',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: kTextPrimary,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        backgroundColor: kBackground,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchProfileDashboardData,
        color: kPremiumRed,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            children: [
              // ==========================================
              // 1. HEADER BLOCK
              // ==========================================
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: kPremiumRed.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: kPremiumRed,
                        child: Text(
                          _fullName.isNotEmpty
                              ? _fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: kTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _email,
                            style: const TextStyle(
                              fontSize: 14,
                              color: kTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Colors.amber.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _reviewCount > 0
                                      ? '${_averageRating.toStringAsFixed(1)} ($_reviewCount Reviews)'
                                      : 'No reviews yet',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ==========================================
              // 2. MARKETPLACE BLOCK
              // ==========================================
              _buildSectionHeader('Marketplace'),
              _buildSettingsBlock([
                _buildSettingsTile(
                  icon: Icons.storefront_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'My Listings',
                  subtitle: 'Manage the items you are selling',
                  trailingText: _activeListingsCount.toString(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MyListingsScreen(),
                      ),
                    ).then((_) => _fetchProfileDashboardData());
                  },
                ),
                _buildSettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: Colors.teal,
                  title: 'My Transactions',
                  subtitle: 'View your buying and selling history',
                  trailingText: _transactionCount.toString(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MyTransactionsScreen(),
                      ),
                    ).then((_) => _fetchProfileDashboardData());
                  },
                ),
                _buildSettingsTile(
                  icon: Icons.favorite_rounded,
                  iconColor: kPremiumRed,
                  title: 'Saved Items',
                  subtitle: 'Items you have favorited',
                  isLast: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SavedItemsScreen(),
                      ),
                    );
                  },
                ),
              ]),

              // ==========================================
              // 3. ACCOUNT SETTINGS BLOCK (UPDATED)
              // ==========================================
              _buildSectionHeader('Account Settings'),
              _buildSettingsBlock([
                _buildSettingsTile(
                  icon: Icons.person_rounded,
                  iconColor: Colors.blueAccent,
                  title: 'Edit Profile',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) =>
                                EditProfileScreen(currentName: _fullName),
                      ),
                    ).then((_) => _fetchProfileDashboardData());
                  },
                ),
                _buildSettingsTile(
                  icon: Icons.account_balance_rounded,
                  iconColor: Colors.green,
                  title: 'Payment & Payouts',
                  subtitle: 'Manage your Stripe connected account',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PaymentPayoutsScreen(),
                      ),
                    );
                  },
                ),
                _buildSettingsTile(
                  icon: Icons.security_rounded,
                  iconColor: Colors.orange,
                  title: 'Security & Password',
                  isLast: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SecurityScreen(userEmail: _email),
                      ),
                    );
                  },
                ),
              ]),

              // ==========================================
              // 4. SUPPORT & APP BLOCK
              // ==========================================
              _buildSectionHeader('Support'),
              _buildSettingsBlock([
                _buildSettingsTile(
                  icon: Icons.help_outline_rounded,
                  iconColor: Colors.grey.shade700,
                  title: 'Help & Support',
                  onTap: () {},
                ),
                _buildSettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: Colors.grey.shade700,
                  title: 'About Avory',
                  trailingText: 'v1.0.0',
                  onTap: () {},
                ),
                _buildSettingsTile(
                  icon: Icons.logout_rounded,
                  iconColor: kPremiumRed,
                  title: 'Log Out',
                  titleColor: kPremiumRed,
                  isLast: true,
                  hideArrow: true,
                  onTap: _signOut,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: kTextSecondary,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsBlock(List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: tiles),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? trailingText,
    required VoidCallback onTap,
    bool isLast = false,
    Color titleColor = kTextPrimary,
    bool hideArrow = false,
  }) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: titleColor,
            ),
          ),
          subtitle:
              subtitle != null
                  ? Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: kTextSecondary),
                  )
                  : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingText != null)
                Text(
                  trailingText,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kTextSecondary,
                    fontSize: 14,
                  ),
                ),
              if (!hideArrow) ...[
                if (trailingText != null) const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 60, color: Colors.grey.shade100),
      ],
    );
  }
}
