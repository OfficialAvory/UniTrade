import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shimmer/shimmer.dart';
import 'chat_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF1A1A1A);
const Color kTextSecondary = Color(0xFF737373);
const Color kTextTertiary = Color(0xFFA3A3A3);

class BorrowedItemsScreen extends StatefulWidget {
  const BorrowedItemsScreen({super.key});

  @override
  State<BorrowedItemsScreen> createState() => _BorrowedItemsScreenState();
}

class _BorrowedItemsScreenState extends State<BorrowedItemsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isProcessingPayment = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _activeRentals = [];
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchBorrowedItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBorrowedItems() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('rentals')
          .select('''
            id,
            status,
            start_date,
            end_date,
            total_rental_cost,
            security_deposit,
            owner_id,
            listings (id, title, image_url),
            owner:profiles!owner_id (full_name)
          ''')
          .eq('renter_id', _currentUserId)
          .inFilter('status', ['pending', 'awaiting_payment', 'active'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          final List<Map<String, dynamic>> allRentals =
              List<Map<String, dynamic>>.from(data);

          _pendingRequests =
              allRentals
                  .where(
                    (r) =>
                        r['status'] == 'pending' ||
                        r['status'] == 'awaiting_payment',
                  )
                  .toList();
          _activeRentals =
              allRentals.where((r) => r['status'] == 'active').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading items: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    }
  }

  Future<void> _payForRental(Map<String, dynamic> rental) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const PopScope(
            canPop: false,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
    );

    try {
      final double rentCost = (rental['total_rental_cost'] as num).toDouble();
      final double deposit = (rental['security_deposit'] as num).toDouble();
      final double totalAmount = rentCost + deposit;

      final int amountInFils = (totalAmount * 100).toInt();

      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET_KEY']}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'amount': amountInFils.toString(), 'currency': 'aed'},
      );

      final paymentIntent = jsonDecode(response.body);

      if (paymentIntent['error'] != null) {
        throw Exception(paymentIntent['error']['message']);
      }

      final String paymentIntentId = paymentIntent['id'];

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
          merchantDisplayName: 'Avory Campus Market',
          style: ThemeMode.system,
        ),
      );

      if (mounted) Navigator.pop(context);

      await Stripe.instance.presentPaymentSheet();

      await Supabase.instance.client
          .from('rentals')
          .update({
            'status': 'active',
            'payment_status': 'paid',
            'stripe_payment_intent_id': paymentIntentId,
          })
          .eq('id', rental['id']);

      _fetchBorrowedItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment Successful! Rental is now active.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Failed: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  Future<void> _cancelRequest(String rentalId) async {
    try {
      await Supabase.instance.client
          .from('rentals')
          .update({'status': 'cancelled'})
          .eq('id', rentalId);
      _fetchBorrowedItems();
    } catch (e) {
      debugPrint('Failed to cancel: $e');
    }
  }

  Future<void> _messageOwner(Map<String, dynamic> rental) async {
    try {
      final supabase = Supabase.instance.client;
      final listingId = rental['listings']['id'];
      final ownerId = rental['owner_id'];
      final ownerName = rental['owner']['full_name'];
      final itemTitle = rental['listings']['title'];

      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', listingId)
          .eq('buyer_id', _currentUserId);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': listingId,
                  'buyer_id': _currentUserId,
                  'seller_id': ownerId,
                })
                .select('id')
                .single();
        chatId = newChat['id'];
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: ownerName,
                  itemTitle: itemTitle,
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Could not start chat: $e');
    }
  }

  String _formatDateRange(String startIso, String endIso) {
    final start = DateTime.parse(startIso).toLocal();
    final end = DateTime.parse(endIso).toLocal();
    final formatter = DateFormat('MMM d');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text(
          'Borrowed Items',
          style: TextStyle(
            color: kTextPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withOpacity(0.05),
                  width: 1.5,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 3,
              indicatorColor: kTextPrimary,
              labelColor: kTextPrimary,
              unselectedLabelColor: kTextTertiary,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelPadding: const EdgeInsets.symmetric(vertical: 12),
              labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 15),
              tabs: [
                Text('Pending (${_pendingRequests.length})'),
                Text('Active (${_activeRentals.length})'),
              ],
            ),
          ),
        ),
      ),
      body:
          _isLoading
              ? _buildShimmerLoadingState()
              : TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildList(_pendingRequests, isPendingTab: true),
                  _buildList(_activeRentals, isPendingTab: false),
                ],
              ),
    );
  }

  Widget _buildShimmerLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder:
          (_, __) => Shimmer.fromColors(
            baseColor: Colors.black.withOpacity(0.05),
            highlightColor: Colors.white,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> items, {
    required bool isPendingTab,
  }) {
    if (items.isEmpty) {
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
              child: Icon(
                isPendingTab
                    ? Icons.hourglass_empty_rounded
                    : Icons.backpack_outlined,
                size: 48,
                color: kTextTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isPendingTab
                  ? 'No pending requests'
                  : 'You aren\'t renting anything',
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isPendingTab
                  ? 'When you request to borrow an item,\nit will appear here.'
                  : 'Items you are actively renting\nwill be tracked here.',
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

    return RefreshIndicator(
      onRefresh: _fetchBorrowedItems,
      color: kPremiumRed,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder:
            (context, index) =>
                _buildRentalCard(items[index], isPendingTab: isPendingTab),
      ),
    );
  }

  Widget _buildRentalCard(
    Map<String, dynamic> rental, {
    required bool isPendingTab,
  }) {
    final itemTitle = rental['listings']['title'];
    final itemImage = rental['listings']['image_url'];
    final ownerName = rental['owner']['full_name'];
    final dateRange = _formatDateRange(
      rental['start_date'],
      rental['end_date'],
    );

    final double rentCost = (rental['total_rental_cost'] as num).toDouble();
    final double deposit = (rental['security_deposit'] as num).toDouble();
    final double totalPaid = rentCost + deposit;

    final String status = rental['status'];

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Image & Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    itemImage,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Container(
                          width: 72,
                          height: 72,
                          color: kBackground,
                          child: const Icon(
                            Icons.broken_image_rounded,
                            color: kTextTertiary,
                          ),
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
                      itemTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        color: kTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: kTextSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Owner: $ownerName',
                          style: const TextStyle(
                            color: kTextSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: kPremiumRed.withOpacity(0.8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateRange,
                          style: const TextStyle(
                            color: kPremiumRed,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
          ),

          // Payout Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Upfront',
                    style: TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED $totalPaid',
                    style: const TextStyle(
                      fontSize: 20,
                      color: kTextPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (deposit > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Hold: AED $deposit',
                        style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // DYNAMIC ACTION BUTTONS
          if (status == 'pending')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelRequest(rental['id']),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.black.withOpacity(0.1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  foregroundColor: kTextPrimary,
                ),
                child: const Text(
                  'Cancel Request',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else if (status == 'awaiting_payment')
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _payForRental(rental),
                    icon: const Icon(Icons.credit_card_rounded),
                    label: Text('Pay AED $totalPaid to Start'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _cancelRequest(rental['id']),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cancel Request',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            )
          else if (status == 'active')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _messageOwner(rental),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text(
                  'Message Owner to Return',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPremiumRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
