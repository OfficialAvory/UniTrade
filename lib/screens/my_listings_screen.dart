import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'item_details_screen.dart';
import 'edit_listing_screen.dart';

const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myListings = [];
  List<Map<String, dynamic>> _myReviews = [];
  double _rentalEarnings = 0.0; // NEW: Track rental earnings
  String _currentFilter = 'All'; // 'All', 'Active', 'Sold', 'Reviews'

  @override
  void initState() {
    super.initState();
    _fetchStoreData();
  }

  Future<void> _fetchStoreData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser!;

      // 1. Fetch Listings
      final listingsFuture = Supabase.instance.client
          .from('listings')
          .select('*')
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      // 2. Fetch Reviews
      final reviewsFuture = Supabase.instance.client
          .from('reviews')
          .select('''
            id,
            rating,
            comment,
            created_at,
            buyer:profiles!buyer_id(full_name),
            listings(title, image_url)
          ''')
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      // 3. NEW: Fetch paid Rentals to add to total earnings
      final rentalsFuture = Supabase.instance.client
          .from('rentals')
          .select('total_rental_cost')
          .eq('owner_id', user.id)
          .eq('payment_status', 'paid');

      final results = await Future.wait([
        listingsFuture,
        reviewsFuture,
        rentalsFuture,
      ]);

      if (mounted) {
        setState(() {
          _myListings = List<Map<String, dynamic>>.from(results[0]);
          _myReviews = List<Map<String, dynamic>>.from(results[1]);

          // Calculate rental earnings (Only the rental cost, excluding the deposit)
          final rentals = List<Map<String, dynamic>>.from(results[2]);
          _rentalEarnings = rentals.fold(
            0.0,
            (sum, r) => sum + (r['total_rental_cost'] as num).toDouble(),
          );

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error fetching store data: $e');
    }
  }

  // --- STATS COMPUTATION ---
  int get _activeCount =>
      _myListings.where((i) => !(i['is_sold'] ?? false)).length;
  int get _soldCount => _myListings.where((i) => i['is_sold'] == true).length;

  // NEW: Combine sale earnings + rental earnings
  double get _totalEarnings {
    final saleEarnings = _myListings
        .where((i) => i['is_sold'] == true)
        .fold(0.0, (sum, item) => sum + (item['price'] as num).toDouble());
    return saleEarnings + _rentalEarnings;
  }

  List<Map<String, dynamic>> get _filteredListings {
    if (_currentFilter == 'Active') {
      return _myListings.where((i) => !(i['is_sold'] ?? false)).toList();
    } else if (_currentFilter == 'Sold') {
      return _myListings.where((i) => i['is_sold'] == true).toList();
    }
    return _myListings;
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final date = DateTime.parse(isoString).toLocal();
    return DateFormat('MMM d, yyyy').format(date);
  }

  // --- SOLD STATUS LOGIC ---
  Future<void> _toggleSoldStatus(
    Map<String, dynamic> item,
    bool currentStatus,
  ) async {
    if (currentStatus == true) {
      await _updateListingInDatabase(item['id'], false, null, null);
      return;
    }
    _showBuyerSelectionSheet(item);
  }

  void _showFinalPriceDialog(Map<String, dynamic> item, String? buyerId) {
    final TextEditingController priceController = TextEditingController(
      text: item['price'].toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Final Sale Price',
            style: TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the final agreed amount to keep your store earnings accurate.',
                style: TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
                decoration: InputDecoration(
                  prefixText: 'AED ',
                  prefixStyle: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 20,
                  ),
                  filled: true,
                  fillColor: kBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: kTextSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final priceStr = priceController.text.trim();
                final double? finalPrice = double.tryParse(priceStr);
                Navigator.pop(ctx);
                _updateListingInDatabase(item['id'], true, buyerId, finalPrice);
              },
              child: const Text(
                'Confirm',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showBuyerSelectionSheet(Map<String, dynamic> item) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FutureBuilder(
          future: Supabase.instance.client
              .from('chats')
              .select('buyer_id, profiles!chats_buyer_id_fkey(full_name)')
              .eq('listing_id', item['id']),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(color: kPremiumRed),
                ),
              );
            }

            final chats = snapshot.data as List<dynamic>? ?? [];

            return Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mark as Sold',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Did you sell this to someone on Avory? Select them so they can leave a review.',
                    style: TextStyle(color: kTextSecondary),
                  ),
                  const SizedBox(height: 20),
                  if (chats.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "No active chats for this item.",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: chats.length,
                        separatorBuilder: (c, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final buyerName = chat['profiles']['full_name'];
                          final buyerId = chat['buyer_id'];

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: kPremiumRed.withOpacity(0.1),
                              child: Text(
                                buyerName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: kPremiumRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              buyerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.check_circle_outline,
                              color: Colors.grey,
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _showFinalPriceDialog(item, buyerId);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showFinalPriceDialog(item, null);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Sold externally / Skip',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateListingInDatabase(
    dynamic itemId,
    bool isSold,
    String? buyerId,
    double? finalPrice,
  ) async {
    try {
      final updateData = <String, dynamic>{
        'is_sold': isSold,
        'buyer_id': buyerId,
      };

      if (isSold && finalPrice != null) {
        updateData['price'] = finalPrice;
      }

      final response =
          await Supabase.instance.client
              .from('listings')
              .update(updateData)
              .eq('id', itemId)
              .select();

      if (response.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Update Blocked 🛑'),
                  content: const Text(
                    'Supabase blocked the status change. Please check your UPDATE RLS policies in the Supabase Dashboard.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        }
        return;
      }

      await _fetchStoreData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSold ? 'Marked as Sold' : 'Marked as Available'),
            backgroundColor: isSold ? Colors.green : kTextPrimary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    }
  }

  Future<void> _deleteItem(dynamic itemId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Listing'),
            content: const Text(
              'This action cannot be undone. Are you sure you want to delete this item?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: kTextSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: kPremiumRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      final response =
          await Supabase.instance.client
              .from('listings')
              .delete()
              .eq('id', itemId)
              .select();

      if (response.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Delete Blocked 🛑'),
                  content: const Text(
                    'Supabase blocked the deletion. Please check your DELETE RLS policies in the Supabase Dashboard.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        }
        return;
      }

      await _fetchStoreData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    }
  }

  void _shareItem(Map<String, dynamic> item) {
    final title = item['title'];
    final price = item['price'];
    Share.share('Check out my item on Avory: $title for AED $price!');
  }

  void _showManageOptions(Map<String, dynamic> item) {
    final bool isSold = item['is_sold'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        item['image_url'],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'AED ${item['price']}',
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.ios_share_rounded,
                  color: Colors.black87,
                ),
                title: const Text(
                  'Share Listing',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareItem(item);
                },
              ),
              if (!isSold)
                ListTile(
                  leading: const Icon(
                    Icons.edit_outlined,
                    color: Colors.black87,
                  ),
                  title: const Text(
                    'Edit Details',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditListingScreen(item: item),
                      ),
                    );
                    if (updated == true) {
                      await _fetchStoreData();
                    }
                  },
                ),
              ListTile(
                leading: Icon(
                  isSold
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                  color: isSold ? Colors.orange : Colors.green,
                ),
                title: Text(
                  isSold ? 'Mark as Available' : 'Mark as Sold',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        isSold ? Colors.orange.shade800 : Colors.green.shade700,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _toggleSoldStatus(item, isSold);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Delete Listing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _deleteItem(item['id']);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'My Store',
          style: TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: kPremiumRed),
              )
              : RefreshIndicator(
                color: kPremiumRed,
                onRefresh: _fetchStoreData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatsHeader(),
                          _buildFilterTabs(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    if (_currentFilter == 'Reviews') ...[
                      if (_myReviews.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.star_outline_rounded,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "No reviews yet.",
                                  style: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            return _buildReviewCard(_myReviews[index]);
                          }, childCount: _myReviews.length),
                        ),
                    ] else ...[
                      if (_filteredListings.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.dashboard_customize_outlined,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _myListings.isEmpty
                                      ? "You haven't posted any items yet."
                                      : "No items match this filter.",
                                  style: const TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.68,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              return _buildSellerListingCard(
                                _filteredListings[index],
                              );
                            }, childCount: _filteredListings.length),
                          ),
                        ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              ),
    );
  }

  Widget _buildStatsHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kTextPrimary, Colors.blueGrey.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatColumn('Active', _activeCount.toString()),
          Container(height: 40, width: 1, color: Colors.white24),
          _buildStatColumn('Sold', _soldCount.toString()),
          Container(height: 40, width: 1, color: Colors.white24),
          _buildStatColumn(
            'Earnings',
            'AED ${_totalEarnings.toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    final filters = ['All', 'Active', 'Sold', 'Reviews'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children:
              filters.map((filter) {
                final isSelected = _currentFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : kTextPrimary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: kPremiumRed,
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? kPremiumRed : Colors.grey.shade300,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _currentFilter = filter);
                      }
                    },
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final buyerName = review['buyer']['full_name'] ?? 'Unknown User';
    final initial = buyerName.isNotEmpty ? buyerName[0].toUpperCase() : '?';
    final rating = review['rating'] as int? ?? 5;
    final comment = review['comment'] ?? '';
    final dateString = _formatDate(review['created_at']);
    final itemTitle = review['listings']?['title'] ?? 'Unknown Item';
    final itemImage = review['listings']?['image_url'];

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: kPremiumRed.withOpacity(0.1),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: kPremiumRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buyerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Row(
                      children: List.generate(5, (index) {
                        return Icon(
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 16,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              Text(
                dateString,
                style: const TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(comment, style: const TextStyle(fontSize: 15, height: 1.4)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      itemImage != null
                          ? Image.network(
                            itemImage,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            width: 40,
                            height: 40,
                            color: Colors.grey.shade300,
                            child: const Icon(
                              Icons.image,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Item Sold',
                        style: TextStyle(
                          fontSize: 11,
                          color: kTextSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        itemTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerListingCard(Map<String, dynamic> item) {
    final bool isSold = item['is_sold'] ?? false;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailsScreen(item: item),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: ColorFiltered(
                      colorFilter:
                          isSold
                              ? const ColorFilter.mode(
                                Colors.grey,
                                BlendMode.saturation,
                              )
                              : const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              ),
                      child: Image.network(
                        item['image_url'],
                        fit: BoxFit.cover,
                        errorBuilder:
                            (ctx, err, stack) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey,
                              ),
                            ),
                      ),
                    ),
                  ),
                  if (isSold)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'SOLD',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _showManageOptions(item),
                      child: Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSold ? Colors.grey : kTextPrimary,
                      decoration: isSold ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${item['price']}',
                    style: TextStyle(
                      color: isSold ? Colors.grey : kPremiumRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
