import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- THEME CONSTANTS ---
const Color kPremiumRed = Color(0xFFD32F2F);
const Color kBackground = Color(0xFFF5F5F7);
const Color kSurface = Colors.white;
const Color kTextPrimary = Color(0xFF212121);
const Color kTextSecondary = Color(0xFF757575);

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();

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
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_titleController.text.trim().isEmpty ||
        _budgetController.text.trim().isEmpty ||
        _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in the title, budget, and category.'),
          backgroundColor: kPremiumRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;

      await Supabase.instance.client.from('requests').insert({
        'requester_id': user.id,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'budget': double.tryParse(_budgetController.text.trim()) ?? 0.0,
        'category': _selectedCategory,
      });

      if (mounted) {
        Navigator.pop(
          context,
          true,
        ); // Return true so HomeScreen knows to refresh
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request posted successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: kPremiumRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PREMIUM INPUT STYLING ---
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
      appBar: AppBar(
        title: const Text(
          'Post a Request',
          style: TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: kTextPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header instructions
            const Text(
              "Tell the campus what you need.",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Sellers with matching items will be able to message you directly.",
              style: TextStyle(
                fontSize: 15,
                color: kTextSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),

            // --- MAIN DETAILS CARD ---
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'WHAT ARE YOU LOOKING FOR?',
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
                      'e.g. Physics 101 Textbook',
                      Icons.search_rounded,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                                child: Text(
                                  c,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => _selectedCategory = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --- DETAILS & BUDGET CARD ---
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'DETAILS & BUDGET',
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
                    controller: _budgetController,
                    keyboardType: const TextInputType.numberWithOptions(
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
                      'Max Willing to Pay',
                      Icons.attach_money,
                      prefix: 'AED ',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _descController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: kTextPrimary, height: 1.4),
                    decoration: _premiumInputDecoration(
                      'Any specific details? (Optional)',
                      Icons.notes_rounded,
                    ).copyWith(alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
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
            onPressed: _isLoading ? null : _submitRequest,
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
                      'Post Request',
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
