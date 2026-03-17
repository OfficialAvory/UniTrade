import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'create_listing_screen.dart';
import 'profile_screen.dart';
import 'saved_items_screen.dart';
import 'inbox_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  bool _hasUnreadActivity = false; // Renamed to cover both messages and rentals
  late final RealtimeChannel _activityChannel;

  final List<Widget> _pages = [
    const HomeScreen(),
    const SavedItemsScreen(),
    const InboxScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkUnreadActivity();
    _setupRealtime();
  }

  // --- UPDATED LOGIC (Checks Messages AND Rentals) ---
  Future<void> _checkUnreadActivity() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      bool hasUnread = false;

      // 1. Check for unread messages (Your existing logic)
      final chats = await Supabase.instance.client
          .from('chats')
          .select('id')
          .or('buyer_id.eq.${currentUser.id},seller_id.eq.${currentUser.id}');

      if (chats.isNotEmpty) {
        final chatIds = chats.map((c) => c['id']).toList();
        final unreadMessages = await Supabase.instance.client
            .from('messages')
            .select('id')
            .inFilter('chat_id', chatIds)
            .eq('is_read', false)
            .neq('sender_id', currentUser.id)
            .limit(1);

        if (unreadMessages.isNotEmpty) {
          hasUnread = true;
        }
      }

      // 2. NEW: Check for pending rental requests (Owner needs to approve)
      if (!hasUnread) {
        final pendingRentals = await Supabase.instance.client
            .from('rentals')
            .select('id')
            .eq('owner_id', currentUser.id)
            .eq('status', 'pending')
            .limit(1);

        if (pendingRentals.isNotEmpty) {
          hasUnread = true;
        }
      }

      if (mounted && _hasUnreadActivity != hasUnread) {
        setState(() {
          _hasUnreadActivity = hasUnread;
        });
      }
    } catch (e) {
      debugPrint('Error checking activity: $e');
    }
  }

  void _setupRealtime() {
    // We create a single channel but listen to TWO different tables
    _activityChannel = Supabase.instance.client.channel('public:activity_nav');

    _activityChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _checkUnreadActivity(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rentals', // ✅ Listen to rentals table too!
          callback: (payload) => _checkUnreadActivity(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_activityChannel);
    super.dispose();
  }

  // --- UI LOGIC ---

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onAddListingTapped() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateListingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 65,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // 1. Home
                _NavBarItem(
                  icon: Icons.home_rounded,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                ),

                // 2. Favorites
                _NavBarItem(
                  icon: Icons.favorite_border_rounded,
                  activeIcon: Icons.favorite_rounded,
                  label: 'Saved',
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),

                // 3. Create (Center Action Button)
                _CreateListingButton(onTap: _onAddListingTapped),

                // 4. Activity / Inbox
                _NavBarItem(
                  icon:
                      Icons
                          .notifications_none_rounded, // Better icon for "Activity"
                  activeIcon: Icons.notifications_rounded,
                  label: 'Activity',
                  isSelected: _selectedIndex == 2,
                  onTap: () => _onItemTapped(2),
                  hasBadge:
                      _hasUnreadActivity, // Shows dot for chats OR rentals
                ),

                // 5. Profile
                _NavBarItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _selectedIndex == 3,
                  onTap: () => _onItemTapped(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- CUSTOM WIDGETS ---

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasBadge;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = kPremiumRed;
    final inactiveColor = Colors.grey.shade400;

    Widget iconWidget = Icon(
      isSelected ? activeIcon : icon,
      color: isSelected ? activeColor : inactiveColor,
      size: 26,
    );

    if (hasBadge) {
      iconWidget = Badge(
        smallSize: 10, // Made it slightly larger so it's obvious
        backgroundColor: Colors.redAccent,
        child: iconWidget,
      );
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(isSelected), child: iconWidget),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateListingButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateListingButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: kPremiumRed,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: kPremiumRed.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sell',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kPremiumRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
