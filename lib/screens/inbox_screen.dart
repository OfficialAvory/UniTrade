import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'chat_screen.dart';
import 'manage_rentals_screen.dart';
import 'borrowed_items_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF1A1A1A);
const Color kTextSecondary = Color(0xFF737373);
const Color kTextTertiary = Color(0xFFA3A3A3);

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allChats = [];
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  int _selectedCategoryIndex = 0; // 0: Buying, 1: Selling, 2: Rentals
  int _lendingActionCount = 0;
  int _borrowingActionCount = 0;

  // --- NEW: Track Block States ---
  Set<String> _blockedByMe = {};

  late final RealtimeChannel _activityChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchInbox();
    _fetchRentalCounts();
    _setupRealtime();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchInbox();
      _fetchRentalCounts();
    }
  }

  void _setupRealtime() {
    _activityChannel = Supabase.instance.client.channel(
      'inbox_$_currentUserId',
    );

    _activityChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            debugPrint('Realtime update: Messages table changed');
            _fetchInbox();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (payload) {
            debugPrint('Realtime update: Chats table changed');
            _fetchInbox();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rentals',
          callback: (payload) {
            debugPrint('Realtime update: Rentals table changed');
            _fetchRentalCounts();
          },
        )
        // Also listen for blocks being added/removed to update UI instantly
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blocks',
          callback: (payload) {
            debugPrint('Realtime update: Blocks table changed');
            _fetchInbox();
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Realtime subscription status: $status');
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Supabase.instance.client.removeChannel(_activityChannel);
    super.dispose();
  }

  Future<void> _fetchRentalCounts() async {
    try {
      final supabase = Supabase.instance.client;
      final lendingRes = await supabase
          .from('rentals')
          .select('id')
          .eq('owner_id', _currentUserId)
          .eq('status', 'pending');
      final borrowingRes = await supabase
          .from('rentals')
          .select('id')
          .eq('renter_id', _currentUserId)
          .eq('status', 'awaiting_payment');

      if (mounted) {
        setState(() {
          _lendingActionCount = lendingRes.length;
          _borrowingActionCount = borrowingRes.length;
        });
      }
    } catch (e) {
      debugPrint('Error fetching rental counts: $e');
    }
  }

  Future<void> _fetchInbox() async {
    try {
      final supabase = Supabase.instance.client;

      // 1. FETCH BLOCKS safely
      final blocksData = await supabase
          .from('blocks')
          .select('blocker_id, blocked_id')
          .or('blocker_id.eq.$_currentUserId,blocked_id.eq.$_currentUserId');

      Set<String> tempBlockedByMe = {};
      Set<String> blockedMe = {};

      for (var b in blocksData) {
        if (b['blocker_id'] == _currentUserId)
          tempBlockedByMe.add(b['blocked_id']);
        if (b['blocked_id'] == _currentUserId) blockedMe.add(b['blocker_id']);
      }

      // 2. FETCH CHATS
      final data = await supabase
          .from('chats')
          .select('''
            id, buyer_id, seller_id, payment_status, hidden_by_buyer, hidden_by_seller, created_at,
            listings (title, image_url, is_sold),
            requests (title, is_fulfilled), 
            buyer:profiles!buyer_id (full_name),
            seller:profiles!seller_id (full_name),
            messages (id, content, created_at, sender_id, is_read, is_offer, offer_status)
          ''')
          .or('buyer_id.eq.$_currentUserId,seller_id.eq.$_currentUserId');

      if (mounted) {
        setState(() {
          _blockedByMe = tempBlockedByMe;
          List<Map<String, dynamic>> processedChats =
              List<Map<String, dynamic>>.from(data);

          // 3. FILTER OUT CHATS IF THEY BLOCKED US (The "Silent Block" effect)
          processedChats.removeWhere((chat) {
            final otherUserId =
                chat['buyer_id'] == _currentUserId
                    ? chat['seller_id']
                    : chat['buyer_id'];
            return blockedMe.contains(otherUserId);
          });

          for (var chat in processedChats) {
            List<dynamic> msgs = chat['messages'] ?? [];
            msgs.sort(
              (a, b) => DateTime.parse(
                b['created_at'],
              ).compareTo(DateTime.parse(a['created_at'])),
            );

            final otherUserId =
                chat['buyer_id'] == _currentUserId
                    ? chat['seller_id']
                    : chat['buyer_id'];

            // Do not show unread badges if we blocked them
            if (_blockedByMe.contains(otherUserId)) {
              chat['unread_count'] = 0;
            } else {
              chat['unread_count'] =
                  msgs
                      .where(
                        (m) =>
                            m['is_read'] == false &&
                            m['sender_id'] != _currentUserId,
                      )
                      .length;
            }

            if (msgs.isNotEmpty) {
              chat['last_message'] = msgs.first;
              chat['updated_at'] = msgs.first['created_at'];
            } else {
              chat['last_message'] = null;
              chat['updated_at'] = chat['created_at'];
            }
          }
          processedChats.sort(
            (a, b) => DateTime.parse(
              b['updated_at'],
            ).compareTo(DateTime.parse(a['updated_at'])),
          );
          _allChats = processedChats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching inbox: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _hideChat(String chatId, bool isBuyer) async {
    try {
      final col = isBuyer ? 'hidden_by_buyer' : 'hidden_by_seller';
      await Supabase.instance.client
          .from('chats')
          .update({col: true})
          .eq('id', chatId);
      setState(() => _allChats.removeWhere((chat) => chat['id'] == chatId));
    } catch (e) {
      debugPrint('Error hiding chat: $e');
    }
  }

  Future<void> _toggleUnread(String chatId, List<dynamic> messages) async {
    try {
      final lastReceived = messages.firstWhere(
        (m) => m['sender_id'] != _currentUserId,
        orElse: () => null,
      );
      if (lastReceived != null) {
        await Supabase.instance.client
            .from('messages')
            .update({'is_read': !lastReceived['is_read']})
            .eq('id', lastReceived['id']);
        _fetchInbox();
      }
    } catch (e) {
      debugPrint('Error toggling unread: $e');
    }
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    final date = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0 && now.day == date.day) {
      return DateFormat('h:mm a').format(date);
    }
    if (diff.inDays == 1 || (diff.inDays == 0 && now.day != date.day)) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d').format(date);
  }

  int get _unreadBuyingCount {
    return _allChats
        .where(
          (chat) =>
              chat['buyer_id'] == _currentUserId &&
              chat['hidden_by_buyer'] != true,
        )
        .fold(0, (sum, chat) => sum + (chat['unread_count'] as int? ?? 0));
  }

  int get _unreadSellingCount {
    return _allChats
        .where(
          (chat) =>
              chat['buyer_id'] != _currentUserId &&
              chat['hidden_by_seller'] != true,
        )
        .fold(0, (sum, chat) => sum + (chat['unread_count'] as int? ?? 0));
  }

  int get _totalRentalActions => _lendingActionCount + _borrowingActionCount;

  bool get _hasUnreadInOtherCategories {
    if (_selectedCategoryIndex != 0 && _unreadBuyingCount > 0) return true;
    if (_selectedCategoryIndex != 1 && _unreadSellingCount > 0) return true;
    if (_selectedCategoryIndex != 2 && _totalRentalActions > 0) return true;
    return false;
  }

  String get _currentCategoryName {
    if (_selectedCategoryIndex == 0) return 'Buying';
    if (_selectedCategoryIndex == 1) return 'Selling';
    return 'Rentals';
  }

  void _showCategorySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.only(bottom: 32, top: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                _buildCategoryOption(
                  0,
                  'Buying',
                  Icons.shopping_bag_outlined,
                  badgeCount: _unreadBuyingCount,
                ),
                _buildCategoryOption(
                  1,
                  'Selling',
                  Icons.storefront_outlined,
                  badgeCount: _unreadSellingCount,
                ),
                _buildCategoryOption(
                  2,
                  'Rentals',
                  Icons.key_outlined,
                  badgeCount: _totalRentalActions,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryOption(
    int index,
    String title,
    IconData icon, {
    int badgeCount = 0,
  }) {
    final isSelected = _selectedCategoryIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedCategoryIndex = index);
          Navigator.pop(context);
          _fetchInbox();
          _fetchRentalCounts();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? kTextPrimary : kBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : kTextPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? kTextPrimary : kTextSecondary,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: kPremiumRed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded, color: kTextPrimary)
              else
                const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buyingChats =
        _allChats
            .where(
              (chat) =>
                  chat['buyer_id'] == _currentUserId &&
                  chat['hidden_by_buyer'] != true,
            )
            .toList();

    final sellingChats =
        _allChats
            .where(
              (chat) =>
                  chat['buyer_id'] != _currentUserId &&
                  chat['hidden_by_seller'] != true,
            )
            .toList();

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showCategorySelector,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentCategoryName,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: kTextPrimary,
                size: 28,
              ),
              if (_hasUnreadInOtherCategories)
                Container(
                  margin: const EdgeInsets.only(left: 6, bottom: 8),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kPremiumRed,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
        centerTitle: false,
        backgroundColor: kBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body:
          _isLoading
              ? _buildShimmerLoadingState()
              : _selectedCategoryIndex == 2
              ? _buildRentalsDashboard()
              : _buildChatList(
                _selectedCategoryIndex == 0 ? buyingChats : sellingChats,
                _selectedCategoryIndex == 0,
              ),
    );
  }

  Widget _buildChatList(List<Map<String, dynamic>> chats, bool isBuyingTab) {
    return RefreshIndicator(
      onRefresh: _fetchInbox,
      color: kPremiumRed,
      backgroundColor: Colors.white,
      child:
          chats.isEmpty
              ? _buildEmptyState(isBuyingTab)
              : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                itemCount: chats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder:
                    (context, index) => _buildPremiumChatCard(chats[index]),
              ),
    );
  }

  Widget _buildShimmerLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder:
          (_, __) => Shimmer.fromColors(
            baseColor: Colors.black.withOpacity(0.05),
            highlightColor: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 120, height: 14, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Container(width: 180, height: 12, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildRentalsDashboard() {
    return RefreshIndicator(
      onRefresh: () async => await _fetchRentalCounts(),
      color: kPremiumRed,
      backgroundColor: Colors.white,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          Row(
            children: [
              Expanded(
                child: _buildBentoCard(
                  title: 'Borrowed Items',
                  subtitle: 'Items you rent',
                  icon: Icons.backpack_rounded,
                  badgeCount: _borrowingActionCount,
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const BorrowedItemsScreen(),
                        ),
                      ).then((_) => _fetchRentalCounts()),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildBentoCard(
                  title: 'Lending Manager',
                  subtitle: 'Pending approvals',
                  icon: Icons.key_rounded,
                  badgeCount: _lendingActionCount,
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ManageRentalsScreen(),
                        ),
                      ).then((_) => _fetchRentalCounts()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBentoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            badgeCount > 0
                                ? kPremiumRed.withOpacity(0.08)
                                : kBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: badgeCount > 0 ? kPremiumRed : kTextPrimary,
                        size: 26,
                      ),
                    ),
                    if (badgeCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kPremiumRed,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badgeCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  style: const TextStyle(color: kTextPrimary, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumChatCard(Map<String, dynamic> chat) {
    final isBuyer = chat['buyer_id'] == _currentUserId;
    final otherName =
        isBuyer ? chat['seller']['full_name'] : chat['buyer']['full_name'];
    final userInitial =
        (otherName as String).isNotEmpty ? otherName[0].toUpperCase() : '?';
    final otherUserId = isBuyer ? chat['seller_id'] : chat['buyer_id'];

    final isRequest = chat['requests'] != null;
    final String itemTitle =
        isRequest
            ? "Request: ${chat['requests']['title']}"
            : chat['listings']?['title'] ?? 'Unknown Item';
    final String? itemImage = isRequest ? null : chat['listings']?['image_url'];
    final bool isSold =
        isRequest
            ? chat['requests']['is_fulfilled']
            : chat['listings']?['is_sold'] ?? false;
    final String payStatus = chat['payment_status'] ?? 'pending';

    final lastMessage = chat['last_message'];
    final bool hasUnread = (chat['unread_count'] ?? 0) > 0;
    final bool isBlockedByMe = _blockedByMe.contains(otherUserId);

    String preview = 'Tap to start chatting';

    // --- SHOW BLOCKED STATUS IN INBOX ---
    if (isBlockedByMe) {
      preview = '🚫 You blocked this user';
    } else if (isSold && payStatus != 'completed') {
      preview = 'Item unavailable';
    } else if (lastMessage != null) {
      preview =
          lastMessage['is_offer'] == true
              ? (lastMessage['sender_id'] == _currentUserId
                  ? 'You sent an offer'
                  : 'Sent you an offer')
              : lastMessage['content'];
    }

    return Slidable(
      key: ValueKey(chat['id']),
      startActionPane: ActionPane(
        motion: const StretchMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _toggleUnread(chat['id'], chat['messages']),
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            icon:
                hasUnread
                    ? Icons.mark_chat_read_rounded
                    : Icons.mark_chat_unread_rounded,
            borderRadius: BorderRadius.circular(24),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const StretchMotion(),
        dismissible: DismissiblePane(
          onDismissed: () => _hideChat(chat['id'], isBuyer),
        ),
        children: [
          SlidableAction(
            onPressed: (_) => _hideChat(chat['id'], isBuyer),
            backgroundColor: kPremiumRed,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            borderRadius: BorderRadius.circular(24),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color:
                hasUnread
                    ? kPremiumRed.withOpacity(0.3)
                    : Colors.black.withOpacity(0.04),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: hasUnread ? kPremiumRed.withOpacity(0.02) : kSurface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => ChatScreen(
                          chatId: chat['id'],
                          otherUserName: otherName,
                          itemTitle: itemTitle,
                        ),
                  ),
                ).then(
                  (_) => _fetchInbox(),
                ), // Re-fetches on return in case they unblocked
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.black.withOpacity(0.05),
                            ),
                            borderRadius: BorderRadius.circular(16),
                            color: isRequest ? kBackground : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child:
                                itemImage != null
                                    ? CachedNetworkImage(
                                      imageUrl: itemImage,
                                      fit: BoxFit.cover,
                                      color:
                                          isSold
                                              ? Colors.white.withOpacity(0.5)
                                              : null,
                                      colorBlendMode:
                                          isSold ? BlendMode.modulate : null,
                                      placeholder:
                                          (_, __) =>
                                              Container(color: kBackground),
                                      errorWidget:
                                          (_, __, ___) =>
                                              _buildPlaceholderImage(),
                                    )
                                    : isRequest
                                    ? const Icon(
                                      Icons.campaign_rounded,
                                      color: kTextSecondary,
                                      size: 28,
                                    )
                                    : _buildPlaceholderImage(),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.grey.shade800,
                              child: Text(
                                userInitial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                otherName,
                                style: const TextStyle(
                                  color: kTextSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _formatTimestamp(chat['updated_at']),
                              style: TextStyle(
                                color: hasUnread ? kPremiumRed : kTextTertiary,
                                fontSize: 11,
                                fontWeight:
                                    hasUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          itemTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                isSold && payStatus != 'completed'
                                    ? Colors.grey
                                    : kTextPrimary,
                            decoration:
                                isSold && payStatus != 'completed'
                                    ? TextDecoration.lineThrough
                                    : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (hasUnread)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: kPremiumRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      isBlockedByMe
                                          ? kPremiumRed
                                          : (isSold && payStatus != 'completed'
                                              ? kTextTertiary
                                              : (hasUnread
                                                  ? kTextPrimary
                                                  : kTextSecondary)),
                                  fontSize: 14,
                                  fontStyle:
                                      isSold && payStatus != 'completed'
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                  fontWeight:
                                      hasUnread || isBlockedByMe
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() => Container(
    color: kBackground,
    child: const Icon(Icons.image_rounded, color: kTextTertiary, size: 24),
  );

  Widget _buildEmptyState(bool isBuyingTab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withOpacity(0.04),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.inbox_rounded,
              size: 48,
              color: kTextTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isBuyingTab ? "No buying activity" : "No selling activity",
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isBuyingTab
                ? "Items you inquire about\nwill appear here."
                : "When someone messages you,\ntheir chats will appear here.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
