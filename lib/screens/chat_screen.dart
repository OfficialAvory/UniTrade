import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  String? _askingPrice;
  Key _sliderKey = UniqueKey();
  String? _localPaymentStatus;

  bool _isProcessingAction = false;

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
    _fetchAskingPrice();
  }

  Future<void> _fetchAskingPrice() async {
    try {
      final chatData =
          await Supabase.instance.client
              .from('chats')
              .select('listing_id, request_id')
              .eq('id', widget.chatId)
              .single();

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

      if (mounted && fetchedPrice != null) {
        setState(() {
          _askingPrice = fetchedPrice;
        });
      }
    } catch (e) {
      debugPrint('Error fetching asking price: $e');
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
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
        ).showSnackBar(SnackBar(content: Text('Error updating offer: $e')));
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
                'For: ${widget.itemTitle}',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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

  Future<void> _payWithStripe(String amountString) async {
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

      if (mounted) Navigator.pop(context); // Close spinner

      await Stripe.instance.presentPaymentSheet();

      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'paid'})
          .eq('id', widget.chatId);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content':
            '💳 Payment of AED $amountString secured in Escrow. Funds are locked and safe.',
      });

      if (mounted) {
        setState(() {
          _localPaymentStatus = 'paid';
        });
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Canceled/Failed: $e'),
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

    try {
      final verify =
          await Supabase.instance.client
              .from('chats')
              .select('payment_status')
              .eq('id', widget.chatId)
              .single();

      if (verify['payment_status'] != 'paid') {
        throw Exception('Action failed: Trade is no longer in escrow.');
      }

      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'cancelled'})
          .eq('id', widget.chatId);

      await Supabase.instance.client.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': _currentUserId,
        'content':
            '⚠️ Trade Cancelled. The funds have been refunded to the buyer.',
      });

      if (mounted) {
        setState(() {
          _localPaymentStatus = 'cancelled';
        });
      }
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
  ) async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

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

    try {
      final verify =
          await Supabase.instance.client
              .from('chats')
              .select('payment_status')
              .eq('id', widget.chatId)
              .single();

      if (verify['payment_status'] != 'paid') {
        throw Exception('Action failed: Trade is no longer in escrow.');
      }

      await Supabase.instance.client
          .from('chats')
          .update({'payment_status': 'completed'})
          .eq('id', widget.chatId);

      if (listingId != null) {
        await Supabase.instance.client
            .from('listings')
            .update({'is_sold': true, 'buyer_id': _currentUserId})
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
        'content': '✅ Trade Completed! Funds have been released to the seller.',
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
      if (mounted) {
        setState(() => _isProcessingAction = false);
      }
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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    color: Colors.orangeAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Trade Complete!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'How was your experience with the seller?',
                    style: TextStyle(
                      color: kTextSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 40,
                        ),
                        onPressed: () {
                          setModalState(() => rating = index + 1);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Leave a quick comment...',
                      filled: true,
                      fillColor: kBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await Supabase.instance.client
                              .from('reviews')
                              .insert({
                                'listing_id': listingId,
                                'buyer_id': _currentUserId,
                                'seller_id': revieweeId,
                                'rating': rating,
                                'comment': commentController.text,
                              });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Review published!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error saving review: $e');
                        }
                      },
                      child: const Text(
                        'Publish Review',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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

          final bool isCurrentUserBuyer;
          final String trueSellerId;

          if (requestId != null) {
            isCurrentUserBuyer = _currentUserId != chatRow['buyer_id'];
            trueSellerId = chatRow['buyer_id'];
          } else {
            isCurrentUserBuyer = _currentUserId == chatRow['buyer_id'];
            trueSellerId = chatRow['seller_id'];
          }

          final otherUserRole = isCurrentUserBuyer ? 'Seller' : 'Buyer';
          final roleColor =
              isCurrentUserBuyer ? Colors.deepPurple : Colors.teal;

          return Column(
            children: [
              AppBar(
                backgroundColor: kSurface,
                elevation: 0,
                scrolledUnderElevation: 2,
                shadowColor: Colors.black.withOpacity(0.1),
                iconTheme: const IconThemeData(color: kTextPrimary),
                titleSpacing: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.otherUserName,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w800,
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
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
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

                    final messages = msgSnapshot.data ?? [];
                    final unreadMessages =
                        messages
                            .where(
                              (msg) =>
                                  msg['is_read'] == false &&
                                  msg['sender_id'] != _currentUserId,
                            )
                            .toList();

                    if (unreadMessages.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _markMessagesAsRead(),
                      );
                    }

                    bool hasAcceptedOffer = false;
                    String acceptedAmount = '0';

                    try {
                      final acceptedMsg = messages.firstWhere(
                        (msg) =>
                            msg['is_offer'] == true &&
                            msg['offer_status'] == 'accepted',
                      );
                      hasAcceptedOffer = true;
                      acceptedAmount = acceptedMsg['content'];
                    } catch (e) {
                      // No accepted offer found, keep false
                    }

                    return Column(
                      children: [
                        // ============================================
                        // SMART RENTAL BANNER LOGIC
                        // ============================================
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

                        // ============================================
                        // MESSAGE LIST
                        // ============================================
                        Expanded(
                          child:
                              messages.isEmpty
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
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    reverse: true,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      final message = messages[index];
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

                        // ============================================
                        // INPUT AREA
                        // ============================================
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 50,
                                        maxHeight: 120,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kBackground,
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: TextField(
                                        controller: _messageController,
                                        textCapitalization:
                                            TextCapitalization.sentences,
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
                                        onSubmitted: (_) => _sendMessage(),
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
                                            color: Colors.amber.shade300,
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

  // =====================================================================
  // RENTAL CONTEXT BANNER
  // =====================================================================
  Widget _buildRentalContextBanner(Map<String, dynamic> rental, bool isOwner) {
    final String status = rental['status'];
    final DateTime endDate = DateTime.parse(rental['end_date']).toLocal();
    final DateTime now = DateTime.now();

    final endDay = DateTime(endDate.year, endDate.month, endDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final int daysLeft = endDay.difference(today).inDays;

    Color bannerColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    if (status == 'pending') {
      bannerColor = Colors.amber.shade50;
      iconColor = Colors.amber.shade800;
      icon = Icons.hourglass_top_rounded;
      title = 'Rental Requested';
      subtitle =
          isOwner
              ? 'Tap your Activity tab to approve this.'
              : 'Waiting for the owner to approve.';
    } else if (status == 'awaiting_payment') {
      bannerColor = Colors.orange.shade50;
      iconColor = Colors.orange.shade800;
      icon = Icons.payment_rounded;
      title = 'Request Approved';
      subtitle =
          isOwner
              ? 'Waiting for the renter to pay the deposit.'
              : 'Tap your Activity tab to pay and start the rental!';
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
    } else if (status == 'completed') {
      bannerColor = Colors.deepPurple.shade50;
      iconColor = Colors.deepPurple;
      icon = Icons.verified_rounded;
      title = 'Rental Completed';
      subtitle = 'The item was returned and deposit refunded.';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bannerColor,
        border: Border(bottom: BorderSide(color: iconColor.withOpacity(0.2))),
      ),
      child: Row(
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
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: iconColor.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // EXISTING ESCROW BANNER
  // =====================================================================
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
                    () => _releaseFunds(listingId, requestId, trueSellerId),
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

  // =====================================================================
  // MESSAGE BUBBLES
  // =====================================================================

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final DateTime createdAt = DateTime.parse(message['created_at']).toLocal();
    final String timeString = DateFormat('h:mm a').format(createdAt);
    final bool isRead = message['is_read'] ?? false;
    final String rawContent = message['content'].toString();

    // 1. Check if this is the Automated Rental Request Message
    if (rawContent.startsWith('📅 Rental Request!')) {
      return _buildRentalRequestBubble(
        message,
        isMe,
        timeString,
        isRead,
        rawContent,
      );
    }

    // 2. Check if this is a standard System Message (Receipts, Cancels, etc.)
    // Note: I removed the 📅 emoji from here so it doesn't trigger the grey pill!
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    // 3. Normal Text Message
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
                    fontWeight: FontWeight.w500,
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

  // ✅ NEW: BEAUTIFUL RENTAL REQUEST BUBBLE
  Widget _buildRentalRequestBubble(
    Map<String, dynamic> message,
    bool isMe,
    String timeString,
    bool isRead,
    String rawContent,
  ) {
    // Strip the ugly raw header so we can render it beautifully
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
          crossAxisAlignment:
              CrossAxisAlignment
                  .start, // Left aligned text makes paragraphs much easier to read
          children: [
            // Beautiful Bold Header
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
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Clean Body Text
            Text(
              cleanContent,
              style: TextStyle(
                color: isMe ? Colors.white : kTextPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),

            // Standard Timestamp Row aligned to the right
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
                      fontWeight: FontWeight.w500,
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
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AED $offerAmount',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: kTextPrimary,
                      letterSpacing: -1,
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
                      style: TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
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

// ============================================================================
// Custom Animated "Swipe to Release" Widget
// ============================================================================
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
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.5,
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
                      setState(() {
                        _dragPosition = 0;
                      });
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
