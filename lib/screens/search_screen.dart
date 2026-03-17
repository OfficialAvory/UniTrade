import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'item_details_screen.dart';

class SearchScreen extends StatefulWidget {
  // NEW: Accepts the text typed from the Home Screen
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the controller with the text from the Home screen
    _searchController = TextEditingController(text: widget.initialQuery ?? '');

    // If they typed something on the home screen, automatically run the search!
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('listings')
          .select('*')
          .ilike('title', '%$query%')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Matched background to Home screen
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Container(
          height: 40, // Slightly thinner to match the standard app bar height
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9), // kOffWhite from Home screen
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _searchController,
            onSubmitted: _performSearch, // Search when they hit enter
            autofocus:
                widget.initialQuery == null ||
                widget
                    .initialQuery!
                    .isEmpty, // Only autofocus if it's a fresh search
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search collection...',
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
              prefixIcon: const Icon(
                Icons.search,
                color: Colors.grey,
                size: 20,
              ),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          color: Colors.black54,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                      : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              )
              : _searchResults.isEmpty && _searchController.text.isNotEmpty
              ? const Center(
                child: Text(
                  'No items found.',
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
              )
              : _searchResults.isEmpty
              ? const Center(
                child: Text(
                  'Type to start searching!',
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
              )
              : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75, // Matches the Home Screen cards
                ),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  return _buildProductCard(_searchResults[index]);
                },
              ),
    );
  }

  // Uses the exact same design as the Home Screen
  Widget _buildProductCard(Map<String, dynamic> item) {
    final bool isSold = item['is_sold'] ?? false;

    return GestureDetector(
      onTap: () {
        if (isSold) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This item has already been sold!'),
              duration: Duration(seconds: 1),
            ),
          );
          return;
        }

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
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.deepPurple,
                            ),
                          );
                        },
                        errorBuilder:
                            (context, error, stackTrace) => const Center(
                              child: Icon(
                                Icons.broken_image,
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
                          top: Radius.circular(16),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'SOLD',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
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
                      color: isSold ? Colors.grey : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AED ${item['price']}',
                    style: TextStyle(
                      color: isSold ? Colors.grey : Colors.deepPurple,
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
