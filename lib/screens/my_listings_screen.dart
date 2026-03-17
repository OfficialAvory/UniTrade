import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
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
  String _currentFilter = 'All'; // 'All', 'Active', 'Sold'

  @override
  void initState() {
    super.initState();
    _fetchMyListings();
  }

  Future<void> _fetchMyListings() async {
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final listingsData = await Supabase.instance.client
          .from('listings')
          .select('*')
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _myListings = List<Map<String, dynamic>>.from(listingsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- STATS COMPUTATION ---
  int get _activeCount =>
      _myListings.where((i) => !(i['is_sold'] ?? false)).length;
  int get _soldCount => _myListings.where((i) => i['is_sold'] == true).length;
  double get _totalEarnings => _myListings
      .where((i) => i['is_sold'] == true)
      .fold(0.0, (sum, item) => sum + (item['price'] as num).toDouble());

  List<Map<String, dynamic>> get _filteredListings {
    if (_currentFilter == 'Active') {
      return _myListings.where((i) => !(i['is_sold'] ?? false)).toList();
    } else if (_currentFilter == 'Sold') {
      return _myListings.where((i) => i['is_sold'] == true).toList();
    }
    return _myListings;
  }

  // --- SOLD STATUS LOGIC ---
  Future<void> _toggleSoldStatus(dynamic itemId, bool currentStatus) async {
    if (currentStatus == true) {
      await _updateListingInDatabase(itemId, false, null);
      return;
    }
    _showBuyerSelectionSheet(itemId);
  }

  void _showBuyerSelectionSheet(dynamic itemId) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        // <-- Use sheetContext here
        return FutureBuilder(
          future: Supabase.instance.client
              .from('chats')
              .select('buyer_id, profiles!chats_buyer_id_fkey(full_name)')
              .eq('listing_id', itemId),
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
                      fontWeight: FontWeight.w800,
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
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await _updateListingInDatabase(
                                itemId,
                                true,
                                buyerId,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _updateListingInDatabase(itemId, true, null);
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
                          fontWeight: FontWeight.w600,
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
  ) async {
    try {
      // .select() forces Supabase to return the updated row.
      // If RLS blocks it, the response will be empty.
      final response =
          await Supabase.instance.client
              .from('listings')
              .update({'is_sold': isSold, 'buyer_id': buyerId})
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

      await _fetchMyListings();

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
      // .select() forces Supabase to return the deleted row.
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

      await _fetchMyListings();
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

  // ============================================================================
  // PROFESSIONAL OPTIONS MENU
  // ============================================================================
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
              // Small handle indicator
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Context Header
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Menu Options
              ListTile(
                leading: const Icon(
                  Icons.ios_share_rounded,
                  color: Colors.black87,
                ),
                title: const Text(
                  'Share Listing',
                  style: TextStyle(fontWeight: FontWeight.w600),
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
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext); // Pop the sheet first

                    // Use the outer context to push the screen
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditListingScreen(item: item),
                      ),
                    );

                    if (updated == true) {
                      await _fetchMyListings(); // Ensure we wait for fetch
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
                    fontWeight: FontWeight.w600,
                    color:
                        isSold ? Colors.orange.shade800 : Colors.green.shade700,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _toggleSoldStatus(item['id'], isSold);
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
                    fontWeight: FontWeight.w600,
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

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'My Store',
          style: TextStyle(fontWeight: FontWeight.w800, color: kTextPrimary),
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
                onRefresh: _fetchMyListings,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. STATS BANNER
                          _buildStatsHeader(),

                          // 2. INTERACTIVE FILTER TABS
                          _buildFilterTabs(),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // 3. THE GRID
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

                    // Padding at bottom
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              ),
    );
  }

  // --- COMPONENT WIDGETS ---

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
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children:
            ['All', 'Active', 'Sold'].map((filter) {
              final isSelected = _currentFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(
                    filter,
                    style: TextStyle(
                      color: isSelected ? Colors.white : kTextPrimary,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
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
            // IMAGE SECTION
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
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),

                  // THE CLEAN "OPTIONS" MENU ICON
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

            // DETAILS SECTION
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
                      fontWeight: FontWeight.w600,
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
                      fontWeight: FontWeight.w800,
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
