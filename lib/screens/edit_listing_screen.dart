import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class EditListingScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const EditListingScreen({super.key, required this.item});

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _priceController;

  String? _selectedCategory;
  final List<String> _categories = [
    'Textbooks',
    'Electronics',
    'Dorm Supplies',
    'Clothing',
    'Other',
  ];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the text fields with the existing data
    _titleController = TextEditingController(text: widget.item['title']);
    _descController = TextEditingController(text: widget.item['description']);
    _priceController = TextEditingController(
      text: widget.item['price'].toString(),
    );

    // Ensure the category perfectly matches our dropdown list
    final category = widget.item['category'] as String?;
    if (category != null && _categories.contains(category)) {
      _selectedCategory = category;
    } else {
      _selectedCategory = 'Other';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _updateListing() async {
    if (_titleController.text.isEmpty ||
        _priceController.text.isEmpty ||
        _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields.'),
          backgroundColor: kPremiumRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Added .select() to force execution and return the updated row
      final response =
          await Supabase.instance.client
              .from('listings')
              .update({
                'title': _titleController.text.trim(),
                'description': _descController.text.trim(),
                'price': double.parse(_priceController.text.trim()),
                'category': _selectedCategory,
              })
              .eq('id', widget.item['id'])
              .select();

      // 2. Explicitly check if the update was blocked by RLS
      if (response.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder:
                (ctx) => AlertDialog(
                  title: const Text('Update Blocked 🛑'),
                  content: const Text(
                    'Supabase blocked the edit. Please check your UPDATE RLS policies in the Supabase Dashboard.',
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
        return; // Stop execution here
      }

      if (mounted) {
        Navigator.pop(context, true); // Go back and signal success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PREMIUM INPUT STYLING (Same as CreateListingScreen) ---
  InputDecoration _premiumInputDecoration(
    String label,
    IconData icon, {
    String? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixText: prefix,
      prefixStyle: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      prefixIcon: Icon(icon, size: 22, color: Colors.grey.shade400),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPremiumRed, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kPremiumRed.withOpacity(0.5)),
      ),
      floatingLabelStyle: const TextStyle(
        color: kPremiumRed,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      // We use a Stack to place the cinematic image behind the custom app bar
      body: Stack(
        children: [
          // 1. SCROLLABLE CONTENT
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              bottom: 120,
            ), // Space for sticky bottom bar
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. CINEMATIC IMAGE HEADER
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        widget.item['image_url'],
                        fit: BoxFit.cover,
                      ),
                      // Dark gradient overlay for the back button
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withOpacity(0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // "Image Locked" frosted glass badge
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Image cannot be changed',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // B. FORM CONTENT
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- MAIN DETAILS CARD ---
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          'MAIN DETAILS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _titleController,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kTextPrimary,
                              ),
                              decoration: _premiumInputDecoration(
                                'Item Title',
                                Icons.sell_outlined,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+\.?\d{0,2}'),
                                ),
                              ],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: kTextPrimary,
                              ),
                              decoration: _premiumInputDecoration(
                                'Price',
                                Icons.attach_money,
                                prefix: 'AED ',
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // --- ADDITIONAL INFO CARD ---
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          'ADDITIONAL INFO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              decoration: _premiumInputDecoration(
                                'Category',
                                Icons.category_outlined,
                              ),
                              items:
                                  _categories
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(
                                            c,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged:
                                  (v) => setState(() => _selectedCategory = v),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _descController,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                color: kTextPrimary,
                                height: 1.4,
                              ),
                              decoration: _premiumInputDecoration(
                                'Description',
                                Icons.notes_rounded,
                              ).copyWith(alignLabelWithHint: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. CUSTOM GLASS BACK BUTTON
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),

      // 3. STICKY BOTTOM ACTION BAR
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        decoration: BoxDecoration(
          color: kSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _updateListing,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPremiumRed,
              foregroundColor: Colors.white,
              elevation: 5,
              shadowColor: kPremiumRed.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child:
                _isLoading
                    ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
