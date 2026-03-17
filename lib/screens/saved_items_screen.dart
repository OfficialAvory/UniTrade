import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'item_details_screen.dart';
import 'chat_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class SavedItemsScreen extends StatefulWidget {
  const SavedItemsScreen({super.key});

  @override
  State<SavedItemsScreen> createState() => _SavedItemsScreenState();
}

class _SavedItemsScreenState extends State<SavedItemsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allSavedListings = [];
  List<Map<String, dynamic>> _filteredListings = [];
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  // For category filtering
  String _selectedCategory = 'All';
  List<String> _dynamicCategories = ['All'];

  // NEW: Realtime channel for background syncing
  late final RealtimeChannel _savedChannel;

  @override
  void initState() {
    super.initState();
    _fetchSavedItems();
    _setupRealtime();
  }

  // NEW: Setup Realtime listener
  void _setupRealtime() {
    _savedChannel = Supabase.instance.client.channel('public:saved_items_sync');
    _savedChannel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'saved_items',
          callback: (payload) {
            // Fetch silently to avoid showing the loading spinner and flickering the UI
            _fetchSavedItems(silent: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    // NEW: Clean up the channel when the widget is destroyed
    Supabase.instance.client.removeChannel(_savedChannel);
    super.dispose();
  }

  // UPDATED: Added a 'silent' parameter so background updates don't trigger the loading UI
  Future<void> _fetchSavedItems({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final data = await Supabase.instance.client
          .from('saved_items')
          .select('listings(*)')
          .eq('user_id', _currentUserId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allSavedListings =
              data
                  .map((item) => item['listings'] as Map<String, dynamic>)
                  .toList();

          // Dynamically build category list based on what is saved
          Set<String> uniqueCategories = {'All'};
          for (var item in _allSavedListings) {
            if (item['category'] != null) {
              uniqueCategories.add(item['category']);
            }
          }
          _dynamicCategories = uniqueCategories.toList();

          _applyFilter(); // Filter items based on current selection
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint('Error loading saved items: $e');
      }
    }
  }

  void _applyFilter() {
    if (_selectedCategory == 'All') {
      _filteredListings = List.from(_allSavedListings);
    } else {
      _filteredListings =
          _allSavedListings
              .where((item) => item['category'] == _selectedCategory)
              .toList();
    }
  }

  // Quick Unsave
  Future<void> _quickUnsave(String listingId) async {
    // Optimistically remove it from UI first so it feels instant
    setState(() {
      _allSavedListings.removeWhere((item) => item['id'] == listingId);
      _applyFilter();
    });

    try {
      await Supabase.instance.client
          .from('saved_items')
          .delete()
          .eq('user_id', _currentUserId)
          .eq('listing_id', listingId);
    } catch (e) {
      _fetchSavedItems(); // Revert on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing item: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    }
  }

  // Quick Make Offer Modal
  void _showQuickOfferDialog(Map<String, dynamic> item) {
    final TextEditingController offerController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Make an Offer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kTextPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Asking price: AED ${item['price']}',
                style: const TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: offerController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
                decoration: InputDecoration(
                  prefixText: 'AED ',
                  prefixStyle: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 24,
                  ),
                  filled: true,
                  fillColor: kBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: kPremiumRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    final offerAmount = offerController.text.trim();
                    if (offerAmount.isEmpty) return;
                    Navigator.pop(context); // Close modal
                    await _sendQuickOffer(item, offerAmount);
                  },
                  child: const Text(
                    'Send Offer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendQuickOffer(Map<String, dynamic> item, String amount) async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Fetch seller profile to get their name for the ChatScreen
      final profileData =
          await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', item['seller_id'])
              .single();
      final sellerName = profileData['full_name'] ?? 'Unknown User';

      // 2. Check if chat exists or create one
      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', item['id'])
          .eq('buyer_id', _currentUserId);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': item['id'],
                  'buyer_id': _currentUserId,
                  'seller_id': item['seller_id'],
                })
                .select('id')
                .single();
        chatId = newChat['id'];
      }

      // 3. Send Offer Message
      await supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': _currentUserId,
        'content': amount,
        'is_offer': true,
      });

      // 4. Navigate to Chat
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: sellerName,
                  itemTitle: item['title'],
                ),
          ),
        ).then(
          (_) => _fetchSavedItems(silent: true),
        ); // Refresh silently when coming back
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        title: const Text(
          'Saved Items',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextPrimary,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
        backgroundColor: kBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          // CATEGORY TABS
          if (_dynamicCategories.length > 1)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _dynamicCategories.length,
                itemBuilder: (context, index) {
                  final category = _dynamicCategories[index];
                  final isSelected = category == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? Colors.white : kTextSecondary,
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
                          color:
                              isSelected ? kPremiumRed : Colors.grey.shade300,
                        ),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = category;
                          _applyFilter();
                        });
                      },
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child:
                _isLoading
                    ? const Center(
                      child: CircularProgressIndicator(color: kPremiumRed),
                    )
                    : RefreshIndicator(
                      onRefresh: () async {
                        await _fetchSavedItems();
                      },
                      color: kPremiumRed,
                      backgroundColor: Colors.white,
                      child:
                          _filteredListings.isEmpty
                              ? _buildEmptyState()
                              : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  24,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 0.58,
                                    ),
                                itemCount: _filteredListings.length,
                                itemBuilder: (context, index) {
                                  return _buildProductCard(
                                    _filteredListings[index],
                                  );
                                },
                              ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item) {
    final bool isSold = item['is_sold'] ?? false;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailsScreen(item: item),
          ),
        );
        _fetchSavedItems(silent: true);
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
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey,
                              ),
                            ),
                      ),
                    ),
                  ),

                  // SOLD OVERLAY
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
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),

                  // QUICK UNSAVE HEART
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _quickUnsave(item['id']),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: kPremiumRed,
                          size: 18,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isSold ? Colors.grey : kTextPrimary,
                      decoration: isSold ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

                  // QUICK OFFER BUTTON
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32, // Sleek, thin button
                    child: OutlinedButton(
                      onPressed:
                          isSold || item['seller_id'] == _currentUserId
                              ? null
                              : () => _showQuickOfferDialog(item),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(
                          color: isSold ? Colors.grey.shade300 : kPremiumRed,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isSold ? 'Unavailable' : 'Make Offer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSold ? Colors.grey : kPremiumRed,
                        ),
                      ),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "No items here",
            style: TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Save items you love to easily find them later.",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
