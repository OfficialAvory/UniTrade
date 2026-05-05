import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shimmer/shimmer.dart';

import 'chat_screen.dart'; // Added to allow navigation to the chat

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF1A1A1A);
const Color kTextSecondary = Color(0xFF737373);
const Color kTextTertiary = Color(0xFFA3A3A3);

class ManageRentalsScreen extends StatefulWidget {
  const ManageRentalsScreen({super.key});

  @override
  State<ManageRentalsScreen> createState() => _ManageRentalsScreenState();
}

class _ManageRentalsScreenState extends State<ManageRentalsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isProcessingAction = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _activeRentals = [];
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchRentals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchRentals() async {
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
            stripe_payment_intent_id,
            renter_id,
            listings (id, title, image_url),
            renter:profiles!renter_id (full_name)
          ''') // Added renter_id and listings.id to allow chat navigation
          .eq('owner_id', _currentUserId)
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
            content: Text('Error loading rentals: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    }
  }

  Future<void> _updateRentalStatus(String rentalId, String newStatus) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      await Supabase.instance.client
          .from('rentals')
          .update({'status': newStatus})
          .eq('id', rentalId);

      _fetchRentals();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'awaiting_payment'
                  ? 'Approved! Waiting for Renter to pay.'
                  : 'Request Declined',
            ),
            backgroundColor:
                newStatus == 'cancelled' ? Colors.grey.shade800 : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _confirmReturnAndRefund(Map<String, dynamic> rental) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

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
      final double deposit = (rental['security_deposit'] as num).toDouble();
      final String? paymentIntentId = rental['stripe_payment_intent_id'];

      if (deposit > 0 &&
          paymentIntentId != null &&
          paymentIntentId.isNotEmpty) {
        final int refundAmountInFils = (deposit * 100).toInt();

        final response = await http.post(
          Uri.parse('https://api.stripe.com/v1/refunds'),
          headers: {
            'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET_KEY']}',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'payment_intent': paymentIntentId,
            'amount': refundAmountInFils.toString(),
          },
        );

        final refundData = jsonDecode(response.body);

        if (refundData['error'] != null) {
          throw Exception(refundData['error']['message']);
        }
      }

      await Supabase.instance.client
          .from('rentals')
          .update({'status': 'completed'})
          .eq('id', rental['id']);

      _fetchRentals();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item Returned! Deposit refunded successfully.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refund Failed: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  // --- NEW: JUMP TO CHAT LOGIC ---
  Future<void> _openChat(Map<String, dynamic> rental) async {
    try {
      final supabase = Supabase.instance.client;
      final listingId = rental['listings']['id'];
      final renterId = rental['renter_id'];
      final renterName = rental['renter']['full_name'];
      final itemTitle = rental['listings']['title'];

      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', listingId)
          .eq('buyer_id', renterId);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': listingId,
                  'buyer_id': renterId,
                  'seller_id': _currentUserId,
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
                  otherUserName: renterName,
                  itemTitle: itemTitle,
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Could not open chat: $e');
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
          'Manage Rentals',
          style: TextStyle(color: kTextPrimary, fontSize: 24),
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
              labelStyle: const TextStyle(fontSize: 15),
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
                isPendingTab ? Icons.inbox_rounded : Icons.inventory_2_outlined,
                size: 48,
                color: kTextTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isPendingTab ? 'No pending requests' : 'No active rentals',
              style: const TextStyle(color: kTextPrimary, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              isPendingTab
                  ? 'When someone requests to rent an item,\nit will appear here.'
                  : 'Items currently out on rent\nwill be tracked here.',
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
      onRefresh: _fetchRentals,
      color: kPremiumRed,
      backgroundColor: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          return _buildRentalCard(items[index], isPendingTab: isPendingTab);
        },
      ),
    );
  }

  Widget _buildRentalCard(
    Map<String, dynamic> rental, {
    required bool isPendingTab,
  }) {
    final itemTitle = rental['listings']['title'];
    final itemImage = rental['listings']['image_url'];
    final renterName = rental['renter']['full_name'];
    final status = rental['status'];
    final dateRange = _formatDateRange(
      rental['start_date'],
      rental['end_date'],
    );

    final double rentCost = (rental['total_rental_cost'] as num).toDouble();
    final double deposit = (rental['security_deposit'] as num).toDouble();

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
          // Top Row: Image, Info, & Chat Button
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
                      style: const TextStyle(fontSize: 17, color: kTextPrimary),
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
                          renterName,
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
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: kTextSecondary,
                ),
                onPressed: () => _openChat(rental),
                style: IconButton.styleFrom(backgroundColor: kBackground),
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
                    'Expected Payout',
                    style: TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED $rentCost',
                    style: const TextStyle(fontSize: 20, color: kTextPrimary),
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
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Dynamic Action Buttons
          if (status == 'pending')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        () => _updateRentalStatus(rental['id'], 'cancelled'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Colors.black.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      foregroundColor: kTextPrimary,
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        () => _updateRentalStatus(
                          rental['id'],
                          'awaiting_payment',
                        ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: kPremiumRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ],
            )
          else if (status == 'awaiting_payment')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade200, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    color: Colors.amber.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for Renter to Pay...',
                    style: TextStyle(
                      color: Colors.amber.shade800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            )
          else if (status == 'active')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmReturnAndRefund(rental),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.teal, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  foregroundColor: Colors.teal,
                  backgroundColor: Colors.teal.withOpacity(0.05),
                ),
                child: const Text(
                  'Confirm Item Returned',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
