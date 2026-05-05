import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'onboarding_screen.dart';
import 'item_details_screen.dart';
import 'search_screen.dart';
import 'create_request_screen.dart';
import 'chat_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- STATE ---
  bool _isLoading = true;
  String _fullName = '';

  // Tab State
  int _selectedTabIndex = 0; // 0 for "For Sale", 1 for "Looking For"

  // Data Buckets (For Sale)
  List<Map<String, dynamic>> _freshFinds = [];
  List<Map<String, dynamic>> _textbooks = [];
  List<Map<String, dynamic>> _electronics = [];
  List<Map<String, dynamic>> _clothing = [];
  List<Map<String, dynamic>> _dormSupplies = [];
  List<Map<String, dynamic>> _other = [];

  // Store saved item IDs for quick reference
  Set<String> _savedItemIds = {};

  final TextEditingController _homeSearchController = TextEditingController();

  // --- INIT ---
  @override
  void initState() {
    super.initState();
    _initializeHome();
  }

  @override
  void dispose() {
    _homeSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeHome() async {
    await _fetchProfile();
    await Future.wait([_fetchAllListings(), _fetchSavedItemIds()]);
  }

  Future<void> _fetchProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data =
          await Supabase.instance.client
              .from('profiles')
              .select('full_name')
              .eq('id', userId)
              .single();

      if (mounted && data['full_name'] != null) {
        setState(() => _fullName = data['full_name']);
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _fetchSavedItemIds() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
          .from('saved_items')
          .select('listing_id')
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          _savedItemIds =
              data.map<String>((e) => e['listing_id'] as String).toSet();
        });
      }
    } catch (e) {
      debugPrint('Error fetching saved item IDs: $e');
    }
  }

  Future<void> _toggleFavorite(String listingId) async {
    final isSaved = _savedItemIds.contains(listingId);
    final userId = Supabase.instance.client.auth.currentUser!.id;

    setState(() {
      if (isSaved) {
        _savedItemIds.remove(listingId);
      } else {
        _savedItemIds.add(listingId);
      }
    });

    try {
      if (isSaved) {
        await Supabase.instance.client
            .from('saved_items')
            .delete()
            .eq('user_id', userId)
            .eq('listing_id', listingId);
      } else {
        await Supabase.instance.client.from('saved_items').insert({
          'user_id': userId,
          'listing_id': listingId,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (isSaved) {
            _savedItemIds.add(listingId);
          } else {
            _savedItemIds.remove(listingId);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating favorites: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    }
  }

  Future<void> _fetchAllListings() async {
    try {
      final data = await Supabase.instance.client
          .from('listings')
          .select('*')
          .eq('is_sold', false)
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        final allItems = List<Map<String, dynamic>>.from(data);

        setState(() {
          _freshFinds = allItems.take(4).toList();
          _textbooks =
              allItems.where((i) => i['category'] == 'Textbooks').toList();
          _electronics =
              allItems.where((i) => i['category'] == 'Electronics').toList();
          _clothing =
              allItems.where((i) => i['category'] == 'Clothing').toList();
          _dormSupplies =
              allItems.where((i) => i['category'] == 'Dorm Supplies').toList();
          _other = allItems.where((i) => i['category'] == 'Other').toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error fetching home data: $e');
    }
  }

  void _submitSearch(String query) {
    if (query.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(initialQuery: query.trim()),
      ),
    ).then((_) {
      _homeSearchController.clear();
      _fetchSavedItemIds();
    });
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // 1. GREETING SECTION
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fullName.isEmpty ? 'Hello!' : 'Hi, $_fullName',
                              style: const TextStyle(
                                color: kTextPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Find what you need on campus today.",
                              style: TextStyle(
                                color: kTextSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 22,
                        child: IconButton(
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            color: kTextPrimary,
                            size: 22,
                          ),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. SEARCH BAR
              SliverAppBar(
                backgroundColor: kBackground,
                elevation: 0,
                pinned: true,
                floating: false,
                primary: false,
                automaticallyImplyLeading: false,
                toolbarHeight: 70,
                titleSpacing: 0,
                title: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _homeSearchController,
                      builder: (context, value, child) {
                        return TextField(
                          controller: _homeSearchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _submitSearch,
                          cursorColor: kPremiumRed,
                          decoration: InputDecoration(
                            hintText: 'What are you looking for?',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: kPremiumRed,
                            ),
                            suffixIcon:
                                value.text.isNotEmpty
                                    ? IconButton(
                                      icon: const Icon(
                                        Icons.cancel_rounded,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        _homeSearchController.clear();
                                      },
                                    )
                                    : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 3. SEGMENTED HEADER TABS
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Stack(
                      children: [
                        AnimatedAlign(
                          alignment:
                              _selectedTabIndex == 0
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: FractionallySizedBox(
                            widthFactor: 0.5,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap:
                                    () => setState(() => _selectedTabIndex = 0),
                                child: Center(
                                  child: Text(
                                    'For Sale',
                                    style: TextStyle(
                                      color:
                                          _selectedTabIndex == 0
                                              ? kTextPrimary
                                              : kTextSecondary,
                                      fontWeight:
                                          _selectedTabIndex == 0
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap:
                                    () => setState(() => _selectedTabIndex = 1),
                                child: Center(
                                  child: Text(
                                    'Looking For',
                                    style: TextStyle(
                                      color:
                                          _selectedTabIndex == 1
                                              ? kTextPrimary
                                              : kTextSecondary,
                                      fontWeight:
                                          _selectedTabIndex == 1
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ];
          },
          body:
              _isLoading
                  ? _buildShimmerLoadingState()
                  : _selectedTabIndex == 0
                  ? _buildForSaleBody()
                  : _buildLookingForBody(),
        ),
      ),
    );
  }

  // --- SHIMMER LOADING STATE ---
  Widget _buildShimmerLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Fresh on Campus', showSeeAll: false),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemBuilder:
                    (_, __) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 24,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder:
                    (_, __) => Container(
                      width: 150,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- "FOR SALE" BODY ---
  Widget _buildForSaleBody() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchAllListings();
        await _fetchSavedItemIds();
      },
      color: kPremiumRed,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_freshFinds.isNotEmpty) ...[
              _buildSectionHeader('Fresh on Campus', showSeeAll: false),
              _buildFreshFindsGrid(),
            ],
            _buildCategoryLane('Textbooks', _textbooks),
            _buildCategoryLane('Electronics', _electronics),
            _buildCategoryLane('Clothing', _clothing),
            _buildCategoryLane('Dorm Supplies', _dormSupplies),
            _buildCategoryLane('Other Essentials', _other),
          ],
        ),
      ),
    );
  }

  // --- "LOOKING FOR" BODY ---
  Widget _buildLookingForBody() {
    return FutureBuilder(
      future: Supabase.instance.client
          .from('requests')
          .select('*, profiles:requester_id(full_name)')
          .eq('is_fulfilled', false)
          .order('created_at', ascending: false),
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: kPremiumRed),
          );
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: kPremiumRed.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          size: 80,
                          color: kPremiumRed,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "No active requests right now.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Can't find what you need? Post a request and sellers will message you directly!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: kTextSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => const CreateRequestScreen(),
                              ),
                            );
                            if (result == true) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Post a Request',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPremiumRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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

        return RefreshIndicator(
          color: kPremiumRed,
          onRefresh: () async => setState(() {}),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateRequestScreen(),
                          ),
                        );
                        if (result == true) {
                          setState(() {});
                        }
                      },
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Post a Request',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPremiumRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final req = requests[index];
                    return _buildRequestCard(req);
                  }, childCount: requests.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        );
      },
    );
  }

  // --- REQUEST WIDGETS & METHODS ---

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final String requesterName = req['profiles']['full_name'] ?? 'A Student';
    final String currentUserId = Supabase.instance.client.auth.currentUser!.id;
    final bool isMyRequest = req['requester_id'] == currentUserId;

    // Optional new fields (will be null if you haven't added them to DB yet)
    final String? imageUrl = req['reference_image'];
    final String? preferredCondition = req['preferred_condition'];
    final String? urgency = req['urgency'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reference Image OR User Avatar
                if (imageUrl != null && imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: kPremiumRed.withOpacity(0.1),
                    child: Text(
                      requesterName[0].toUpperCase(),
                      style: const TextStyle(
                        color: kPremiumRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                const SizedBox(width: 16),

                // Title and Requester Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Requested by $requesterName',
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Budget Box
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Willing to pay',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'AED ${req['budget']}',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Description
          if (req['description'] != null &&
              req['description'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                req['description'],
                style: const TextStyle(
                  color: kTextPrimary,
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
            ),

          // Details Tags (Condition & Urgency)
          if (preferredCondition != null || urgency != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Wrap(
                spacing: 8,
                children: [
                  if (preferredCondition != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Condition: $preferredCondition',
                        style: const TextStyle(
                          fontSize: 11,
                          color: kTextSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (urgency != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Needed: $urgency',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Bottom Action Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    req['category'],
                    style: const TextStyle(
                      color: kTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!isMyRequest)
                  ElevatedButton.icon(
                    onPressed: () => _startChatForRequest(req, requesterName),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                    label: const Text(
                      'I have this!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPremiumRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _deleteRequest(req['id']),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete Request'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startChatForRequest(
    Map<String, dynamic> req,
    String requesterName,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
    );

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser!.id;
      final requesterId = req['requester_id'];

      final existingChat =
          await Supabase.instance.client
              .from('chats')
              .select('id')
              .eq('buyer_id', requesterId)
              .eq('seller_id', currentUserId)
              .eq('request_id', req['id'])
              .maybeSingle();

      String chatId;

      if (existingChat != null) {
        chatId = existingChat['id'];
      } else {
        final newChat =
            await Supabase.instance.client
                .from('chats')
                .insert({
                  'buyer_id': requesterId,
                  'seller_id': currentUserId,
                  'request_id': req['id'],
                })
                .select('id')
                .single();
        chatId = newChat['id'];

        // --- NEW: AUTOMATED ICEBREAKER MESSAGE ---
        await Supabase.instance.client.from('messages').insert({
          'chat_id': chatId,
          'sender_id': currentUserId,
          'content': '👋 Hi! I have the "${req['title']}" you are looking for.',
        });
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: requesterName,
                  itemTitle: "Request: ${req['title']}",
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteRequest(String requestId) async {
    try {
      await Supabase.instance.client
          .from('requests')
          .delete()
          .eq('id', requestId);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // --- HOME SCREEN WIDGETS ---

  Widget _buildSectionHeader(
    String title, {
    bool showSeeAll = true,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (showSeeAll)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: kPremiumRed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFreshFindsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _freshFinds.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemBuilder: (context, index) {
          return _buildProductCard(_freshFinds[index], isFeatured: true);
        },
      ),
    );
  }

  Widget _buildCategoryLane(String title, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title,
          onSeeAll: () {
            _submitSearch(title == 'Other Essentials' ? 'Other' : title);
          },
        ),
        if (items.isEmpty)
          Container(
            height: 120,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.grey.shade200,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.grey.shade400,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  "No items here yet.",
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 240,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length > 10 ? 10 : items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                return _CompactProductCard(
                  item: items[index],
                  isSaved: _savedItemIds.contains(items[index]['id']),
                  onFavoriteToggle: () => _toggleFavorite(items[index]['id']),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> item, {
    bool isFeatured = false,
  }) {
    final condition = item['condition'] ?? 'Used';
    final isSaved = _savedItemIds.contains(item['id']);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailsScreen(item: item),
          ),
        ).then((_) => _fetchSavedItemIds());
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item['image_url'],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(color: Colors.white),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                            ),
                          ),
                    ),
                  ),
                  if (isFeatured)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kPremiumRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(item['id']),
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        radius: 14,
                        child: Icon(
                          isSaved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 16,
                          color: isSaved ? kPremiumRed : kTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        condition,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: kTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${item['price']}',
                    style: const TextStyle(
                      color: kPremiumRed,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
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

class _CompactProductCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isSaved;
  final VoidCallback onFavoriteToggle;

  const _CompactProductCard({
    required this.item,
    required this.isSaved,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ItemDetailsScreen(item: item),
          ),
        ).then((_) {
          context
              .findAncestorStateOfType<_HomeScreenState>()
              ?._fetchSavedItemIds();
        });
      },
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item['image_url'],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(color: Colors.white),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                            ),
                          ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onFavoriteToggle,
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.9),
                        radius: 12,
                        child: Icon(
                          isSaved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 14,
                          color: isSaved ? kPremiumRed : kTextSecondary,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: kTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${item['price']}',
                    style: const TextStyle(
                      color: kTextSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
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
