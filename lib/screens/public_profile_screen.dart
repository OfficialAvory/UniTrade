import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'item_details_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class PublicProfileScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;

  const PublicProfileScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _sellerListings = [];
  List<Map<String, dynamic>> _sellerReviews = [];

  double _averageRating = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchSellerData();
  }

  Future<void> _fetchSellerData() async {
    try {
      // 1. Fetch their listings
      final listingsData = await Supabase.instance.client
          .from('listings')
          .select('*')
          .eq('seller_id', widget.sellerId)
          .order('created_at', ascending: false);

      // 2. Fetch their reviews
      final reviewsData = await Supabase.instance.client
          .from('reviews')
          .select('*, profiles!reviews_buyer_id_fkey(full_name)')
          .eq('seller_id', widget.sellerId)
          .order('created_at', ascending: false);

      // 3. Calculate average rating
      double totalStars = 0;
      for (var review in reviewsData) {
        totalStars += (review['rating'] as num).toDouble();
      }

      final average =
          reviewsData.isNotEmpty ? (totalStars / reviewsData.length) : 0.0;

      if (mounted) {
        setState(() {
          _sellerListings = List<Map<String, dynamic>>.from(listingsData);
          _sellerReviews = List<Map<String, dynamic>>.from(reviewsData);
          _averageRating = average;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
        // Title completely removed so it only shows the back button!
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: kPremiumRed),
              )
              : DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    // --- TOP HEADER ---
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.only(bottom: 24, top: 12),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: kPremiumRed.withOpacity(0.1),
                            child: Text(
                              widget.sellerName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: kPremiumRed,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.sellerName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: kTextPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Rating Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _sellerReviews.isNotEmpty
                                      ? '${_averageRating.toStringAsFixed(1)}  •  ${_sellerReviews.length} reviews'
                                      : 'No reviews yet',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kTextPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- TABS ---
                    Container(
                      color: Colors.white,
                      child: const TabBar(
                        labelColor: kPremiumRed,
                        unselectedLabelColor: kTextSecondary,
                        indicatorColor: kPremiumRed,
                        indicatorWeight: 3,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        tabs: [Tab(text: 'Listings'), Tab(text: 'Reviews')],
                      ),
                    ),

                    // --- TAB VIEWS ---
                    Expanded(
                      child: TabBarView(
                        children: [
                          // TAB 1: Listings
                          _sellerListings.isEmpty
                              ? const Center(
                                child: Text(
                                  "This user has no active items.",
                                  style: TextStyle(
                                    color: kTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                              : GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 0.75,
                                    ),
                                itemCount: _sellerListings.length,
                                itemBuilder: (context, index) {
                                  return _buildProductCard(
                                    _sellerListings[index],
                                  );
                                },
                              ),

                          // TAB 2: Reviews
                          _sellerReviews.isEmpty
                              ? const Center(
                                child: Text(
                                  "No reviews yet.",
                                  style: TextStyle(
                                    color: kTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                              : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _sellerReviews.length,
                                separatorBuilder:
                                    (context, index) => const Divider(
                                      height: 32,
                                      color: Colors.black12,
                                    ),
                                itemBuilder: (context, index) {
                                  final review = _sellerReviews[index];
                                  final reviewerName =
                                      review['profiles']?['full_name'] ??
                                      'Unknown User';
                                  final rating = review['rating'];
                                  final comment = review['comment'] ?? '';
                                  final date = DateFormat('MMM d, yyyy').format(
                                    DateTime.parse(review['created_at']),
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4.0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              reviewerName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: kTextPrimary,
                                              ),
                                            ),
                                            Text(
                                              date,
                                              style: const TextStyle(
                                                color: kTextSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: List.generate(5, (
                                            starIndex,
                                          ) {
                                            return Icon(
                                              starIndex < rating
                                                  ? Icons.star_rounded
                                                  : Icons.star_border_rounded,
                                              color: Colors.amber,
                                              size: 18,
                                            );
                                          }),
                                        ),
                                        if (comment.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            comment,
                                            style: const TextStyle(
                                              color: kTextPrimary,
                                              height: 1.4,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item) {
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
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
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
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                  if (isSold)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: isSold ? TextDecoration.lineThrough : null,
                      color: isSold ? Colors.grey : kTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${item['price']}',
                    style: TextStyle(
                      color: isSold ? Colors.grey : kPremiumRed,
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
