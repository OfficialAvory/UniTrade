import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- THEME CONSTANTS (Matched to your app) ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF5A5A5A);
const Color kTextTertiary = Color(0xFF757575);

class ManageRentalsScreen extends StatefulWidget {
  const ManageRentalsScreen({super.key});

  @override
  State<ManageRentalsScreen> createState() => _ManageRentalsScreenState();
}

class _ManageRentalsScreenState extends State<ManageRentalsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isProcessingAction = false; // Lock UI during API calls
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
            listings (title, image_url),
            renter:profiles!renter_id (full_name)
          ''')
          .eq('owner_id', _currentUserId)
          .inFilter('status', ['pending', 'awaiting_payment', 'active'])
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          final List<Map<String, dynamic>> allRentals =
              List<Map<String, dynamic>>.from(data);

          // We group 'pending' and 'awaiting_payment' in the first tab
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

  // --- STANDARD DATABASE UPDATE (For Declines & Approvals) ---
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

  // --- STRIPE PARTIAL REFUND LOGIC ---
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

      // Only attempt a refund if there is a deposit and a valid payment ID
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

      // If refund succeeds (or wasn't needed), mark rental as completed
      await Supabase.instance.client
          .from('rentals')
          .update({'status': 'completed'})
          .eq('id', rental['id']);

      _fetchRentals();

      if (mounted) {
        Navigator.pop(context); // Close spinner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item Returned! Deposit refunded successfully.'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close spinner
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
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'Manage Rentals',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
            fontSize: 24,
            letterSpacing: -0.5,
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
              isPendingTab ? Icons.inbox_rounded : Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isPendingTab ? 'No pending requests' : 'No active rentals',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        physics: const AlwaysScrollableScrollPhysics(),
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
          // Top Row: Image & Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
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
                          color: Colors.grey.shade100,
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: Colors.grey.shade400,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: Colors.blueGrey.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          renterName,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
                        const SizedBox(width: 4),
                        Text(
                          dateRange,
                          style: TextStyle(
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
            padding: EdgeInsets.symmetric(vertical: 16),
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
                    style: TextStyle(color: kTextSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AED $rentCost',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Hold: AED $deposit',
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Dynamic Action Buttons
          if (status == 'pending')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        () => _updateRentalStatus(rental['id'], 'cancelled'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: kTextSecondary,
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    // ✅ NEW: Changes to awaiting_payment instead of active
                    onPressed:
                        () => _updateRentalStatus(
                          rental['id'],
                          'awaiting_payment',
                        ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: kPremiumRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            )
          else if (status == 'awaiting_payment')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              alignment: Alignment.center,
              child: Text(
                'Waiting for Renter to Pay...',
                style: TextStyle(
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else if (status == 'active')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                // ✅ NEW: Triggers the Stripe Refund!
                onPressed: () => _confirmReturnAndRefund(rental),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.teal, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.teal,
                  backgroundColor: Colors.teal.withOpacity(0.05),
                ),
                child: const Text(
                  'Confirm Item Returned',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
