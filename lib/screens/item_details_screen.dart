import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'chat_screen.dart';
import 'leave_review_screen.dart';
import 'public_profile_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class ItemDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> item;

  const ItemDetailsScreen({super.key, required this.item});

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  // --- STATE ---
  String _sellerName = 'Loading...';
  double? _sellerRating;
  int _sellerReviewCount = 0;

  bool _isStartingChat = false;
  bool _isSaved = false;
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  int _currentImageIndex = 0;
  List<String> _images = [];

  // Renting properties
  late bool _isSelling;
  late bool _isRenting;

  // --- INIT ---
  @override
  void initState() {
    super.initState();
    _fetchSellerInfo();
    _checkIfSaved();

    if (widget.item['image_urls'] != null &&
        widget.item['image_urls'] is List &&
        (widget.item['image_urls'] as List).isNotEmpty) {
      _images = List<String>.from(widget.item['image_urls']);
    } else {
      _images = [widget.item['image_url']];
    }

    final String type = widget.item['listing_type'] ?? 'sell';
    _isSelling = type == 'sell' || type == 'both';
    _isRenting = type == 'rent' || type == 'both';
  }

  // --- LOGIC ---
  Future<void> _fetchSellerInfo() async {
    try {
      final supabase = Supabase.instance.client;
      final sellerId = widget.item['seller_id'];

      final profileData =
          await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', sellerId)
              .single();

      final reviewsData = await supabase
          .from('reviews')
          .select('rating')
          .eq('seller_id', sellerId);

      double? average;
      if (reviewsData.isNotEmpty) {
        double total = 0;
        for (var review in reviewsData) {
          total += (review['rating'] as num).toDouble();
        }
        average = total / reviewsData.length;
      }

      if (mounted) {
        setState(() {
          _sellerName = profileData['full_name'] ?? 'Unknown User';
          _sellerRating = average;
          _sellerReviewCount = reviewsData.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sellerName = 'Unknown User');
      }
    }
  }

  Future<void> _checkIfSaved() async {
    try {
      final data = await Supabase.instance.client
          .from('saved_items')
          .select('id')
          .eq('user_id', _currentUserId)
          .eq('listing_id', widget.item['id']);

      if (mounted && data.isNotEmpty) {
        setState(() => _isSaved = true);
      }
    } catch (e) {
      // Silent fail
    }
  }

  // UPDATED: Optimistic UI toggle
  Future<void> _toggleSave() async {
    // 1. Instantly update UI
    final wasSaved = _isSaved;
    setState(() => _isSaved = !_isSaved);

    try {
      // 2. Perform DB action
      if (_isSaved) {
        await Supabase.instance.client.from('saved_items').insert({
          'user_id': _currentUserId,
          'listing_id': widget.item['id'],
        });
      } else {
        await Supabase.instance.client
            .from('saved_items')
            .delete()
            .eq('user_id', _currentUserId)
            .eq('listing_id', widget.item['id']);
      }
    } catch (e) {
      // 3. Revert if failed
      if (mounted) {
        setState(() => _isSaved = wasSaved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating favorites: $e')));
      }
    }
  }

  Future<void> _startChat() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    if (currentUser.id == widget.item['seller_id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't message yourself!")),
      );
      return;
    }

    setState(() => _isStartingChat = true);

    try {
      final supabase = Supabase.instance.client;
      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', widget.item['id'])
          .eq('buyer_id', currentUser.id);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': widget.item['id'],
                  'buyer_id': currentUser.id,
                  'seller_id': widget.item['seller_id'],
                })
                .select('id')
                .single();
        chatId = newChat['id'];
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: _sellerName,
                  itemTitle: widget.item['title'],
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isStartingChat = false);
    }
  }

  // ==========================================================
  // RENTING LOGIC (With Syncfusion Calendar)
  // ==========================================================
  Future<void> _handleRentRequest() async {
    if (_currentUserId == widget.item['seller_id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't rent your own item!")),
      );
      return;
    }

    setState(() => _isStartingChat = true);

    // 1. Fetch currently booked dates
    List<DateTime> blackoutedDates = [];
    try {
      final data = await Supabase.instance.client
          .from('rentals')
          .select('start_date, end_date')
          .eq('listing_id', widget.item['id'])
          .inFilter('status', ['awaiting_payment', 'active']);

      for (var row in data) {
        DateTime start = DateTime.parse(row['start_date']).toLocal();
        DateTime end = DateTime.parse(row['end_date']).toLocal();

        // Add every day in the range to the blackout list
        for (
          DateTime d = start;
          d.isBefore(end) || d.isAtSameMomentAs(end);
          d = d.add(const Duration(days: 1))
        ) {
          blackoutedDates.add(DateTime(d.year, d.month, d.day));
        }
      }
    } catch (e) {
      debugPrint('Error fetching booked dates: $e');
    }

    if (!mounted) return;
    setState(() => _isStartingChat = false);

    // 2. Show Syncfusion Date Picker Bottom Sheet
    DateTimeRange? pickedDates = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        PickerDateRange? tempSelectedRange;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Rental Dates',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 350,
                  child: SfDateRangePicker(
                    view: DateRangePickerView.month,
                    selectionMode: DateRangePickerSelectionMode.range,
                    minDate: DateTime.now(),
                    maxDate: DateTime.now().add(const Duration(days: 90)),
                    monthViewSettings: DateRangePickerMonthViewSettings(
                      blackoutDates: blackoutedDates,
                    ),
                    monthCellStyle: const DateRangePickerMonthCellStyle(
                      blackoutDateTextStyle: TextStyle(
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    selectionColor: kPremiumRed,
                    startRangeSelectionColor: kPremiumRed,
                    endRangeSelectionColor: kPremiumRed,
                    rangeSelectionColor: kPremiumRed.withOpacity(0.1),
                    todayHighlightColor: kPremiumRed,
                    onSelectionChanged: (
                      DateRangePickerSelectionChangedArgs args,
                    ) {
                      if (args.value is PickerDateRange) {
                        tempSelectedRange = args.value;
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: kPremiumRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      if (tempSelectedRange?.startDate != null &&
                          tempSelectedRange?.endDate != null) {
                        Navigator.pop(
                          context,
                          DateTimeRange(
                            start: tempSelectedRange!.startDate!,
                            end: tempSelectedRange!.endDate!,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please select a start and end date.',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text(
                      'Confirm Dates',
                      style: TextStyle(
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

    if (pickedDates == null) return;

    // 3. Safety Check
    bool isRangeValid = true;
    for (
      DateTime d = pickedDates.start;
      d.isBefore(pickedDates.end) || d.isAtSameMomentAs(pickedDates.end);
      d = d.add(const Duration(days: 1))
    ) {
      final checkDay = DateTime(d.year, d.month, d.day);
      if (blackoutedDates.any((bd) => bd.isAtSameMomentAs(checkDay))) {
        isRangeValid = false;
        break;
      }
    }

    if (!isRangeValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your selection includes unavailable dates. Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 4. Calculate Costs
    final int days = pickedDates.duration.inDays + 1;
    final double pricePerDay =
        (widget.item['rental_price_per_day'] as num).toDouble();
    final double deposit = (widget.item['security_deposit'] as num).toDouble();
    final double totalRent = days * pricePerDay;
    final double totalUpfront = totalRent + deposit;

    // 5. Show Summary
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => _buildRentalSummarySheet(
            pickedDates,
            days,
            pricePerDay,
            totalRent,
            deposit,
            totalUpfront,
          ),
    );
  }

  Widget _buildRentalSummarySheet(
    DateTimeRange dates,
    int days,
    double pricePerDay,
    double totalRent,
    double deposit,
    double totalUpfront,
  ) {
    final DateFormat formatter = DateFormat('MMM d, yyyy');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rental Request Summary',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextPrimary,
              ),
            ),
            const SizedBox(height: 24),
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
                        'Dates',
                        style: TextStyle(color: kTextSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatter.format(dates.start)} - ${formatter.format(dates.end)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kPremiumRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$days Days',
                      style: const TextStyle(
                        color: kPremiumRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildCostRow('AED $pricePerDay x $days days', 'AED $totalRent'),
            const SizedBox(height: 12),
            _buildCostRow('Security Deposit (Refundable)', 'AED $deposit'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Divider(),
            ),
            _buildCostRow('Total Upfront', 'AED $totalUpfront', isTotal: true),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: kPremiumRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _submitRentalRequest(dates, totalRent, deposit);
                },
                child: const Text(
                  'Send Request to Owner',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostRow(String title, String amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isTotal ? kTextPrimary : kTextSecondary,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            fontSize: isTotal ? 18 : 15,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            color: kTextPrimary,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
            fontSize: isTotal ? 20 : 15,
          ),
        ),
      ],
    );
  }

  Future<void> _submitRentalRequest(
    DateTimeRange dates,
    double rentCost,
    double deposit,
  ) async {
    setState(() => _isStartingChat = true);

    try {
      final supabase = Supabase.instance.client;
      final ownerId = widget.item['seller_id'];
      final itemTitle = widget.item['title'];

      await supabase.from('rentals').insert({
        'listing_id': widget.item['id'],
        'owner_id': ownerId,
        'renter_id': _currentUserId,
        'start_date': dates.start.toIso8601String(),
        'end_date': dates.end.toIso8601String(),
        'total_rental_cost': rentCost,
        'security_deposit': deposit,
        'status': 'pending',
      });

      final DateFormat formatter = DateFormat('MMM d, yyyy');
      final String startStr = formatter.format(dates.start);
      final String endStr = formatter.format(dates.end);

      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', widget.item['id'])
          .eq('buyer_id', _currentUserId);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': widget.item['id'],
                  'buyer_id': _currentUserId,
                  'seller_id': ownerId,
                })
                .select('id')
                .single();
        chatId = newChat['id'];
      }

      final String autoMessage =
          '📅 Rental Request!\n'
          'I would like to rent your "$itemTitle" from $startStr to $endStr.\n\n'
          'Please check your Activity > Rentals tab to approve or decline this request.';

      await supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': _currentUserId,
        'content': autoMessage,
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: _sellerName,
                  itemTitle: itemTitle,
                ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rental request sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingChat = false);
    }
  }

  void _showOfferDialog() {
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
                'For: ${widget.item['title']}',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Asking price: AED ${widget.item['price']}',
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
                    Navigator.pop(context);
                    await _sendOffer(offerAmount);
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

  Future<void> _sendOffer(String amount) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    if (currentUser.id == widget.item['seller_id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You can't make an offer on your own item!"),
        ),
      );
      return;
    }

    setState(() => _isStartingChat = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Find or create the chat instance
      final existingChats = await supabase
          .from('chats')
          .select('id')
          .eq('listing_id', widget.item['id'])
          .eq('buyer_id', currentUser.id);

      String chatId;
      if (existingChats.isNotEmpty) {
        chatId = existingChats.first['id'];
      } else {
        final newChat =
            await supabase
                .from('chats')
                .insert({
                  'listing_id': widget.item['id'],
                  'buyer_id': currentUser.id,
                  'seller_id': widget.item['seller_id'],
                })
                .select('id')
                .single();
        chatId = newChat['id'];
      }

      // 2. Insert the offer message
      await supabase.from('messages').insert({
        'chat_id': chatId,
        'sender_id': currentUser.id,
        'content': amount,
        'is_offer': true,
      });

      // 3. Navigate into the ChatScreen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUserName: _sellerName,
                  itemTitle: widget.item['title'],
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isStartingChat = false);
    }
  }

  void _openFullScreenGallery(int startIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                FullScreenGallery(images: _images, initialIndex: startIndex),
      ),
    );
  }

  // --- UI WIDGETS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImageHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item['title'],
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: kTextPrimary,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isSelling && !_isRenting)
                        Text(
                          'AED ${widget.item['price']}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: kPremiumRed,
                            letterSpacing: -0.5,
                          ),
                        ),
                      if (_isRenting && !_isSelling)
                        Text(
                          'AED ${widget.item['rental_price_per_day']} / day',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: kPremiumRed,
                            letterSpacing: -0.5,
                          ),
                        ),
                      if (_isSelling && _isRenting)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'AED ${widget.item['price']}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: kPremiumRed,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'or',
                              style: TextStyle(
                                color: kTextSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AED ${widget.item['rental_price_per_day']} / day',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kPremiumRed,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildModernChip(
                            Icons.check_circle_outline_rounded,
                            widget.item['condition'] ?? 'Used',
                            Colors.blueGrey,
                          ),
                          _buildModernChip(
                            Icons.location_on_outlined,
                            widget.item['meetup_spot'] ?? 'Dubai',
                            Colors.deepOrange,
                          ),
                          if (_isRenting &&
                              widget.item['security_deposit'] != null)
                            _buildModernChip(
                              Icons.shield_outlined,
                              'Dep: AED ${widget.item['security_deposit']}',
                              Colors.teal,
                            ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      _buildSellerRow(),
                      const SizedBox(height: 32),
                      const Text(
                        'Description',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.item['description'] ??
                            'No description provided.',
                        style: const TextStyle(
                          fontSize: 15,
                          color: kTextSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildStickyHeader()),
        ],
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildImageHeader() {
    return SizedBox(
      height: 420,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: _images.length,
            onPageChanged:
                (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openFullScreenGallery(index),
                child: Image.network(
                  _images[index],
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                ),
              ),
            ),
          ),
          if (_images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_images.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: _currentImageIndex == index ? 20 : 6,
                    decoration: BoxDecoration(
                      color:
                          _currentImageIndex == index
                              ? kPremiumRed
                              : Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStickyHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGlassIconBtn(
              Icons.arrow_back_rounded,
              () => Navigator.pop(context),
            ),
            Row(
              children: [
                _buildGlassIconBtn(Icons.ios_share_rounded, () {
                  final String title = widget.item['title'];
                  Share.share('Check out this $title on Avory!');
                }),
                const SizedBox(width: 12),
                _buildGlassIconBtn(
                  _isSaved
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  _toggleSave,
                  color: _isSaved ? kPremiumRed : Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassIconBtn(
    IconData icon,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildModernChip(IconData icon, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accent.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerRow() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => PublicProfileScreen(
                  sellerId: widget.item['seller_id'],
                  sellerName: _sellerName,
                ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 26,
              child: Text(
                _sellerName != 'Loading...'
                    ? _sellerName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: kPremiumRed,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sellerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Colors.amber.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sellerRating != null
                            ? _sellerRating!.toStringAsFixed(1)
                            : 'New',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _sellerReviewCount > 0
                            ? ' ($_sellerReviewCount reviews)'
                            : ' Seller',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // --- NEW: UPDATED BOTTOM ACTION BAR ---
  Widget _buildBottomActionBar() {
    final bool isSold = widget.item['is_sold'] ?? false;
    final bool isBuyer = widget.item['buyer_id'] == _currentUserId;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isSold && isBuyer) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => LeaveReviewScreen(
                            sellerId: widget.item['seller_id'],
                            sellerName: _sellerName,
                            listingId: widget.item['id'],
                            itemTitle: widget.item['title'],
                          ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Leave Review',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else ...[
            // --- NEW: DEDICATED CHAT BUTTON ---
            Container(
              height: 54,
              width: 54,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSold ? Colors.grey.shade300 : kPremiumRed,
                  width: 2,
                ),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: isSold ? Colors.grey : kPremiumRed,
                ),
                onPressed: (_isStartingChat || isSold) ? null : _startChat,
              ),
            ),
            const SizedBox(width: 12),

            // --- DYNAMIC ACTION BUTTONS ---
            if (_isSelling && _isRenting) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      (_isStartingChat || isSold) ? null : _showOfferDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: isSold ? Colors.grey.shade300 : kPremiumRed,
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    foregroundColor: isSold ? Colors.grey : kPremiumRed,
                  ),
                  child: const Text(
                    'Offer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (_isStartingChat || isSold) ? null : _handleRentRequest,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor:
                        isSold ? Colors.grey.shade300 : kPremiumRed,
                    foregroundColor: isSold ? Colors.grey : Colors.white,
                    elevation: isSold ? 0 : 5,
                    shadowColor: kPremiumRed.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Rent',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (_isStartingChat || isSold)
                          ? null
                          : (_isRenting
                              ? _handleRentRequest
                              : _showOfferDialog),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor:
                        isSold ? Colors.grey.shade300 : kPremiumRed,
                    foregroundColor: isSold ? Colors.grey : Colors.white,
                    elevation: isSold ? 0 : 5,
                    shadowColor: kPremiumRed.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child:
                      _isStartingChat
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : Text(
                            _isRenting
                                ? 'Select Dates to Rent'
                                : 'Make an Offer',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class FullScreenGallery extends StatelessWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenGallery({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Image.network(images[index], fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}
