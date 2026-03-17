import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'chat_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF5A5A5A);

class BorrowedItemsScreen extends StatefulWidget {
  const BorrowedItemsScreen({super.key});

  @override
  State<BorrowedItemsScreen> createState() => _BorrowedItemsScreenState();
}

class _BorrowedItemsScreenState extends State<BorrowedItemsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isProcessingPayment = false; // Lock screen during Stripe flow
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

          // Group pending AND awaiting_payment together in the first tab
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

  // --- NEW STRIPE PAYMENT LOGIC ---
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

      // 1. Create Payment Intent
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

      final String paymentIntentId =
          paymentIntent['id']; // WE MUST SAVE THIS FOR THE REFUND

      // 2. Initialize Payment Sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
          merchantDisplayName: 'Avory Campus Market',
          style: ThemeMode.system,
        ),
      );

      if (mounted) Navigator.pop(context); // Close spinner

      // 3. Present Sheet
      await Stripe.instance.presentPaymentSheet();

      // 4. If successful, update database!
      await Supabase.instance.client
          .from('rentals')
          .update({
            'status': 'active',
            'payment_status': 'paid',
            'stripe_payment_intent_id':
                paymentIntentId, // Saved for refunding the deposit later
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
    // ... (Your existing message owner logic stays exactly the same)
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
        backgroundColor: kBackground,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Borrowed Items',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
            fontSize: 24,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kPremiumRed,
          indicatorWeight: 3,
          labelColor: kPremiumRed,
          unselectedLabelColor: kTextSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          tabs: [
            Tab(text: 'Pending (${_pendingRequests.length})'),
            Tab(text: 'Active (${_activeRentals.length})'),
          ],
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: kPremiumRed),
              )
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_pendingRequests, isPendingTab: true),
                  _buildList(_activeRentals, isPendingTab: false),
                ],
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
            Icon(
              isPendingTab
                  ? Icons.hourglass_empty_rounded
                  : Icons.backpack_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              isPendingTab
                  ? 'No pending requests'
                  : 'You aren\'t renting anything right now',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchBorrowedItems,
      color: kPremiumRed,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(
                  itemImage,
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey.shade200,
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
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Owner: $ownerName',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
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
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Upfront',
                    style: TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                  Text(
                    'AED $totalPaid',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                'Refundable Deposit: AED $deposit',
                style: const TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // DYNAMIC ACTION BUTTONS
          if (status == 'pending')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelRequest(rental['id']),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: kTextSecondary,
                ),
                child: const Text('Cancel Request (Waiting for Owner)'),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _cancelRequest(rental['id']),
                  child: const Text(
                    'Cancel Request',
                    style: TextStyle(color: Colors.red),
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
                label: const Text('Message Owner to Return'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPremiumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
