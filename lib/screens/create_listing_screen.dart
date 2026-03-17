import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Define a Premium Red Color Constant
const Color kPremiumRed = Color(0xFFD32F2F); // Deep, professional red
const Color kBackground = Color(0xFFF5F5F7); // "Apple" style light grey
const Color kSurface = Colors.white;

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  // --- STATE ---
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _rentalPriceController = TextEditingController();
  final _depositController = TextEditingController();

  String _selectedListingType = 'Sell'; // Default to Sell
  final List<String> _listingTypes = ['Sell', 'Rent', 'Both'];

  String? _selectedCategory;
  final List<String> _categories = [
    'Textbooks',
    'Electronics',
    'Dorm Supplies',
    'Clothing',
    'Other',
  ];

  String? _selectedCondition;
  final List<String> _conditions = [
    'Brand New',
    'Like New',
    'Lightly Used',
    'Well Used',
    'Heavily Used',
  ];

  String? _selectedMeetup;
  final List<String> _meetupSpots = [
    'Main Library',
    'Student Center',
    'North Dorms',
    'South Dorms',
    'Coffee Shop',
    'Campus Gym',
    'Other',
  ];

  List<XFile> _imageFiles = [];
  bool _isLoading = false;

  // --- LOGIC ---

  bool get isSelling =>
      _selectedListingType == 'Sell' || _selectedListingType == 'Both';
  bool get isRenting =>
      _selectedListingType == 'Rent' || _selectedListingType == 'Both';

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 70);

    if (images.isNotEmpty) {
      setState(() {
        final totalImages = _imageFiles.toList()..addAll(images);
        if (totalImages.length > 4) {
          _imageFiles = totalImages.sublist(0, 4);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Maximum 4 images allowed.'),
                backgroundColor: Colors.black87,
              ),
            );
          }
        } else {
          _imageFiles = totalImages;
        }
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  Future<void> _uploadListing() async {
    // Dynamic Validation based on Listing Type
    bool hasMissingPrices = false;
    if (isSelling && _priceController.text.trim().isEmpty)
      hasMissingPrices = true;
    if (isRenting &&
        (_rentalPriceController.text.trim().isEmpty ||
            _depositController.text.trim().isEmpty)) {
      hasMissingPrices = true;
    }

    if (_titleController.text.trim().isEmpty ||
        hasMissingPrices ||
        _selectedCategory == null ||
        _selectedCondition == null ||
        _selectedMeetup == null ||
        _imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields and add a photo.'),
          backgroundColor: kPremiumRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      List<String> uploadedImageUrls = [];

      // 1. Upload Images
      for (var i = 0; i < _imageFiles.length; i++) {
        final file = _imageFiles[i];
        final imageExtension = file.name.split('.').last;
        final imagePath =
            '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.$imageExtension';
        final imageBytes = await file.readAsBytes();

        await supabase.storage
            .from('listings')
            .uploadBinary(
              imagePath,
              imageBytes,
              fileOptions: const FileOptions(upsert: true),
            );

        final imageUrl = supabase.storage
            .from('listings')
            .getPublicUrl(imagePath);
        uploadedImageUrls.add(imageUrl);
      }

      // 2. Insert Data
      await supabase.from('listings').insert({
        'seller_id': userId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'listing_type':
            _selectedListingType.toLowerCase(), // 'sell', 'rent', or 'both'
        'price': isSelling ? double.parse(_priceController.text.trim()) : null,
        'rental_price_per_day':
            isRenting ? double.parse(_rentalPriceController.text.trim()) : null,
        'security_deposit':
            isRenting ? double.parse(_depositController.text.trim()) : null,
        'is_available': true, // Standard for newly created items
        'category': _selectedCategory,
        'condition': _selectedCondition,
        'meetup_spot': _selectedMeetup,
        'image_url': uploadedImageUrls.first,
        'image_urls': uploadedImageUrls,
      });

      if (mounted) {
        Navigator.pop(context, true);
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

  // --- STYLING HELPERS ---

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

  // --- WIDGET BUILD ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'New Listing',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Optional reset logic
            },
            child: Text('Reset', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1. PHOTO GALLERY ---
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'PHOTOS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  _buildPhotoGallery(),
                  const SizedBox(height: 24),

                  // --- 2. MAIN FORM CARD ---
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // LISTING TYPE SELECTOR
                        const Text(
                          'I want to:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildListingTypeSelector(),
                        const SizedBox(height: 24),

                        // Title
                        TextFormField(
                          controller: _titleController,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          decoration: _premiumInputDecoration(
                            'What is this item?',
                            Icons.local_offer_outlined,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Animated Price Fields based on selection
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: Column(
                            children: [
                              if (isSelling) ...[
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
                                  ),
                                  decoration: _premiumInputDecoration(
                                    'Sale Price',
                                    Icons.attach_money,
                                    prefix: 'AED ',
                                  ),
                                ),
                                if (isRenting) const SizedBox(height: 20),
                              ],

                              if (isRenting) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _rentalPriceController,
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
                                        ),
                                        decoration: _premiumInputDecoration(
                                          'Per Day',
                                          Icons.calendar_today_outlined,
                                          prefix: 'AED ',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _depositController,
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
                                        ),
                                        decoration: _premiumInputDecoration(
                                          'Deposit',
                                          Icons.shield_outlined,
                                          prefix: 'AED ',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Category
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          decoration: _premiumInputDecoration(
                            'Category',
                            Icons.category_outlined,
                          ),
                          items:
                              _categories
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() => _selectedCategory = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- 3. DETAILS CARD ---
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'DETAILS',
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
                          value: _selectedCondition,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          decoration: _premiumInputDecoration(
                            'Condition',
                            Icons.verified_outlined,
                          ),
                          items:
                              _conditions
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (v) => setState(() => _selectedCondition = v),
                        ),
                        const SizedBox(height: 20),

                        DropdownButtonFormField<String>(
                          value: _selectedMeetup,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          decoration: _premiumInputDecoration(
                            'Meetup Location',
                            Icons.location_on_outlined,
                          ),
                          items:
                              _meetupSpots
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() => _selectedMeetup = v),
                        ),
                        const SizedBox(height: 20),

                        TextFormField(
                          controller: _descController,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: _premiumInputDecoration(
                            'Description (Optional)',
                            Icons.notes_rounded,
                          ).copyWith(alignLabelWithHint: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- 4. BOTTOM ACTION BAR ---
          Container(
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
                onPressed: _isLoading ? null : _uploadListing,
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
                          'Post Listing',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- NEW: LISTING TYPE SELECTOR ---
  Widget _buildListingTypeSelector() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children:
            _listingTypes.map((type) {
              final isSelected = _selectedListingType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedListingType = type;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
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
                      type,
                      style: TextStyle(
                        color: isSelected ? kPremiumRed : Colors.grey.shade600,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  // --- PHOTO GALLERY WIDGET ---
  Widget _buildPhotoGallery() {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount:
            _imageFiles.length < 4
                ? _imageFiles.length + 1
                : _imageFiles.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          if (index == _imageFiles.length && _imageFiles.length < 4) {
            return GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      color: kPremiumRed.withOpacity(0.8),
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: kPremiumRed.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FutureBuilder<Uint8List>(
                    future: _imageFiles[index].readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          height: 120,
                          width: 100,
                        );
                      }
                      return Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removeImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
