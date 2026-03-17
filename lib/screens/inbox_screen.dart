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

class _InboxScreenState extends State<InboxScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allChats = [];
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  int _selectedTabIndex = 0;
  int _lendingActionCount = 0;
  int _borrowingActionCount = 0;

  late final RealtimeChannel _activityChannel;

  @override
  void initState() {
    super.initState();
    _fetchInbox();
    _fetchRentalCounts();
    _setupRealtime();
  }

  void _setupRealtime() {
    _activityChannel = Supabase.instance.client.channel(
      'public:inbox_activity',
    );
    _activityChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _fetchInbox(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rentals',
          callback: (payload) => _fetchRentalCounts(),
        )
        .subscribe();
  }

  @override
  void dispose() {
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
      final data = await Supabase.instance.client
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
          List<Map<String, dynamic>> processedChats =
              List<Map<String, dynamic>>.from(data);
          for (var chat in processedChats) {
            List<dynamic> msgs = chat['messages'] ?? [];
            msgs.sort(
              (a, b) => DateTime.parse(
                b['created_at'],
              ).compareTo(DateTime.parse(a['created_at'])),
            );
            chat['unread_count'] =
                msgs
                    .where(
                      (m) =>
                          m['is_read'] == false &&
                          m['sender_id'] != _currentUserId,
                    )
                    .length;
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
    if (diff.inDays == 0 && now.day == date.day)
      return DateFormat('h:mm a').format(date);
    if (diff.inDays == 1 || (diff.inDays == 0 && now.day != date.day))
      return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats =
        _allChats.where((chat) {
          final isBuyer = chat['buyer_id'] == _currentUserId;
          if (isBuyer && chat['hidden_by_buyer'] == true) return false;
          if (!isBuyer && chat['hidden_by_seller'] == true) return false;
          return _selectedTabIndex == 0
              ? isBuyer
              : _selectedTabIndex == 1
              ? !isBuyer
              : false;
        }).toList();

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'Activity',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
            fontSize: 26,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        backgroundColor: kBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    alignment: Alignment(
                      _selectedTabIndex == 0
                          ? -1.0
                          : _selectedTabIndex == 1
                          ? 0.0
                          : 1.0,
                      0,
                    ),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.fastOutSlowIn,
                    child: FractionallySizedBox(
                      widthFactor: 0.333,
                      heightFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _buildSegmentTab(0, 'Buying'),
                      _buildSegmentTab(1, 'Selling'),
                      _buildSegmentTab(
                        2,
                        'Rentals',
                        badgeCount: _lendingActionCount + _borrowingActionCount,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body:
          _selectedTabIndex == 2
              ? _buildRentalsDashboard()
              : _isLoading
              ? _buildShimmerLoadingState()
              : RefreshIndicator(
                onRefresh: _fetchInbox,
                color: kPremiumRed,
                child:
                    filteredChats.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          itemCount: filteredChats.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 12),
                          itemBuilder:
                              (context, index) =>
                                  _buildPremiumChatCard(filteredChats[index]),
                        ),
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
            baseColor: Colors.grey.shade200,
            highlightColor: Colors.white,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
    );
  }

  Widget _buildRentalsDashboard() {
    return RefreshIndicator(
      onRefresh: () async => await _fetchRentalCounts(),
      color: kPremiumRed,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildPremiumRentalCard(
            title: 'Borrowed Items',
            subtitle: 'Track the items you are currently renting.',
            emptyHint: 'No active borrowed items.',
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
          const SizedBox(height: 16),
          _buildPremiumRentalCard(
            title: 'Lending Manager',
            subtitle: 'Approve requests & manage items out for rent.',
            emptyHint: 'All caught up! No pending approvals.',
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
        ],
      ),
    );
  }

  Widget _buildPremiumRentalCard({
    required String title,
    required String subtitle,
    required String emptyHint,
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kBackground,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(0.05)),
              ),
              child: Icon(icon, color: kTextPrimary, size: 24),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badgeCount > 0 ? subtitle : emptyHint,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: badgeCount > 0 ? kTextSecondary : kTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: kPremiumRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentTab(int index, String title, {int badgeCount = 0}) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? kTextPrimary : kTextSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kPremiumRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
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

    String preview = 'Tap to start chatting';
    if (isSold && payStatus != 'completed') {
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
      child: GestureDetector(
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
            ).then((_) => _fetchInbox()),
        child: Container(
          decoration: BoxDecoration(
            color: hasUnread ? kPremiumRed.withOpacity(0.02) : kSurface,
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
                                      (_, __) => Container(color: kBackground),
                                  errorWidget:
                                      (_, __, ___) => _buildPlaceholderImage(),
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
                            style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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
                                hasUnread ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      itemTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
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
                                  isSold && payStatus != 'completed'
                                      ? kTextTertiary
                                      : (hasUnread
                                          ? kTextPrimary
                                          : kTextSecondary),
                              fontSize: 14,
                              fontStyle:
                                  isSold && payStatus != 'completed'
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                              fontWeight:
                                  hasUnread
                                      ? FontWeight.w600
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
    );
  }

  Widget _buildPlaceholderImage() => Container(
    color: kBackground,
    child: const Icon(Icons.image_rounded, color: kTextTertiary, size: 24),
  );

  Widget _buildEmptyState() {
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
            _selectedTabIndex == 0
                ? "No buying activity"
                : "No selling activity",
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedTabIndex == 0
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
