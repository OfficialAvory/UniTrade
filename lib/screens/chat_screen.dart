import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // NEW: Required for kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'public_profile_screen.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF5A5A5A);

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String itemTitle;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.itemTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final String _currentUserId = Supabase.instance.client.auth.currentUser!.id;

  late final Stream<List<Map<String, dynamic>>> _messagesStream;
  late final Stream<List<Map<String, dynamic>>> _chatStream;

  // --- MESSAGE FREEZE CACHE ---
  List<Map<String, dynamic>> _cachedMessages = [];

  String? _askingPrice;
  Key _sliderKey = UniqueKey();
  String? _localPaymentStatus;

  bool _isProcessingAction = false;

  late final RealtimeChannel _typingChannel;
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;

  // --- BLOCK LOGIC STATE ---
  bool _isBlockedByMe = false;
  String? _checkedOtherUserId;

  @override
  void initState() {
    super.initState();

    _messagesStream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', widget.chatId)
        .order('created_at', ascending: false);

    _chatStream = Supabase.instance.client
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('id', widget.chatId);

    _markMessagesAsRead();
    _fetchChatDetails();
    _setupTypingIndicator();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    Supabase.instance.client.removeChannel(_typingChannel);
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchChatDetails() async {
    try {
      final chatData =
          await Supabase.instance.client
              .from('chats')
              .select('listing_id, request_id, buyer_id, seller_id')
              .eq('id', widget.chatId)
              .single();

      final otherUserId =
          chatData['buyer_id'] == _currentUserId
              ? chatData['seller_id']
              : chatData['buyer_id'];

      final blockData = await Supabase.instance.client
          .from('blocks')
          .select('id')
          .eq('blocker_id', _currentUserId)
          .eq('blocked_id', otherUserId);

      String? fetchedPrice;
      if (chatData['listing_id'] != null) {
        final listingData =
            await Supabase.instance.client
                .from('listings')
                .select('price')
                .eq('id', chatData['listing_id'])
                .single();
        fetchedPrice = listingData['price'].toString();
      } else if (chatData['request_id'] != null) {
        final requestData =
            await Supabase.instance.client
                .from('requests')
                .select('budget')
                .eq('id', chatData['request_id'])
                .single();
        fetchedPrice = requestData['budget'].toString();
      }

      if (mounted) {
        setState(() {
          _isBlockedByMe = blockData.isNotEmpty;
          _checkedOtherUserId = otherUserId;
          if (fetchedPrice != null) _askingPrice = fetchedPrice;
        });
      }
    } catch (e) {
      debugPrint('Error fetching chat details: $e');
    }
  }

  Future<void> _checkBlockStatus(String otherId) async {
    if (_checkedOtherUserId == otherId) return;
    _checkedOtherUserId = otherId;

    try {
      final blockData = await Supabase.instance.client
          .from('blocks')
          .select('id')
          .eq('blocker_id', _currentUserId)
          .eq('blocked_id', otherId);

      if (mounted) {
        setState(() {
          _isBlockedByMe = blockData.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('Error checking block status: $e');
    }
  }

  void _setupTypingIndicator() {
    _typingChannel = Supabase.instance.client.channel('chat_${widget.chatId}');

    _typingChannel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (payload['sender_id'] != _currentUserId && !_isBlockedByMe) {
              setState(() => _isOtherUserTyping = true);

              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => _isOtherUserTyping = false);
              });
            }
          },
        )
        .subscribe();
  }

  void _onTextChanged(String text) {
    if (_isBlockedByMe) return;
    _typingChannel.sendBroadcastMessage(
      event: 'typing',
      payload: {'sender_id': _currentUserId},
    );
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image == null) return;
    setState(() => _isProcessingAction = true);

    try {
      // Use readAsBytes instead of File to support Web platform safely
      final imageBytes = await image.readAsBytes();
      final fileExt = image.name.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = '${widget.chatId}/$fileName';

      await Supabase.instance.client.storage
          .from('chat_images')
          .uploadBinary(filePath, imageBytes);

      final imageUrl = Supabase.instance.client.storage
          .from('chat_images')
          .getPublicUrl(filePath);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '📷 Image',
        'image_url': imageUrl,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await Supabase.instance.client.rpc(
        'mark_messages_read',
        params: {'p_chat_id': widget.chatId, 'p_user_id': _currentUserId},
      );
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _sendMessage([String? customText]) async {
    final text = customText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': text,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    }
  }

  void _showMeetupSelector() {
    final List<String> campusSpots = [
      'Campus Library',
      'Student Center',
      'Main Gate',
      'Cafeteria',
      'Dorms Lobby',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Suggest a Meetup Spot',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: kTextPrimary,
                  ),
                ),
              ),
              ...campusSpots.map(
                (spot) => ListTile(
                  leading: const Icon(
                    Icons.location_on_rounded,
                    color: kPremiumRed,
                  ),
                  title: Text(
                    spot,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _sendMessage("📍 Let's meet at the $spot.");
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showTrustAndSafetyOptions(String otherUserId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
              ListTile(
                leading: Icon(
                  _isBlockedByMe
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                  color: Colors.orange,
                ),
                title: Text(
                  _isBlockedByMe ? 'Unblock User' : 'Block User',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleBlockUser(otherUserId);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.flag_rounded, color: kPremiumRed),
                title: const Text(
                  'Report User',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kPremiumRed,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog(otherUserId);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleBlockUser(String otherUserId) async {
    setState(() => _isProcessingAction = true);
    try {
      if (_isBlockedByMe) {
        await Supabase.instance.client
            .from('blocks')
            .delete()
            .eq('blocker_id', _currentUserId)
            .eq('blocked_id', otherUserId);

        if (mounted) {
          setState(() => _isBlockedByMe = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User has been unblocked.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await Supabase.instance.client.from('blocks').insert({
          'blocker_id': _currentUserId,
          'blocked_id': otherUserId,
        });

        if (mounted) {
          setState(() {
            _isBlockedByMe = true;
            _isOtherUserTyping = false;
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User has been blocked. Chat removed.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: kPremiumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  void _showReportDialog(String otherUserId) {
    final List<String> reasons = [
      'Spam or Scam',
      'Inappropriate Behavior',
      'No Show',
      'Fake Listing',
      'Other',
    ];
    String selectedReason = reasons.first;
    final TextEditingController otherReasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Report User',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Why are you reporting this user?',
                    style: TextStyle(color: kTextSecondary),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: kBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items:
                        reasons
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedReason = val);
                      }
                    },
                  ),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: otherReasonController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Please specify the reason...',
                        filled: true,
                        fillColor: kBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      maxLines: 3,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPremiumRed,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);

                    final finalReason =
                        selectedReason == 'Other'
                            ? 'Other: ${otherReasonController.text.trim()}'
                            : selectedReason;

                    try {
                      await Supabase.instance.client.from('reports').insert({
                        'reporter_id': _currentUserId,
                        'reported_id': otherUserId,
                        'reason': finalReason,
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Report submitted. Our team will review it shortly.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to send report: $e'),
                            backgroundColor: kPremiumRed,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Submit Report',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImageFullScreen(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                elevation: 0,
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Future<void> _updateOfferStatus(String messageId, String status) async {
    try {
      await Supabase.instance.client
          .from('messages')
          .update({'offer_status': status})
          .eq('id', messageId);
      final statusText =
          status == 'accepted' ? 'accepted the offer!' : 'declined the offer.';
      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': 'I have $statusText',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showInChatOfferDialog() {
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
                      fontWeight: FontWeight.bold,
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
                'For: ${widget.itemTitle}',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_askingPrice != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Asking price / Budget: AED $_askingPrice',
                  style: const TextStyle(color: kTextSecondary, fontSize: 14),
                ),
              ],
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

                    try {
                      await Supabase.instance.client.from('messages').insert({
                        'chat_id': widget.chatId,
                        'sender_id': _currentUserId,
                        'content': offerAmount,
                        'is_offer': true,
                      });
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
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

  // =====================================================================
  // STRIPE DIRECT API CALLS (TEST MODE ONLY)
  // =====================================================================

  Future<void> _payWithStripe(String amountString) async {
    // 1. Prevent Web Crash
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💳 Please use the mobile app to process payments!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
      );

      final int amountInFils = (double.parse(amountString) * 100).toInt();

      // 2. Direct call to Stripe API
      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET_KEY']}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'amount': amountInFils.toString(), 'currency': 'aed'},
      );

      final paymentIntent = jsonDecode(response.body);

      if (paymentIntent['error'] != null) {
        throw Exception(paymentIntent['error']['message']);
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
          merchantDisplayName: 'Avory Campus Market',
          style: ThemeMode.system,
        ),
      );

      if (mounted) Navigator.pop(context);

      await Stripe.instance.presentPaymentSheet();

      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'paid'})
          .eq('id', widget.chatId);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '💳 Payment of AED $amountString secured in Escrow.',
      });

      if (mounted) setState(() => _localPaymentStatus = 'paid');
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Failed: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _updateRentalStatus(String rentalId, String newStatus) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);
    try {
      await Supabase.instance.client
          .from('rentals')
          .update({'status': newStatus})
          .eq('id', rentalId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Updated!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: kPremiumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _payForRental(Map<String, dynamic> rental) async {
    // 1. Prevent Web Crash
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('💳 Please use the mobile app to process payments!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
      );

      final double rentCost = (rental['total_rental_cost'] as num).toDouble();
      final double deposit = (rental['security_deposit'] as num).toDouble();
      final int amountInFils = ((rentCost + deposit) * 100).toInt();

      // 2. Direct call to Stripe API
      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/payment_intents'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET_KEY']}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'amount': amountInFils.toString(), 'currency': 'aed'},
      );

      final paymentIntent = jsonDecode(response.body);

      if (paymentIntent['error'] != null) {
        throw Exception(paymentIntent['error']['message']);
      }

      final String paymentIntentId = paymentIntent['id'];

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
          merchantDisplayName: 'Avory Campus Market',
          style: ThemeMode.system,
        ),
      );

      if (mounted) Navigator.pop(context);

      await Stripe.instance.presentPaymentSheet();

      await Supabase.instance.client
          .from('rentals')
          .update({
            'status': 'active',
            'payment_status': 'paid',
            'stripe_payment_intent_id': paymentIntentId,
          })
          .eq('id', rental['id']);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '💳 Rental Payment successful!',
      });
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Failed: $e'),
            backgroundColor: kPremiumRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _cancelTrade() async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
      );
      final verify =
          await Supabase.instance.client
              .from('chats')
              .select('payment_status')
              .eq('id', widget.chatId)
              .single();
      if (verify['payment_status'] != 'paid') {
        throw Exception('Trade is no longer in escrow.');
      }
      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'cancelled'})
          .eq('id', widget.chatId);
      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '⚠️ Trade Cancelled. Funds refunded.',
      });
      if (mounted) setState(() => _localPaymentStatus = 'cancelled');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context);
        setState(() => _isProcessingAction = false);
      }
    }
  }

  Future<void> _releaseFunds(
    String? listingId,
    String? requestId,
    String sellerId,
    String? finalPrice,
  ) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
      );
      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'completed'})
          .eq('id', widget.chatId);
      if (listingId != null) {
        final updateData = <String, dynamic>{
          'is_sold': true,
          'buyer_id': _currentUserId,
        };
        if (finalPrice != null && finalPrice != '0') {
          updateData['price'] =
              double.tryParse(finalPrice) ?? updateData['price'];
        }
        await Supabase.instance.client
            .from('listings')
            .update(updateData)
            .eq('id', listingId);
      } else if (requestId != null) {
        await Supabase.instance.client
            .from('requests')
            .update({'is_fulfilled': true})
            .eq('id', requestId);
      }
      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '✅ Trade Completed! Funds released.',
      });
      if (mounted) {
        setState(() {
          _localPaymentStatus = 'completed';
          _sliderKey = UniqueKey();
        });
        Navigator.pop(context);
        _showReviewModal(sellerId, listingId, requestId);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _completeRentalAndRefund(Map<String, dynamic> rental) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => const PopScope(
              canPop: false,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
      );

      final int refundAmount =
          ((rental['security_deposit'] as num).toDouble() * 100).toInt();

      // 1. Direct call to Stripe Refund API
      final response = await http.post(
        Uri.parse('https://api.stripe.com/v1/refunds'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['STRIPE_SECRET_KEY']}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'payment_intent': rental['stripe_payment_intent_id'],
          'amount': refundAmount.toString(),
        },
      );

      final refundData = jsonDecode(response.body);

      if (refundData['error'] != null) {
        throw Exception(refundData['error']['message']);
      }

      await Supabase.instance.client
          .from('rentals')
          .update({'status': 'completed'})
          .eq('id', rental['id']);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content': '✅ Item returned safely! Deposit released.',
      });

      if (mounted) {
        Navigator.pop(context);
        _showReviewModal(rental['renter_id'], rental['listing_id'], null);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: kPremiumRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  void _showReviewModal(
    String revieweeId,
    String? listingId,
    String? requestId,
  ) {
    int rating = 5;
    final commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Trade Complete!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        icon: Icon(
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 40,
                        ),
                        onPressed:
                            () => setModalState(() => rating = index + 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      hintText: 'Leave a comment...',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await Supabase.instance.client.from('reviews').insert({
                        'listing_id': listingId,
                        'buyer_id': _currentUserId,
                        'seller_id': revieweeId,
                        'rating': rating,
                        'comment': commentController.text,
                      });
                    },
                    child: const Text('Publish Review'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatStream,
        builder: (context, chatSnapshot) {
          if (!chatSnapshot.hasData || chatSnapshot.data!.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: kPremiumRed),
            );
          }

          final chatRow = chatSnapshot.data!.first;

          final paymentStatus =
              _localPaymentStatus ?? chatRow['payment_status'] ?? 'pending';
          final listingId = chatRow['listing_id'];
          final requestId = chatRow['request_id'];

          final bool isCurrentUserBuyer = _currentUserId == chatRow['buyer_id'];
          final String trueSellerId = chatRow['seller_id'];
          final String otherUserId =
              isCurrentUserBuyer ? chatRow['seller_id'] : chatRow['buyer_id'];

          final otherUserRole = isCurrentUserBuyer ? 'Seller' : 'Buyer';
          final roleColor =
              isCurrentUserBuyer ? Colors.deepPurple : Colors.teal;

          final bool isChatLocked =
              paymentStatus == 'completed' || paymentStatus == 'cancelled';

          _checkBlockStatus(otherUserId);

          return Column(
            children: [
              AppBar(
                backgroundColor: kSurface,
                elevation: 0,
                scrolledUnderElevation: 2,
                shadowColor: Colors.black.withOpacity(0.1),
                iconTheme: const IconThemeData(color: kTextPrimary),
                titleSpacing: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showTrustAndSafetyOptions(otherUserId),
                  ),
                ],
                title: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => PublicProfileScreen(
                              sellerId: otherUserId,
                              sellerName: widget.otherUserName,
                            ),
                      ),
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.otherUserName,
                            style: const TextStyle(
                              color: kTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: roleColor.withOpacity(0.5),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              otherUserRole.toUpperCase(),
                              style: TextStyle(
                                color: roleColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.shopping_bag_outlined,
                            size: 12,
                            color: kTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _askingPrice != null
                                ? '${widget.itemTitle} • AED $_askingPrice'
                                : widget.itemTitle,
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, msgSnapshot) {
                    if (msgSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: kPremiumRed),
                      );
                    }

                    final incomingMessages = msgSnapshot.data ?? [];

                    if (!_isBlockedByMe) {
                      _cachedMessages = incomingMessages;
                    }
                    final messagesToRender = _cachedMessages;

                    final unreadMessages =
                        messagesToRender
                            .where(
                              (msg) =>
                                  msg['is_read'] == false &&
                                  msg['sender_id'] != _currentUserId,
                            )
                            .toList();

                    if (unreadMessages.isNotEmpty && !_isBlockedByMe) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _markMessagesAsRead(),
                      );
                    }

                    bool hasAcceptedOffer = false;
                    String acceptedAmount = '0';

                    try {
                      final acceptedMsg = messagesToRender.firstWhere(
                        (msg) =>
                            msg['is_offer'] == true &&
                            msg['offer_status'] == 'accepted',
                      );
                      hasAcceptedOffer = true;
                      acceptedAmount = acceptedMsg['content'];
                    } catch (e) {
                      // Keep false
                    }

                    return Column(
                      children: [
                        if (listingId != null)
                          StreamBuilder<List<Map<String, dynamic>>>(
                            stream: Supabase.instance.client
                                .from('rentals')
                                .stream(primaryKey: ['id'])
                                .eq('listing_id', listingId)
                                .map((data) {
                                  final filtered =
                                      data
                                          .where(
                                            (r) =>
                                                r['renter_id'] ==
                                                    chatRow['buyer_id'] &&
                                                r['owner_id'] ==
                                                    chatRow['seller_id'],
                                          )
                                          .toList();

                                  filtered.sort(
                                    (a, b) => DateTime.parse(
                                      b['created_at'],
                                    ).compareTo(
                                      DateTime.parse(a['created_at']),
                                    ),
                                  );

                                  return filtered;
                                }),
                            builder: (context, rentalSnapshot) {
                              final rentals = rentalSnapshot.data ?? [];

                              Map<String, dynamic>? activeRental;
                              Map<String, dynamic>? pastRental;

                              if (rentals.isNotEmpty) {
                                try {
                                  activeRental = rentals.firstWhere(
                                    (r) => [
                                      'pending',
                                      'awaiting_payment',
                                      'active',
                                    ].contains(r['status']),
                                  );
                                } catch (e) {
                                  pastRental = rentals.first;
                                }
                              }

                              if (activeRental != null) {
                                return _buildRentalContextBanner(
                                  activeRental,
                                  !isCurrentUserBuyer,
                                );
                              } else if (hasAcceptedOffer) {
                                return _buildEscrowBanner(
                                  paymentStatus,
                                  isCurrentUserBuyer,
                                  trueSellerId,
                                  listingId,
                                  requestId,
                                  acceptedAmount,
                                );
                              } else if (pastRental != null) {
                                return _buildRentalContextBanner(
                                  pastRental,
                                  !isCurrentUserBuyer,
                                );
                              }

                              return const SizedBox.shrink();
                            },
                          )
                        else if (hasAcceptedOffer)
                          _buildEscrowBanner(
                            paymentStatus,
                            isCurrentUserBuyer,
                            trueSellerId,
                            listingId,
                            requestId,
                            acceptedAmount,
                          ),

                        Expanded(
                          child:
                              messagesToRender.isEmpty
                                  ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.05,
                                                ),
                                                blurRadius: 20,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.waving_hand_rounded,
                                            size: 48,
                                            color: Colors.amber.shade300,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Start the conversation!',
                                          style: TextStyle(
                                            color: kTextSecondary,
                                          ),
                                        ),
                                        if (!isChatLocked &&
                                            !_isBlockedByMe) ...[
                                          const SizedBox(height: 32),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ActionChip(
                                                label: const Text(
                                                  'Is this still available?',
                                                ),
                                                onPressed:
                                                    () => _sendMessage(
                                                      'Is this still available?',
                                                    ),
                                                backgroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  side: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                              ActionChip(
                                                label: const Text(
                                                  'What is the condition?',
                                                ),
                                                onPressed:
                                                    () => _sendMessage(
                                                      'What is the condition?',
                                                    ),
                                                backgroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  side: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                              ActionChip(
                                                label: const Text(
                                                  'Are you negotiable?',
                                                ),
                                                onPressed:
                                                    () => _sendMessage(
                                                      'Are you negotiable?',
                                                    ),
                                                backgroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  side: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    reverse: true,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: messagesToRender.length,
                                    itemBuilder: (context, index) {
                                      final message = messagesToRender[index];
                                      final isMe =
                                          message['sender_id'] ==
                                          _currentUserId;
                                      final isOffer =
                                          message['is_offer'] ?? false;

                                      if (isOffer) {
                                        return _buildOfferBubble(message, isMe);
                                      }
                                      return _buildMessageBubble(message, isMe);
                                    },
                                  ),
                        ),

                        if (_isOtherUserTyping && !_isBlockedByMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 24, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${widget.otherUserName} is typing...',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),

                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            child:
                                isChatLocked
                                    ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      color: kBackground,
                                      child: const Text(
                                        'This chat is now closed.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: kTextSecondary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                    : _isBlockedByMe
                                    ? Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      color: kBackground,
                                      child: Column(
                                        children: [
                                          const Text(
                                            'You blocked this user.',
                                            style: TextStyle(
                                              color: kTextSecondary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          GestureDetector(
                                            onTap:
                                                () => _toggleBlockUser(
                                                  otherUserId,
                                                ),
                                            child: const Text(
                                              'Tap to unblock',
                                              style: TextStyle(
                                                color: kPremiumRed,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                    : Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          GestureDetector(
                                            onTap: _showMeetupSelector,
                                            child: Container(
                                              width: 40,
                                              height: 50,
                                              margin: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: kBackground,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: const Icon(
                                                Icons.location_on_outlined,
                                                color: kTextSecondary,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _sendImage,
                                            child: Container(
                                              width: 40,
                                              height: 50,
                                              margin: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: kBackground,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child:
                                                  _isProcessingAction
                                                      ? const Padding(
                                                        padding: EdgeInsets.all(
                                                          14.0,
                                                        ),
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  kPremiumRed,
                                                            ),
                                                      )
                                                      : const Icon(
                                                        Icons
                                                            .add_photo_alternate_outlined,
                                                        color: kTextSecondary,
                                                        size: 22,
                                                      ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Container(
                                              constraints: const BoxConstraints(
                                                minHeight: 50,
                                                maxHeight: 120,
                                              ),
                                              decoration: BoxDecoration(
                                                color: kBackground,
                                                borderRadius:
                                                    BorderRadius.circular(25),
                                              ),
                                              child: TextField(
                                                controller: _messageController,
                                                onChanged: _onTextChanged,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .sentences,
                                                cursorColor: kPremiumRed,
                                                minLines: 1,
                                                maxLines: 5,
                                                textAlignVertical:
                                                    TextAlignVertical.center,
                                                style: const TextStyle(
                                                  color: kTextPrimary,
                                                  fontSize: 16,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: 'Message',
                                                  hintStyle: TextStyle(
                                                    color: Colors.grey.shade500,
                                                    fontSize: 16,
                                                  ),
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 20,
                                                        vertical: 14,
                                                      ),
                                                ),
                                                onSubmitted:
                                                    (_) => _sendMessage(),
                                              ),
                                            ),
                                          ),
                                          if (isCurrentUserBuyer &&
                                              !hasAcceptedOffer &&
                                              paymentStatus == 'pending') ...[
                                            const SizedBox(width: 12),
                                            GestureDetector(
                                              onTap: _showInChatOfferDialog,
                                              child: Container(
                                                width: 50,
                                                height: 50,
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade100,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color:
                                                        Colors.amber.shade300,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.local_offer_rounded,
                                                  color: Colors.amber.shade800,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 12),
                                          GestureDetector(
                                            onTap: _sendMessage,
                                            child: Container(
                                              width: 50,
                                              height: 50,
                                              decoration: const BoxDecoration(
                                                color: kPremiumRed,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.send_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRentalContextBanner(Map<String, dynamic> rental, bool isOwner) {
    final String status = rental['status'];
    final DateTime endDate = DateTime.parse(rental['end_date']).toLocal();
    final DateTime now = DateTime.now();
    final double rentCost = (rental['total_rental_cost'] as num).toDouble();
    final double deposit = (rental['security_deposit'] as num).toDouble();
    final double totalAmount = rentCost + deposit;

    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final int daysLeft = endDay.difference(today).inDays;

    Color bannerColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;
    Widget? actionWidget;

    if (status == 'pending') {
      bannerColor = Colors.amber.shade50;
      iconColor = Colors.amber.shade800;
      icon = Icons.hourglass_top_rounded;
      title = 'Rental Requested';
      subtitle =
          isOwner
              ? 'They want to rent this item.'
              : 'Waiting for the owner to approve.';

      if (isOwner) {
        actionWidget = Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _updateRentalStatus(rental['id'], 'cancelled'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTextSecondary,
                  side: BorderSide(color: Colors.black.withOpacity(0.1)),
                ),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    () => _updateRentalStatus(rental['id'], 'awaiting_payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPremiumRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Approve'),
              ),
            ),
          ],
        );
      } else {
        actionWidget = SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => _updateRentalStatus(rental['id'], 'cancelled'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Request'),
          ),
        );
      }
    } else if (status == 'awaiting_payment') {
      bannerColor = Colors.orange.shade50;
      iconColor = Colors.orange.shade800;
      icon = Icons.payment_rounded;
      title = 'Request Approved';
      subtitle =
          isOwner
              ? 'Waiting for them to pay AED $totalAmount.'
              : 'Total due: AED $totalAmount (inc. deposit).';

      if (!isOwner) {
        actionWidget = SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _payForRental(rental),
            icon: const Icon(Icons.credit_card_rounded),
            label: const Text('Pay Now to Start Rental'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        );
      }
    } else if (status == 'active') {
      if (daysLeft < 0) {
        bannerColor = Colors.red.shade50;
        iconColor = Colors.red;
        icon = Icons.warning_rounded;
        title = '🚨 Rental Overdue';
        subtitle =
            isOwner
                ? 'Coordinate return now to release deposit.'
                : 'Please return the item immediately to avoid penalties.';
      } else {
        bannerColor = Colors.green.shade50;
        iconColor = Colors.green.shade800;
        icon = Icons.check_circle_rounded;
        title = 'Active Rental';
        subtitle =
            daysLeft == 0
                ? 'Due Today (${DateFormat('MMM d').format(endDate)})'
                : '⏳ $daysLeft Days Left (Due ${DateFormat('MMM d').format(endDate)})';
      }

      if (isOwner) {
        actionWidget = SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _completeRentalAndRefund(rental),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Confirm Return & Refund Deposit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      }
    } else if (status == 'completed') {
      bannerColor = Colors.deepPurple.shade50;
      iconColor = Colors.deepPurple;
      icon = Icons.verified_rounded;
      title = 'Rental Completed';
      subtitle = 'The item was returned and deposit refunded.';
    } else if (status == 'cancelled') {
      bannerColor = Colors.red.shade50;
      iconColor = Colors.red.shade800;
      icon = Icons.cancel_rounded;
      title = 'Rental Cancelled';
      subtitle = 'This request was cancelled.';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: bannerColor,
        border: Border(bottom: BorderSide(color: iconColor.withOpacity(0.2))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: iconColor.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionWidget != null) ...[
            const SizedBox(height: 12),
            actionWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildEscrowBanner(
    String status,
    bool isBuyer,
    String trueSellerId,
    String? listingId,
    String? requestId,
    String amount,
  ) {
    if (status == 'cancelled') {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.red.shade50,
        child: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Colors.red),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trade Cancelled. Funds have been refunded.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'pending') {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.amber.shade50,
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: Colors.amber.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isBuyer
                        ? 'Offer Accepted! Pay AED $amount now to secure the item in Escrow.'
                        : 'Offer Accepted! Waiting for the buyer to secure funds.',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (isBuyer) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _payWithStripe(amount),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.credit_card_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Secure Checkout',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (status == 'paid') {
      return Container(
        padding: const EdgeInsets.all(20),
        color: Colors.green.shade50,
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isBuyer
                        ? 'Funds Secured. Inspect the item, then slide to release to the seller.'
                        : 'Funds Secured in Escrow! 🔒 Safe to hand over the item.',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (isBuyer) ...[
              const SizedBox(height: 20),
              SwipeToReleaseButton(
                key: _sliderKey,
                onConfirmed:
                    () => _releaseFunds(
                      listingId,
                      requestId,
                      trueSellerId,
                      amount,
                    ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _cancelTrade,
                  child: const Text(
                    'Cancel Trade & Refund',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (status == 'completed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Colors.deepPurple.shade50,
        child: const Row(
          children: [
            Icon(Icons.celebration_rounded, color: Colors.deepPurple),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trade Completed! The funds have been released.',
                style: TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final DateTime createdAt = DateTime.parse(message['created_at']).toLocal();
    final String timeString = DateFormat('h:mm a').format(createdAt);
    final bool isRead = message['is_read'] ?? false;
    final String rawContent = message['content'].toString();
    final String? imageUrl = message['image_url'];

    if (rawContent.startsWith('📅 Rental Request!\n')) {
      return _buildRentalRequestBubble(
        message,
        isMe,
        timeString,
        isRead,
        rawContent,
      );
    }

    final bool isSystemMessage =
        rawContent.contains('💳') ||
        rawContent.contains('✅') ||
        rawContent.contains('⚠️');

    if (isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              rawContent,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 4),
        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: isMe ? kPremiumRed : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: isMe ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => _showImageFullScreen(imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Container(
                            height: 150,
                            width: 200,
                            color:
                                isMe
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.grey.shade100,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: kPremiumRed,
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            if (imageUrl == null || rawContent != '📷 Image')
              Text(
                rawContent,
                style: TextStyle(
                  color: isMe ? Colors.white : kTextPrimary,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeString,
                  style: TextStyle(
                    color:
                        isMe
                            ? Colors.white.withOpacity(0.8)
                            : Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all_rounded,
                    size: 20,
                    color: isRead ? Colors.greenAccent : Colors.white,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentalRequestBubble(
    Map<String, dynamic> message,
    bool isMe,
    String timeString,
    bool isRead,
    String rawContent,
  ) {
    final String cleanContent =
        rawContent.replaceFirst('📅 Rental Request!\n', '').trim();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, top: 4),
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 10,
        ),
        decoration: BoxDecoration(
          color: isMe ? kPremiumRed : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: isMe ? null : Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  color: isMe ? Colors.white : kPremiumRed,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Rental Request',
                  style: TextStyle(
                    color: isMe ? Colors.white : kPremiumRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cleanContent,
              style: TextStyle(
                color: isMe ? Colors.white : kTextPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeString,
                    style: TextStyle(
                      color:
                          isMe
                              ? Colors.white.withOpacity(0.8)
                              : Colors.grey.shade500,
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 20,
                      color: isRead ? Colors.greenAccent : Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferBubble(Map<String, dynamic> message, bool isMe) {
    final String offerAmount = message['content'];
    final String status = message['offer_status'] ?? 'pending';

    Color statusColor = Colors.orange;
    String statusText = 'Pending Response';
    IconData statusIcon = Icons.access_time_filled_rounded;

    if (status == 'accepted') {
      statusColor = Colors.green;
      statusText = 'Offer Accepted';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'declined') {
      statusColor = Colors.red;
      statusText = 'Offer Declined';
      statusIcon = Icons.cancel_rounded;
    }

    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        width: MediaQuery.of(context).size.width * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    isMe
                        ? 'You sent an offer'
                        : '${widget.otherUserName} sent an offer',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Text(
                    'OFFER PRICE',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AED $offerAmount',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (status == 'pending') ...[
              if (isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Waiting for seller to respond...',
                      style: TextStyle(color: kTextSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 20,
                    left: 20,
                    right: 20,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              () =>
                                  _updateOfferStatus(message['id'], 'declined'),
                          child: const Text(
                            'Decline',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              () =>
                                  _updateOfferStatus(message['id'], 'accepted'),
                          child: const Text(
                            'Accept',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class SwipeToReleaseButton extends StatefulWidget {
  final VoidCallback onConfirmed;
  const SwipeToReleaseButton({super.key, required this.onConfirmed});

  @override
  State<SwipeToReleaseButton> createState() => _SwipeToReleaseButtonState();
}

class _SwipeToReleaseButtonState extends State<SwipeToReleaseButton> {
  double _dragPosition = 0.0;
  bool _isConfirmed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = constraints.maxWidth;
        const double buttonWidth = 60.0;
        final double maxDrag = maxWidth - buttonWidth - 8;

        return Container(
          height: 64,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Stack(
            children: [
              const Center(
                child: Text(
                  'Slide to Release Funds ➡️',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Positioned(
                left: _dragPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_isConfirmed) return;
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0) _dragPosition = 0;
                      if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isConfirmed) return;

                    if (_dragPosition > maxDrag * 0.8) {
                      setState(() {
                        _dragPosition = maxDrag;
                        _isConfirmed = true;
                      });
                      widget.onConfirmed();
                    } else {
                      setState(() => _dragPosition = 0);
                    }
                  },
                  child: AnimatedContainer(
                    duration:
                        _isConfirmed
                            ? const Duration(milliseconds: 100)
                            : const Duration(milliseconds: 0),
                    width: buttonWidth,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
