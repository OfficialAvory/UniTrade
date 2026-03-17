import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class MyTransactionsScreen extends StatefulWidget {
  const MyTransactionsScreen({super.key});

  @override
  State<MyTransactionsScreen> createState() => _MyTransactionsScreenState();
}

class _MyTransactionsScreenState extends State<MyTransactionsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allTransactions = [];

  // Segmented Control State
  int _selectedTabIndex = 0; // 0 = Purchased, 1 = Sold
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      // Fetch from 'chats' where the user is EITHER the buyer OR the seller,
      // and a payment has actually been made (status is not pending).
      final data = await Supabase.instance.client
          .from('chats')
          .select('''
            id,
            buyer_id,
            seller_id,
            payment_status,
            created_at,
            buyer:profiles!buyer_id(full_name),
            seller:profiles!seller_id(full_name),
            listings(title, image_url, price),
            requests(title, budget)
          ''')
          .neq(
            'payment_status',
            'pending',
          ) // Only show paid, completed, or cancelled
          .or('buyer_id.eq.$_currentUserId,seller_id.eq.$_currentUserId')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allTransactions = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter the transactions based on the selected tab
    final filteredTransactions =
        _allTransactions.where((transaction) {
          final isBuyer = transaction['buyer_id'] == _currentUserId;
          if (_selectedTabIndex == 0) return isBuyer; // Purchased Tab
          return !isBuyer; // Sold Tab
        }).toList();

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        title: const Text(
          'My Transactions',
          style: TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _buildSegmentTab(0, 'Purchased'),
                  _buildSegmentTab(1, 'Sold'),
                ],
              ),
            ),
          ),
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: kPremiumRed),
              )
              : RefreshIndicator(
                color: kPremiumRed,
                onRefresh: _fetchTransactions,
                child:
                    filteredTransactions.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredTransactions.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _buildTransactionCard(
                              filteredTransactions[index],
                            );
                          },
                        ),
              ),
    );
  }

  Widget _buildSegmentTab(int index, String title) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : [],
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? kTextPrimary : kTextSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final bool isRequest = transaction['requests'] != null;
    final bool isBuyer = transaction['buyer_id'] == _currentUserId;

    // Determine what text to show based on the user's role in this transaction
    final String otherUserName =
        isBuyer
            ? (transaction['seller']?['full_name'] ?? 'Unknown Seller')
            : (transaction['buyer']?['full_name'] ?? 'Unknown Buyer');

    final String roleText = isBuyer ? 'Bought from' : 'Sold to';

    final String title =
        isRequest
            ? transaction['requests']['title']
            : transaction['listings']?['title'] ?? 'Unknown Item';

    final String priceString =
        isRequest
            ? transaction['requests']['budget'].toString()
            : transaction['listings']?['price'].toString() ?? '0';

    final String? imageUrl =
        isRequest ? null : transaction['listings']?['image_url'];

    final String status = transaction['payment_status'] ?? 'unknown';
    final DateTime date = DateTime.parse(transaction['created_at']).toLocal();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. IMAGE OR ICON
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color:
                  isRequest
                      ? kPremiumRed.withOpacity(0.1)
                      : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child:
                  imageUrl != null
                      ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) => const Icon(
                              Icons.broken_image_rounded,
                              color: Colors.grey,
                            ),
                      )
                      : Icon(
                        isRequest
                            ? Icons.campaign_rounded
                            : Icons.inventory_2_outlined,
                        color: isRequest ? kPremiumRed : Colors.grey.shade400,
                        size: 32,
                      ),
            ),
          ),
          const SizedBox(width: 16),

          // 2. MIDDLE DETAILS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: kTextPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$roleText $otherUserName',
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('MMM d, yyyy • h:mm a').format(date),
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 3. RIGHT SIDE: PRICE & STATUS
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // Show a green '+' if they are the seller earning money
                isBuyer ? 'AED $priceString' : '+AED $priceString',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isBuyer ? kTextPrimary : Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildStatusPill(status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'completed':
        bgColor = Colors.deepPurple.shade50;
        textColor = Colors.deepPurple;
        label = 'Completed';
        break;
      case 'paid':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        label = 'In Escrow';
        break;
      case 'cancelled':
        bgColor = Colors.red.shade50;
        textColor = Colors.red;
        label = 'Refunded';
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        label = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: kPremiumRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _selectedTabIndex == 0
                  ? Icons.shopping_bag_outlined
                  : Icons.storefront_rounded,
              size: 64,
              color: kPremiumRed,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _selectedTabIndex == 0 ? "No purchases yet" : "No sales yet",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _selectedTabIndex == 0
                ? "When you buy an item or secure a request\nin escrow, it will appear here."
                : "When someone buys your item or fulfills\nyour request, it will appear here.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: kTextSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
