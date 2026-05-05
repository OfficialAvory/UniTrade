import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW: Added SharedPreferences

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class PaymentPayoutsScreen extends StatefulWidget {
  const PaymentPayoutsScreen({super.key});

  @override
  State<PaymentPayoutsScreen> createState() => _PaymentPayoutsScreenState();
}

class _PaymentPayoutsScreenState extends State<PaymentPayoutsScreen> {
  bool _isLoading = true;
  bool _isWithdrawing = false;
  bool _isStripeConnected = false;

  double _availableBalance = 0.00;
  double _pendingBalance = 0.00;
  List<Map<String, dynamic>> _payoutHistory = [];

  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _fetchFinancialData();
  }

  Future<void> _fetchFinancialData() async {
    try {
      double tempPending = 0.0;
      double tempAvailable = 0.0;

      // NEW: Check local storage to see if they already connected Stripe
      final prefs = await SharedPreferences.getInstance();
      final bool savedStripeStatus =
          prefs.getBool('stripe_connected_$_currentUserId') ?? false;

      // 1. Fetch Sales Data (Chats where seller is current user)
      final chatsData = await Supabase.instance.client
          .from('chats')
          .select('''
            payment_status,
            listings(price),
            requests(budget),
            messages(content, is_offer, offer_status)
          ''')
          .eq('seller_id', _currentUserId)
          .inFilter('payment_status', ['paid', 'completed']);

      for (var chat in chatsData) {
        double price = 0.0;

        // Find accepted offer, otherwise use default price
        if (chat['messages'] != null && (chat['messages'] as List).isNotEmpty) {
          final messages = List<dynamic>.from(chat['messages']);
          final acceptedOffer = messages.lastWhere(
            (m) => m['is_offer'] == true && m['offer_status'] == 'accepted',
            orElse: () => null,
          );
          if (acceptedOffer != null) {
            price = double.tryParse(acceptedOffer['content'].toString()) ?? 0.0;
          } else {
            price =
                (chat['listings']?['price'] ?? chat['requests']?['budget'] ?? 0)
                    .toDouble();
          }
        } else {
          price =
              (chat['listings']?['price'] ?? chat['requests']?['budget'] ?? 0)
                  .toDouble();
        }

        if (chat['payment_status'] == 'paid') {
          tempPending += price;
        } else if (chat['payment_status'] == 'completed') {
          tempAvailable += price;
        }
      }

      // 2. Fetch Rentals Data
      final rentalsData = await Supabase.instance.client
          .from('rentals')
          .select('status, total_rental_cost')
          .eq('owner_id', _currentUserId)
          .eq('payment_status', 'paid')
          .inFilter('status', ['active', 'completed']);

      for (var rental in rentalsData) {
        double cost = (rental['total_rental_cost'] ?? 0).toDouble();
        if (rental['status'] == 'active') {
          tempPending += cost;
        } else if (rental['status'] == 'completed') {
          tempAvailable += cost;
        }
      }

      // 3. Fetch Payouts History (Withdrawals)
      final payoutsData = await Supabase.instance.client
          .from('payouts')
          .select('*')
          .eq('user_id', _currentUserId)
          .order('created_at', ascending: false);

      double totalWithdrawn = 0.0;
      for (var payout in payoutsData) {
        totalWithdrawn += (payout['amount'] ?? 0).toDouble();
      }

      // Final Math: Available is total completed minus whatever they already withdrew
      tempAvailable -= totalWithdrawn;

      if (mounted) {
        setState(() {
          _pendingBalance = tempPending;
          _availableBalance = tempAvailable > 0 ? tempAvailable : 0.0;
          _payoutHistory = List<Map<String, dynamic>>.from(payoutsData);
          _isStripeConnected = savedStripeStatus; // Set the saved status
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching financial data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _processWithdrawal() async {
    if (_availableBalance <= 0) return;

    setState(() => _isWithdrawing = true);

    try {
      // Create a record in the payouts table
      await Supabase.instance.client.from('payouts').insert({
        'user_id': _currentUserId,
        'amount': _availableBalance,
        'status': 'processing',
      });

      // Refresh the screen to show the new balance and payout history
      await _fetchFinancialData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal requested! Funds are on the way.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'Payment & Payouts',
          style: TextStyle(fontWeight: FontWeight.w800, color: kTextPrimary),
        ),
        backgroundColor: kBackground,
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: kPremiumRed),
              )
              : RefreshIndicator(
                color: kPremiumRed,
                onRefresh: _fetchFinancialData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBalanceCard(),
                      const SizedBox(height: 32),
                      _buildPayoutMethodsSection(),
                      const SizedBox(height: 32),
                      _buildRecentActivitySection(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPremiumRed, kPremiumRed.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: kPremiumRed.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AED ${_availableBalance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pending (Escrow)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${_pendingBalance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed:
                    (_availableBalance > 0 &&
                            !_isWithdrawing &&
                            _isStripeConnected)
                        ? _processWithdrawal
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: kPremiumRed,
                  disabledBackgroundColor: Colors.white.withOpacity(0.3),
                  disabledForegroundColor: Colors.white70,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child:
                    _isWithdrawing
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kPremiumRed,
                          ),
                        )
                        : const Text(
                          'Withdraw',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payout Method',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
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
          child:
              _isStripeConnected
                  ? ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_rounded,
                        color: Colors.green,
                      ),
                    ),
                    title: const Text(
                      'Bank Account Connected',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('•••• 1234'),
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text(
                        'Edit',
                        style: TextStyle(color: kPremiumRed),
                      ),
                    ),
                  )
                  : Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 48,
                          color: Colors.orange.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Payout Method Connected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Connect your bank account securely via Stripe to receive payments for your sold items.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kTextSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              // NEW: Save to local storage so it remembers
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool(
                                'stripe_connected_$_currentUserId',
                                true,
                              );

                              setState(() {
                                _isStripeConnected = true;
                              });

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Bank account linked!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigoAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Connect with Stripe',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Withdrawal History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: kTextPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (_payoutHistory.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No recent payouts',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'When you withdraw your earnings, they will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _payoutHistory.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final payout = _payoutHistory[index];
              final date = DateTime.parse(payout['created_at']).toLocal();
              final isProcessing = payout['status'] == 'processing';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            isProcessing
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isProcessing ? Icons.sync_rounded : Icons.check_rounded,
                        color: isProcessing ? Colors.orange : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Withdrawal to Bank',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(date),
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '-AED ${payout['amount']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isProcessing ? 'Processing' : 'Completed',
                          style: TextStyle(
                            color: isProcessing ? Colors.orange : Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
