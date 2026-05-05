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
  int _selectedTabIndex = 0; // 0 = Purchased/Rented, 1 = Sold/Rented Out
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    try {
      // 1. Fetch Sales and Requests from 'chats'
      final chatsFuture = Supabase.instance.client
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
            requests(title, budget),
            messages(content, is_offer, offer_status)
          ''')
          .neq('payment_status', 'pending')
          .or('buyer_id.eq.$_currentUserId,seller_id.eq.$_currentUserId');

      // 2. Fetch Rentals from 'rentals'
      final rentalsFuture = Supabase.instance.client
          .from('rentals')
          .select('''
            id,
            renter_id,
            owner_id,
            status,
            payment_status,
            created_at,
            total_rental_cost,
            security_deposit,
            renter:profiles!renter_id(full_name),
            owner:profiles!owner_id(full_name),
            listings(title, image_url)
          ''')
          .eq(
            'payment_status',
            'paid',
          ) // Only grab rentals where money exchanged hands
          .or('renter_id.eq.$_currentUserId,owner_id.eq.$_currentUserId');

      final results = await Future.wait([chatsFuture, rentalsFuture]);

      final chatsData = List<Map<String, dynamic>>.from(results[0]);
      final rentalsData = List<Map<String, dynamic>>.from(results[1]);

      // Merge both into a single list
      List<Map<String, dynamic>> combined = [];

      for (var c in chatsData) {
        combined.add({...c, 'tx_type': 'sale'});
      }
      for (var r in rentalsData) {
        combined.add({...r, 'tx_type': 'rental'});
      }

      // Sort by newest date first
      combined.sort(
        (a, b) => DateTime.parse(
          b['created_at'],
        ).compareTo(DateTime.parse(a['created_at'])),
      );

      if (mounted) {
        setState(() {
          _allTransactions = combined;
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
          final isRental = transaction['tx_type'] == 'rental';

          // Determine who the buyer/renter is
          final String buyerId =
              isRental ? transaction['renter_id'] : transaction['buyer_id'];
          final bool isBuyer = buyerId == _currentUserId;

          if (_selectedTabIndex == 0) return isBuyer; // Purchased / Rented Tab
          return !isBuyer; // Sold / Rented Out Tab
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
    final bool isRental = transaction['tx_type'] == 'rental';
    final bool isRequest = transaction['requests'] != null;

    final String buyerId =
        isRental ? transaction['renter_id'] : transaction['buyer_id'];
    final bool isBuyer = buyerId == _currentUserId;

    // Determine name dynamically
    String otherUserName = 'Unknown';
    final dynamic targetUserNode =
        isBuyer
            ? (isRental ? transaction['owner'] : transaction['seller'])
            : (isRental ? transaction['renter'] : transaction['buyer']);

    if (targetUserNode != null && targetUserNode['full_name'] != null) {
      otherUserName = targetUserNode['full_name'];
    }

    final String roleText =
        isRental
            ? (isBuyer ? 'Rented from' : 'Rented to')
            : (isBuyer ? 'Bought from' : 'Sold to');

    final String title =
        isRequest
            ? transaction['requests']['title']
            : transaction['listings']?['title'] ?? 'Unknown Item';

    String priceString = '0';
    String subtitleExtension = '';

    // Calculate Price specifically based on if it's a Sale or Rental
    if (isRental) {
      final double cost = (transaction['total_rental_cost'] as num).toDouble();
      final double deposit =
          (transaction['security_deposit'] as num).toDouble();

      priceString = (cost + deposit).toStringAsFixed(0);
      subtitleExtension = ' \n(Inc. AED $deposit deposit)';
    } else {
      priceString =
          isRequest
              ? transaction['requests']['budget'].toString()
              : transaction['listings']?['price'].toString() ?? '0';

      if (transaction['messages'] != null) {
        final messages = transaction['messages'] as List<dynamic>;
        final acceptedOffer = messages.lastWhere(
          (msg) => msg['is_offer'] == true && msg['offer_status'] == 'accepted',
          orElse: () => null,
        );
        if (acceptedOffer != null) {
          priceString = acceptedOffer['content'].toString();
        }
      }
    }

    final String? imageUrl =
        isRequest ? null : transaction['listings']?['image_url'];
    final String status =
        isRental
            ? transaction['status']
            : (transaction['payment_status'] ?? 'unknown');
    final DateTime date = DateTime.parse(transaction['created_at']).toLocal();

    // NEW: Wrapped in GestureDetector to open the receipt
    return GestureDetector(
      onTap:
          () => _showReceiptModal(
            transaction: transaction,
            isBuyer: isBuyer,
            otherUserName: otherUserName,
            roleText: roleText,
            title: title,
            imageUrl: imageUrl,
            status: status,
            date: date,
            isRental: isRental,
            isRequest: isRequest,
            totalDisplayed: priceString,
          ),
      child: Container(
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
                  isBuyer ? 'AED $priceString' : '+AED $priceString',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isBuyer ? kTextPrimary : Colors.green.shade700,
                  ),
                ),
                if (subtitleExtension.isNotEmpty)
                  Text(
                    subtitleExtension,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 8),
                _buildStatusPill(status, isRental),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // NEW: DIGITAL RECEIPT MODAL
  // =====================================================================
  void _showReceiptModal({
    required Map<String, dynamic> transaction,
    required bool isBuyer,
    required String otherUserName,
    required String roleText,
    required String title,
    required String? imageUrl,
    required String status,
    required DateTime date,
    required bool isRental,
    required bool isRequest,
    required String totalDisplayed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // Extracting short ID for the receipt
        final String rawId = transaction['id'].toString();
        final String shortId =
            rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pull Tab
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 48,
                  color: kTextPrimary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Transaction Receipt',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMMM d, yyyy • h:mm a').format(date),
                  style: const TextStyle(color: kTextSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Item Details
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color:
                            isRequest
                                ? kPremiumRed.withOpacity(0.1)
                                : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            imageUrl != null
                                ? Image.network(imageUrl, fit: BoxFit.cover)
                                : Icon(
                                  isRequest
                                      ? Icons.campaign_rounded
                                      : Icons.inventory_2_outlined,
                                  color:
                                      isRequest
                                          ? kPremiumRed
                                          : Colors.grey.shade400,
                                ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$roleText $otherUserName',
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(height: 1),
                ),

                // Math Breakdown
                if (isRental) ...[
                  _buildReceiptRow(
                    'Rental Fee',
                    'AED ${transaction['total_rental_cost']}',
                  ),
                  const SizedBox(height: 12),
                  _buildReceiptRow(
                    'Security Deposit',
                    'AED ${transaction['security_deposit']}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1),
                  ),
                  _buildReceiptRow(
                    'Total Paid',
                    'AED $totalDisplayed',
                    isTotal: true,
                    isPositive: !isBuyer,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Colors.blue.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isBuyer
                                ? 'Your AED ${transaction['security_deposit']} deposit will be refunded when the item is returned safely.'
                                : 'You are holding a AED ${transaction['security_deposit']} deposit. Ensure it is returned upon safe drop-off.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _buildReceiptRow('Agreed Price', 'AED $totalDisplayed'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1),
                  ),
                  _buildReceiptRow(
                    'Total Paid',
                    'AED $totalDisplayed',
                    isTotal: true,
                    isPositive: !isBuyer,
                  ),
                ],

                const SizedBox(height: 32),

                // Footer Metadata
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRANSACTION ID',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: kTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '#$shortId',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: kTextPrimary,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'STATUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: kTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildStatusPill(status, isRental),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isTotal = false,
    bool isPositive = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? kTextPrimary : kTextSecondary,
          ),
        ),
        Text(
          isTotal && isPositive ? '+$value' : value,
          style: TextStyle(
            fontSize: isTotal ? 20 : 14,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
            color:
                isTotal
                    ? (isPositive ? Colors.green.shade700 : kTextPrimary)
                    : kTextPrimary,
          ),
        ),
      ],
    );
  }
  // =====================================================================

  Widget _buildStatusPill(String status, bool isRental) {
    Color bgColor = Colors.grey.shade100;
    Color textColor = Colors.grey.shade700;
    String label = 'Unknown';

    if (isRental) {
      switch (status) {
        case 'active':
          bgColor = Colors.green.shade50;
          textColor = Colors.green.shade700;
          label = 'Active Rental';
          break;
        case 'completed':
          bgColor = Colors.deepPurple.shade50;
          textColor = Colors.deepPurple;
          label = 'Completed';
          break;
        case 'cancelled':
          bgColor = Colors.red.shade50;
          textColor = Colors.red;
          label = 'Refunded';
          break;
      }
    } else {
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
      }
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
                ? "When you buy or rent an item,\nit will appear here."
                : "When someone buys or rents your item,\nit will appear here.",
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
