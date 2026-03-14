import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../services/photo_service.dart';
import '../services/data_provider.dart';

class AddPersonalTransactionScreen extends StatefulWidget {
  const AddPersonalTransactionScreen({super.key});

  @override
  State<AddPersonalTransactionScreen> createState() =>
      _AddPersonalTransactionScreenState();
}

class _AddPersonalTransactionScreenState
    extends State<AddPersonalTransactionScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _type = 'expense'; // 'income' or 'expense'
  String _paymentMode = 'online'; // 'cash' or 'online'
  String? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  XFile? _selectedImage;
  bool _isLoading = false;

  final List<Map<String, String>> _expenseCategories = [
    {'name': 'Food', 'icon': '🍔'},
    {'name': 'Transport', 'icon': '🚌'},
    {'name': 'Accommodation', 'icon': '🏠'},
    {'name': 'Entertainment', 'icon': '🎬'},
    {'name': 'Shopping', 'icon': '🛍️'},
    {'name': 'Bills', 'icon': '📄'},
    {'name': 'Health', 'icon': '💊'},
    {'name': 'Education', 'icon': '📚'},
    {'name': 'Other', 'icon': '📦'},
  ];

  final List<Map<String, String>> _incomeCategories = [
    {'name': 'Salary', 'icon': '💰'},
    {'name': 'Freelance', 'icon': '💻'},
    {'name': 'Investment', 'icon': '📈'},
    {'name': 'Refund', 'icon': '🔄'},
    {'name': 'Gift', 'icon': '🎁'},
    {'name': 'Other', 'icon': '📦'},
  ];
  final List<String> _emojiPresets = const [
    '🍔',
    '🚌',
    '🏠',
    '🎬',
    '🛍️',
    '📦',
    '🍺',
    '✈️',
    '💊',
    '📚',
    '🎮',
    '⚽',
    '🛒',
    '💰',
    '💻',
    '📈',
    '🔄',
    '🎁',
    '🪑',
    '🔧',
    '⛽',
  ];

  List<Map<String, dynamic>> get _currentCategories =>
      _type == 'income' ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    // Categories are now loaded based on transaction type
  }

  Future<void> _saveTransaction() async {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) throw Exception('User not logged in');

      String? photoUrl;
      if (_selectedImage != null) {
        try {
          final bytes = await _selectedImage!.readAsBytes();
          final fileName =
              'personal_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final path = 'personal_transactions/$fileName';

          await Supabase.instance.client.storage
              .from('photos')
              .uploadBinary(path, bytes);

          photoUrl = Supabase.instance.client.storage
              .from('photos')
              .getPublicUrl(path);
        } catch (e) {
          debugPrint('Error uploading photo: $e');
        }
      }

      await Supabase.instance.client.from('personal_transactions').insert({
        'user_id': currentUser.id,
        'name': _nameController.text,
        'amount': amount,
        'type': _type,
        'payment_mode': _paymentMode,
        'category': _selectedCategory,
        'date': _selectedDate.toIso8601String(),
        'notes':
            _notesController.text.isNotEmpty ? _notesController.text : null,
        'photo_url': photoUrl,
      });

      if (mounted) {
        DataProvider().refreshPersonal();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Add Transaction'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type Selector
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _type = 'expense';
                              _selectedCategory =
                                  null; // Reset category when type changes
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _type == 'expense'
                                    ? Colors.red
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.arrow_upward,
                                    color: _type == 'expense'
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Expense',
                                    style: TextStyle(
                                      color: _type == 'expense'
                                          ? Colors.white
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _type = 'income';
                              _selectedCategory =
                                  null; // Reset category when type changes
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _type == 'income'
                                    ? Colors.green
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.arrow_downward,
                                    color: _type == 'income'
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Income',
                                    style: TextStyle(
                                      color: _type == 'income'
                                          ? Colors.white
                                          : Colors.grey,
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

                  const SizedBox(height: 24),

                  // Name
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: 'E.g. Groceries',
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Amount
                  TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      hintText: '0.00',
                      prefixText: '₹ ',
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Mode
                  const Text(
                    'Payment Mode',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _paymentMode = 'cash'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _paymentMode == 'cash'
                                    ? const Color(0xFF30D158)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.money,
                                    color: _paymentMode == 'cash'
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Cash',
                                    style: TextStyle(
                                      color: _paymentMode == 'cash'
                                          ? Colors.white
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _paymentMode = 'online'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _paymentMode == 'online'
                                    ? const Color(0xFF0A84FF)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.credit_card,
                                    color: _paymentMode == 'online'
                                        ? Colors.white
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Online',
                                    style: TextStyle(
                                      color: _paymentMode == 'online'
                                          ? Colors.white
                                          : Colors.grey,
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

                  const SizedBox(height: 16),

                  // Category
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _showCategoryDialog,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCategory ?? 'Select Category',
                              style: TextStyle(
                                color: _selectedCategory != null
                                    ? Colors.white
                                    : Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date
                  const Text(
                    'Date',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Notes (Optional)',
                      hintText: 'Add any notes...',
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Photo
                  GestureDetector(
                    onTap: () async {
                      final img = await PhotoService.pickImage();
                      if (img != null) setState(() => _selectedImage = img);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _selectedImage != null
                              ? const Color(0xFF0A84FF)
                              : Colors.grey,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.camera_alt,
                            color: _selectedImage != null
                                ? const Color(0xFF0A84FF)
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedImage != null
                                ? 'Photo attached'
                                : 'Add Photo (Optional)',
                            style: TextStyle(
                              color: _selectedImage != null
                                  ? Colors.white
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveTransaction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Save Transaction',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
            _type == 'income'
                ? 'Select Income Category'
                : 'Select Expense Category',
            style: const TextStyle(color: Colors.white)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SizedBox(
            width: double.maxFinite,
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                ..._currentCategories.map((category) => ListTile(
                      leading: Text(category['icon']!,
                          style: const TextStyle(fontSize: 24)),
                      title: Text(
                        category['name']!,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      trailing: _selectedCategory == category['name']
                          ? const Icon(Icons.check, color: Color(0xFF0A84FF))
                          : null,
                      onTap: () {
                        setState(() => _selectedCategory = category['name']);
                        Navigator.pop(context);
                      },
                    )),
                const Divider(color: Colors.grey),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.white),
                  title: const Text('Manage Categories',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _showManageCategoriesDialog();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showManageCategoriesDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final categories =
              _type == 'income' ? _incomeCategories : _expenseCategories;
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: Text(
                _type == 'income'
                    ? 'Manage Income Categories'
                    : 'Manage Expense Categories',
                style: const TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: categories
                            .map((c) => ListTile(
                                  leading: Text(c['icon']!,
                                      style: const TextStyle(fontSize: 24)),
                                  title: Text(
                                    c['name']!,
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        categories.remove(c);
                                      });
                                      setState(() {});
                                    },
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _showAddPersonalCategoryDialog(categories);
                        setDialogState(() {});
                        setState(() {});
                      },
                      child: const Text('Add New Category'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddPersonalCategoryDialog(
      List<Map<String, String>> targetList) async {
    final nameController = TextEditingController();
    String selectedEmoji = '📦';
    final emojiController = TextEditingController(text: selectedEmoji);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Add Category',
                style: TextStyle(color: Colors.white)),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Category Name',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emojiController,
                      maxLength: 8,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Custom Emoji (type/paste)',
                        labelStyle: TextStyle(color: Colors.grey),
                        counterText: '',
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey)),
                      ),
                      onChanged: (value) {
                        final customEmoji = value.trim();
                        if (customEmoji.isNotEmpty) {
                          setDialogState(() => selectedEmoji = customEmoji);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('Quick picks',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: _emojiPresets
                          .map((emoji) => GestureDetector(
                                onTap: () {
                                  setDialogState(() => selectedEmoji = emoji);
                                  emojiController.text = emoji;
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: selectedEmoji == emoji
                                        ? Colors.blue.withValues(alpha: 0.3)
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(emoji,
                                      style: const TextStyle(fontSize: 24)),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final categoryName = nameController.text.trim();
                  if (categoryName.isNotEmpty) {
                    final customEmoji = emojiController.text.trim();
                    if (customEmoji.isNotEmpty) {
                      selectedEmoji = customEmoji;
                    }
                    targetList.add({
                      'name': categoryName,
                      'icon': selectedEmoji,
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }
}
