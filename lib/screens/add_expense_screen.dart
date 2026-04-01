import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/photo_service.dart';
import '../services/sync_service.dart';
import '../services/data_provider.dart';
import '../utils/category_icon_utils.dart';

class AddExpenseScreen extends StatefulWidget {
  final String tricountId;
  final Map<String, dynamic>? expense;

  const AddExpenseScreen({
    super.key,
    required this.tricountId,
    this.expense,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final String _selectedCurrency = '₹'; // Default from screenshot
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  XFile? _selectedImage;

  // Participants logic
  List<Map<String, dynamic>> _participants = [];
  String? _paidByUserId;
  String? _transferRecipientId;
  final Map<String, bool> _splitInvolved = {};
  bool _isSplit = true;
  bool _isLoading = true;

  // Categories - Expense
  final List<Map<String, String>> _defaultExpenseCategories = [
    {'name': 'Food', 'icon': '🍔'},
    {'name': 'Groceries', 'icon': '🛒'},
    {'name': 'Transport', 'icon': '🚌'},
    {'name': 'Accommodation', 'icon': '🏠'},
    {'name': 'Entertainment', 'icon': '🎬'},
    {'name': 'Shopping', 'icon': '🛍️'},
    {'name': 'Restaurants', 'icon': '🍝'},
    {'name': 'Transfer', 'icon': '💸'},
    {'name': 'Rent', 'icon': '🏡'},
    {'name': 'Other', 'icon': '🧾'},
  ];
  // Categories - Income
  final List<Map<String, String>> _defaultIncomeCategories = [
    {'name': 'Salary', 'icon': '💰'},
    {'name': 'Freelance', 'icon': '💻'},
    {'name': 'Investment', 'icon': '📈'},
    {'name': 'Refund', 'icon': '🔄'},
    {'name': 'Gift', 'icon': '🎁'},
    {'name': 'Other', 'icon': '🧾'},
  ];
  final List<String> _emojiPresets = const [
    '🍔',
    '🚌',
    '🏠',
    '🎬',
    '🛍️',
    '🧾',
    '🍺',
    '✈️',
    '💊',
    '📚',
    '🎮',
    '⚽',
    '🛒',
    '🪑',
    '🔧',
    '⛽',
    '💰',
    '💻',
    '📈',
    '🔄',
    '🎁',
  ];
  List<Map<String, dynamic>> _allExpenseCategories = [];
  List<Map<String, dynamic>> _allIncomeCategories = [];
  List<Map<String, dynamic>> get _allCategories =>
      _tabController.index == 1 ? _allIncomeCategories : _allExpenseCategories;

  // Split Mode
  String _splitMode = 'Equally'; // Equally, Unequal, Percentages
  final Map<String, double> _splitAmounts = {}; // For Unequal mode
  final Map<String, TextEditingController> _splitControllers = {};

  bool _settleDebts = true;
  String _paymentMethod = 'Online'; // 'Online', 'Cash'

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _amountController.addListener(_updateSplitAmounts);
    _fetchData();
  }

  String _participantId(Map<String, dynamic> participant) {
    final raw = participant['id'] ?? participant['user_id'];
    return raw?.toString() ?? '';
  }

  void _updateSplitAmounts() {
    if (_splitMode == 'Equally') {
      setState(() {}); // Trigger rebuild to update displayed split amounts
    }
  }

  void _updateTotalFromSplits() {
    if (_splitMode == 'Unequal') {
      double total = 0;
      for (var entry in _splitControllers.entries) {
        // Only include if involved?
        // The UI shows text fields only if involved (checked).
        // But the controller exists.
        // We should check if the participant is involved.
        if (_splitInvolved[entry.key] == true) {
          total += double.tryParse(entry.value.text) ?? 0;
        }
      }

      // Update total amount
      // We use a flag or check to avoid loops if needed, but here the flow is one way:
      // Split Edit -> Total Update.
      // Total Edit -> (No Split Update in Unequal mode currently).

      // We need to format it nicely
      final newText = total.toStringAsFixed(2);
      if (_amountController.text != newText) {
        _amountController.text = newText;
      }
    }
  }

  Future<void> _fetchData() async {
    try {
      // Fetch Tricount participants
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select('participants, participant_ids')
          .eq('id', widget.tricountId)
          .single();

      if (mounted) {
        setState(() {
          // Parse participants
          // We expect participants to be stored in the JSONB column 'participants'
          // If it's empty, we might need to fetch profiles using participant_ids
          // For now, let's assume the 'participants' JSONB is being maintained.
          // If not, we fallback to fetching profiles.

          final List<dynamic> jsonParticipants =
              tricountRes['participants'] ?? [];
          if (jsonParticipants.isNotEmpty) {
            _participants = List<Map<String, dynamic>>.from(jsonParticipants);
          } else {
            // Fallback: fetch from users table using IDs (only works for real users)
            // This part might need adjustment if we strictly use the JSONB column for ghosts
            _participants = [];
          }

          // If we have real users in participant_ids but not in jsonb, we should probably fetch them
          // But let's stick to the existing pattern.
          // If the previous code didn't populate 'participants' jsonb correctly, we might have issues.
          // Let's ensure we have at least the current user.

          final currentUser = Supabase.instance.client.auth.currentUser;
          if (_participants.isEmpty && currentUser != null) {
            _participants.add({
              'id': currentUser.id,
              'name': currentUser.userMetadata?['name'] ?? 'Me',
              'photo_url': currentUser.userMetadata?['photo_url'],
            });
          }

          // Initialize split map
          for (var p in _participants) {
            final participantId = _participantId(p);
            if (participantId.isEmpty) continue;
            _splitInvolved[participantId] = true;
            // Initialize controllers
            if (!_splitControllers.containsKey(participantId)) {
              final controller = TextEditingController(text: '0.00');
              controller.addListener(_updateTotalFromSplits);
              _splitControllers[participantId] = controller;
            }
          }

          // Default payer to current user
          if (currentUser != null) {
            // Check if current user is in participants
            final me = _participants.firstWhere(
                (p) => _participantId(p) == currentUser.id,
                orElse: () => _participants.isNotEmpty
                    ? _participants.first
                    : {'id': ''});
            _paidByUserId = _participantId(me);
          }

          if (widget.expense != null) {
            _initializeFromExpense();
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initializeFromExpense() {
    final expense = widget.expense!;
    _titleController.text = expense['name'] ?? '';
    _amountController.text =
        (double.tryParse(expense['value'].toString()) ?? 0).toStringAsFixed(2);
    _selectedDate = DateTime.parse(expense['created_at']);
    _selectedCategory = expense['category'];
    _paidByUserId = expense['user_id'];
    _paymentMethod = expense['payment_method'] ?? 'Online';

    // Set Type
    final type = expense['type'] ?? 'expense';
    if (type == 'income') {
      _tabController.index = 1;
    } else if (type == 'transfer') {
      _tabController.index = 2;
    } else {
      _tabController.index = 0;
    }

    // Set Split
    final involvedData = expense['involved_participants'];

    // Reset split involved
    for (var key in _splitInvolved.keys) {
      _splitInvolved[key] = false;
    }

    if (involvedData is List) {
      bool isUnequal = false;
      double totalAmount = double.tryParse(expense['value'].toString()) ?? 0;

      for (var item in involvedData) {
        if (item is Map) {
          final userId = item['user_id'] ?? item['id'];
          final amount = double.tryParse(item['amount'].toString()) ?? 0;

          _splitInvolved[userId] = true;
          _splitAmounts[userId] = amount;
          if (_splitControllers.containsKey(userId)) {
            _splitControllers[userId]!.text = amount.toStringAsFixed(2);
          }

          // Check if it looks like unequal split
          // If we have amounts, we can check if they are all equal
        }
      }

      // Determine mode
      // If we have amounts in _splitAmounts, check if they are equal
      if (_splitAmounts.isNotEmpty) {
        final count = _splitAmounts.length;
        final expectedShare = totalAmount / count;

        for (var amount in _splitAmounts.values) {
          if ((amount - expectedShare).abs() > 0.05) {
            isUnequal = true;
            break;
          }
        }
      }

      if (isUnequal) {
        _splitMode = 'Unequal';
      } else {
        _splitMode = 'Equally';
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _amountController.removeListener(_updateSplitAmounts);
    _amountController.dispose();
    for (var controller in _splitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveExpense() async {
    if (_titleController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and amount')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final double amount = double.parse(_amountController.text);

      // Validate Unequal Split
      if (_splitMode == 'Unequal') {
        double sum = 0;
        for (var val in _splitAmounts.values) {
          sum += val;
        }
        // Allow small float error
        if ((sum - amount).abs() > 0.01) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Split amounts (₹${sum.toStringAsFixed(2)}) do not match total (₹${amount.toStringAsFixed(2)})')),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      // Prepare involved participants
      List<dynamic> involvedList = [];

      if (_splitMode == 'Equally') {
        // Equal split - store objects with calculated amount
        final selectedIds = _splitInvolved.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList();

        final splitAmount =
            selectedIds.isNotEmpty ? amount / selectedIds.length : 0;

        involvedList = selectedIds
            .map((id) => {'user_id': id, 'amount': splitAmount})
            .toList();
      } else {
        // For Unequal, we might want to store the amounts too.
        // But the current schema expects a list of IDs (jsonb).
        // If we want to store amounts, we should change the schema or store objects.
        if (_splitMode == 'Unequal') {
          involvedList = _splitAmounts.entries
              .where((e) => e.value > 0)
              .map((e) => {'user_id': e.key, 'amount': e.value})
              .toList();
        }
      }

      String type = 'expense';
      if (_tabController.index == 1) type = 'income';
      if (_tabController.index == 2) type = 'transfer';

      // Normalize participants and guard against malformed split payloads.
      // This prevents full expense amount from being treated as a single user's share.
      if (type != 'transfer') {
        final normalized = <Map<String, dynamic>>[];
        for (final item in involvedList) {
          if (item is! Map) continue;
          final uid = (item['user_id'] ?? item['id'])?.toString() ?? '';
          if (uid.isEmpty) continue;
          final amt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0;
          if (amt <= 0) continue;
          normalized.add({'user_id': uid, 'amount': amt});
        }

        if (normalized.isEmpty) {
          final selectedIds = _splitInvolved.entries
              .where((e) => e.value)
              .map((e) => e.key)
              .where((id) => id.isNotEmpty)
              .toList();
          final fallbackIds = selectedIds.isNotEmpty
              ? selectedIds
              : (_participants
                  .map(_participantId)
                  .where((id) => id.isNotEmpty)
                  .toList());
          final count = fallbackIds.length;
          final equalShare = count > 0 ? amount / count : amount;
          involvedList = fallbackIds
              .map((id) => {'user_id': id, 'amount': equalShare})
              .toList();
        } else {
          final sum = normalized.fold<double>(
              0, (prev, item) => prev + (item['amount'] as double));
          if ((sum - amount).abs() > 0.01 && sum > 0) {
            // Keep user's intended relative weights, but force total to match bill.
            final scale = amount / sum;
            involvedList = normalized
                .map((item) => {
                      'user_id': item['user_id'],
                      'amount': (item['amount'] as double) * scale,
                    })
                .toList();
          } else {
            involvedList = normalized;
          }
        }
      }

      // Get payer name for backward compatibility
      final payer = _participants.firstWhere(
          (p) => _participantId(p) == _paidByUserId,
          orElse: () => {'name': 'Unknown'});

      // For transfer, build involvedList from the recipient, not from split
      if (type == 'transfer') {
        if (_transferRecipientId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a transfer recipient')),
          );
          setState(() => _isLoading = false);
          return;
        }
        involvedList = [
          {'user_id': _transferRecipientId, 'amount': amount}
        ];
      }

      if (type == 'transfer' && _settleDebts) {
        await _handleDebtSettlement(amount, payer, involvedList);
        if (mounted) {
          DataProvider().refreshTricountExpenses(widget.tricountId);
          Navigator.pop(context, true);
        }
        return;
      }

      final expenseData = {
        'tricount_id': widget.tricountId,
        'name': _titleController.text,
        'paid_by': payer['name'], // Legacy field
        'user_id': _paidByUserId, // Using the selected payer ID
        'value': amount,
        'category':
            type == 'transfer' ? 'Transfer' : (_selectedCategory ?? 'Other'),
        'created_at': _selectedDate.toIso8601String(),
        'involved_participants': involvedList, // New field
        'type': type,
        'payment_method': _paymentMethod,
      };

      if (widget.expense != null) {
        try {
          await SyncService().updateExpense(widget.expense!['id'], expenseData);
        } catch (e) {
          // Retry with user_id = null if FK violation (Ghost user)
          if (e.toString().contains('23503') ||
              e.toString().contains('expenses_user_id_fkey')) {
            expenseData['user_id'] = null;
            await SyncService()
                .updateExpense(widget.expense!['id'], expenseData);
          } else {
            rethrow;
          }
        }
      } else {
        try {
          await SyncService().insertExpense(expenseData);
          // Sync to personal tracker
          await _syncToPersonalTracker(expenseData, null);
        } catch (e) {
          // Retry with user_id = null if FK violation (Ghost user)
          if (e.toString().contains('23503') ||
              e.toString().contains('expenses_user_id_fkey')) {
            expenseData['user_id'] = null;
            await SyncService().insertExpense(expenseData);
            await _syncToPersonalTracker(expenseData, null);
          } else {
            rethrow;
          }
        }
      }

      // Image upload only works if online and we have an ID (which we don't if offline insert)
      // For now, we only support image upload if online and successful
      if (_selectedImage != null && SyncService().isOnline) {
        // We need the ID of the inserted expense to upload image.
        // Since SyncService abstracts this, we might need to refactor if we want image support.
        // But for now, let's just say image upload is skipped if offline or if we can't get ID easily.
        // Actually, if we are online, we could just do the old way?
        // But we want to use SyncService to handle potential network errors gracefully.

        // If we are online, we can try to fetch the latest expense or just let the user know.
        // Or, we can modify SyncService to return the ID if online.
        // But SyncService returns void.

        // Let's just warn the user if they try to upload image while offline.
        if (!SyncService().isOnline) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Image upload skipped (offline mode)')),
            );
          }
        } else {
          // If online, we can try to upload. But we don't have the ID from SyncService.
          // This is a limitation of the current simple SyncService.
          // To fix this properly, SyncService should return the ID if online.
          // But for now, let's leave image upload for online-only direct calls or improve SyncService later.
          // Given the user request "add expenses offline", text data is priority.
        }
      }

      if (mounted) {
        // Refresh DataProvider so all screens see the new expense
        DataProvider().refreshTricountExpenses(widget.tricountId);
        DataProvider().refreshPersonal();
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving expense: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncToPersonalTracker(
      Map<String, dynamic> expenseData, dynamic result) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;
      final expenseType = (expenseData['type']?.toString() ?? 'expense');
      final payerId = (expenseData['user_id'] ?? _paidByUserId)?.toString();
      final totalAmount =
          double.tryParse(expenseData['value']?.toString() ?? '0') ?? 0;
      final paymentMode =
          (expenseData['payment_method'] as String?)?.toLowerCase() ?? 'online';

      String txType;
      String txName = (expenseData['name']?.toString() ?? 'Group transaction');
      String noteText;
      double amountToLog;

      if (expenseType == 'expense') {
        // Cash-tracking mode: only the actual payer logs the full outflow.
        if (payerId != currentUser.id) return;
        txType = 'expense';
        amountToLog = totalAmount;
        noteText = 'Group expense payment (full bill paid by you)';
      } else if (expenseType == 'income') {
        if (payerId != currentUser.id) return;
        txType = 'income';
        amountToLog = totalAmount;
        noteText = 'Group income received';
      } else if (expenseType == 'transfer') {
        String? receiverId;
        final involved = expenseData['involved_participants'];
        if (involved is List && involved.isNotEmpty) {
          final first = involved.first;
          if (first is Map) {
            receiverId = (first['user_id'] ?? first['id'])?.toString();
          }
        }

        if (payerId == currentUser.id) {
          txType = 'expense';
          amountToLog = totalAmount;
          noteText = 'Transfer sent for group settlement';
        } else if (receiverId == currentUser.id) {
          txType = 'income';
          amountToLog = totalAmount;
          noteText = 'Transfer received for group settlement';
        } else {
          return;
        }
      } else {
        return;
      }

      if (amountToLog <= 0) return;

      await Supabase.instance.client.from('personal_transactions').insert({
        'user_id': currentUser.id,
        'name': txName,
        'amount': amountToLog,
        'type': txType,
        'payment_mode': paymentMode,
        'category': expenseType == 'transfer'
            ? 'Transfer'
            : (expenseData['category'] ?? 'Other'),
        'date': expenseData['created_at'],
        'notes': noteText,
      });
    } catch (e) {
      debugPrint('Error syncing to personal tracker: $e');
      // Don't fail the main operation if personal sync fails
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.expense != null ? 'Edit Expense' : 'Add Expense'),
        actions: [
          // Debug button to check participants
          // IconButton(icon: Icon(Icons.bug_report), onPressed: () => print(_participants)),
        ],
      ),
      body: Column(
        children: [
          // Tabs
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: const Color(0xFF0A84FF),
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              dividerColor: Colors.transparent,
              labelPadding: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              tabs: const [
                Tab(text: 'Expense'),
                Tab(text: 'Income'),
                Tab(text: 'Transfer'),
              ],
              onTap: (_) {
                // Reset category when switching types
                setState(() => _selectedCategory = null);
              },
            ),
          ),

          if (_tabController.index == 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CheckboxListTile(
                title: const Text('Settle existing debts',
                    style: TextStyle(color: Colors.white)),
                value: _settleDebts,
                onChanged: (val) => setState(() => _settleDebts = val ?? false),
                activeColor: const Color(0xFF0A84FF),
                checkColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text('Title',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'E.g. Drinks',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF1C1C1E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_tabController.index != 2) ...[
                        const SizedBox(width: 8),
                        _buildIconButton(
                          icon: Icons.local_offer,
                          child: _selectedCategory != null
                              ? Text(_getCategoryIcon(_selectedCategory!),
                                  style: const TextStyle(fontSize: 24))
                              : null,
                          color: _selectedCategory != null
                              ? const Color(0xFF0A84FF)
                              : Colors.grey,
                          onTap: _showCategoryDialog,
                        ),
                      ],
                      const SizedBox(width: 8),
                      _buildIconButton(
                        icon: Icons.camera_alt,
                        color: _selectedImage != null
                            ? const Color(0xFF0A84FF)
                            : Colors.grey,
                        onTap: () async {
                          final img = await PhotoService.pickImage();
                          if (img != null) setState(() => _selectedImage = img);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Amount
                  const Text('Amount',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(_selectedCurrency,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16)),
                            const Icon(Icons.keyboard_arrow_down,
                                color: Colors.grey, size: 16),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            filled: true,
                            fillColor: const Color(0xFF1C1C1E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Paid By & When
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 420;

                      final paidBySection = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paid By',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _paidByUserId,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1C1C1E),
                                icon: const Icon(Icons.keyboard_arrow_down,
                                    color: Colors.grey),
                                items: _participants
                                    .where((p) => _participantId(p).isNotEmpty)
                                    .map((p) {
                                  final participantId = _participantId(p);
                                  return DropdownMenuItem<String>(
                                    value: participantId,
                                    child: Text(
                                      p['name'] ?? 'Unknown',
                                      style:
                                          const TextStyle(color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() => _paidByUserId = value);
                                },
                              ),
                            ),
                          ),
                        ],
                      );

                      final dateSection = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Date',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Color(0xFF0A84FF),
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1C1C1E),
                                        onSurface: Colors.white,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      DateFormat('dd/MM/yyyy')
                                          .format(_selectedDate),
                                      style:
                                          const TextStyle(color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            paidBySection,
                            const SizedBox(height: 16),
                            dateSection,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: paidBySection),
                          const SizedBox(width: 16),
                          Expanded(child: dateSection),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Payment Method
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment Method',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
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
                                onTap: () =>
                                    setState(() => _paymentMethod = 'Online'),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _paymentMethod == 'Online'
                                        ? const Color(0xFF0A84FF)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Online',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _paymentMethod = 'Cash'),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _paymentMethod == 'Cash'
                                        ? const Color(0xFF30D158)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Cash',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Transfer: show recipient picker instead of split
                  if (_tabController.index == 2) ...[
                    const Text('Transfer To',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _transferRecipientId,
                          isExpanded: true,
                          hint: const Text('Select recipient',
                              style: TextStyle(color: Colors.grey)),
                          dropdownColor: const Color(0xFF1C1C1E),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              color: Colors.grey),
                          items: _participants
                              .where((p) =>
                                  _participantId(p).isNotEmpty &&
                                  _participantId(p) != _paidByUserId)
                              .map((p) {
                            final participantId = _participantId(p);
                            return DropdownMenuItem<String>(
                              value: participantId,
                              child: Text(
                                p['name'] ?? 'Unknown',
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _transferRecipientId = value);
                          },
                        ),
                      ),
                    ),
                  ],

                  // Split (only for expense/income, not transfer)
                  if (_tabController.index != 2) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 380;
                        final splitToggle = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _isSplit,
                              onChanged: (val) =>
                                  setState(() => _isSplit = val ?? true),
                              fillColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return const Color(0xFF0A84FF);
                                }
                                return Colors.grey;
                              }),
                            ),
                            const Text('Split',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16)),
                          ],
                        );

                        final modeDropdown = !_isSplit
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[800]!),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _splitMode,
                                    dropdownColor: const Color(0xFF1C1C1E),
                                    isDense: true,
                                    items: ['Equally', 'Unequal', 'Percentages']
                                        .map((mode) => DropdownMenuItem(
                                              value: mode,
                                              child: Text(mode,
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14)),
                                            ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _splitMode = val);
                                      }
                                    },
                                    icon: const Icon(Icons.unfold_more,
                                        color: Colors.grey, size: 16),
                                  ),
                                ),
                              );

                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              splitToggle,
                              if (_isSplit) ...[
                                const SizedBox(height: 8),
                                modeDropdown,
                              ],
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            splitToggle,
                            modeDropdown,
                          ],
                        );
                      },
                    ),
                    if (_isSplit) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: _participants
                              .where((p) => _participantId(p).isNotEmpty)
                              .map((p) {
                            final participantId = _participantId(p);
                            final isSelected =
                                _splitInvolved[participantId] ?? false;

                            // Calculate display amount based on mode
                            String displayAmount = '₹0.00';
                            final totalAmount =
                                double.tryParse(_amountController.text) ?? 0;

                            if (_splitMode == 'Equally') {
                              final selectedCount =
                                  _splitInvolved.values.where((v) => v).length;
                              final splitAmount = selectedCount > 0
                                  ? totalAmount / selectedCount
                                  : 0;
                              displayAmount =
                                  '₹${splitAmount.toStringAsFixed(2)}';
                            }

                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  _splitInvolved[participantId] = val ?? false;
                                });
                              },
                              title: Text(p['name'] ?? 'Unknown',
                                  style: const TextStyle(color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1),
                              secondary: _splitMode == 'Equally'
                                  ? Text(
                                      isSelected ? displayAmount : '₹0.00',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    )
                                  : SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller:
                                            _splitControllers[participantId],
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        style: const TextStyle(
                                            color: Colors.white),
                                        decoration: InputDecoration(
                                          hintText: '0.00',
                                          hintStyle: TextStyle(
                                              color: Colors.grey[600]),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            borderSide: BorderSide(
                                                color: Colors.grey[800]!),
                                          ),
                                        ),
                                        onChanged: (val) {
                                          final amount =
                                              double.tryParse(val) ?? 0;
                                          _splitAmounts[participantId] = amount;
                                        },
                                      ),
                                    ),
                              activeColor: const Color(0xFF0A84FF),
                              checkColor: Colors.white,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 32),

                  // Add Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveExpense,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Add',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDebtSettlement(double transferAmount,
      Map<String, dynamic> payer, List<dynamic> involvedList) async {
    if (involvedList.isEmpty) return;

    // Get Receiver ID
    String receiverId;
    if (involvedList.first is Map) {
      receiverId = involvedList.first['user_id'];
    } else {
      receiverId = involvedList.first;
    }

    final payerId = _paidByUserId!;
    final currentUser = Supabase.instance.client.auth.currentUser;
    final receiver = _participants.firstWhere(
        (p) => _participantId(p) == receiverId,
        orElse: () => {'name': 'Unknown'});
    final payerName = payer['name']?.toString() ?? 'Someone';
    final receiverName = receiver['name']?.toString() ?? 'Someone';

    // Find expenses where:
    // Paid By = Receiver (receiverId)
    // Involved contains Payer (payerId)
    // And Payer has not fully paid.

    final expenses = await Supabase.instance.client
        .from('expenses')
        .select()
        .eq('tricount_id', widget.tricountId)
        .eq('user_id', receiverId) // Paid by Receiver
        .order('created_at', ascending: true); // Oldest first

    double remainingTransfer = transferAmount;

    for (var expense in expenses) {
      if (remainingTransfer <= 0.01) break;

      final involved =
          List<dynamic>.from(expense['involved_participants'] ?? []);
      bool updated = false;
      final settlementEntries = <Map<String, dynamic>>[];

      final updatedInvolved = involved.map((item) {
        if (item is Map) {
          final uid = item['user_id'] ?? item['id'];
          if (uid == payerId) {
            final amount = double.tryParse(item['amount'].toString()) ?? 0;
            final paid =
                double.tryParse(item['paid_amount']?.toString() ?? '0') ?? 0;
            final debt = amount - paid;

            if (debt > 0) {
              double pay = 0;
              if (remainingTransfer >= debt) {
                pay = debt;
                remainingTransfer -= debt;
              } else {
                pay = remainingTransfer;
                remainingTransfer = 0;
              }

              if (currentUser != null && pay > 0) {
                if (currentUser.id == receiverId) {
                  settlementEntries.add({
                    'user_id': currentUser.id,
                    'name': expense['name'] ?? 'Settlement received',
                    'amount': pay,
                    'type': 'income',
                    'payment_mode': _paymentMethod.toLowerCase(),
                    'category': 'Transfer',
                    'date': DateTime.now().toIso8601String(),
                    'notes': 'Settlement received from $payerName',
                  });
                } else if (currentUser.id == payerId) {
                  settlementEntries.add({
                    'user_id': currentUser.id,
                    'name': expense['name'] ?? 'Settlement paid',
                    'amount': pay,
                    'type': 'expense',
                    'payment_mode': _paymentMethod.toLowerCase(),
                    'category': 'Transfer',
                    'date': DateTime.now().toIso8601String(),
                    'notes': 'Settlement paid to $receiverName',
                  });
                }
              }

              updated = true;
              return {...item, 'paid_amount': paid + pay};
            }
          }
        }
        return item;
      }).toList();

      if (updated) {
        await SyncService().updateExpense(
            expense['id'], {'involved_participants': updatedInvolved});
      }

      if (settlementEntries.isNotEmpty) {
        await Supabase.instance.client
            .from('personal_transactions')
            .insert(settlementEntries);
      }
    }

    // If remaining > 0, create a Transfer for the rest
    if (remainingTransfer > 0.01) {
      final expenseData = {
        'tricount_id': widget.tricountId,
        'name':
            _titleController.text.isEmpty ? 'Transfer' : _titleController.text,
        'paid_by': payer['name'],
        'user_id': payerId,
        'value': remainingTransfer,
        'category': 'Transfer',
        'created_at': _selectedDate.toIso8601String(),
        'involved_participants': involvedList,
        'type': 'transfer',
        'payment_method': _paymentMethod,
      };
      await SyncService().insertExpense(expenseData);

      if (currentUser != null) {
        if (currentUser.id == receiverId) {
          await Supabase.instance.client.from('personal_transactions').insert({
            'user_id': currentUser.id,
            'name': expenseData['name'],
            'amount': remainingTransfer,
            'type': 'income',
            'payment_mode': _paymentMethod.toLowerCase(),
            'category': 'Transfer',
            'date': DateTime.now().toIso8601String(),
            'notes': 'Transfer received from $payerName',
          });
        } else if (currentUser.id == payerId) {
          await Supabase.instance.client.from('personal_transactions').insert({
            'user_id': currentUser.id,
            'name': expenseData['name'],
            'amount': remainingTransfer,
            'type': 'expense',
            'payment_mode': _paymentMethod.toLowerCase(),
            'category': 'Transfer',
            'date': DateTime.now().toIso8601String(),
            'notes': 'Transfer sent to $receiverName',
          });
        }
      }
    }
  }

  Widget _buildIconButton(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap,
      Widget? child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child ?? Icon(icon, color: color),
      ),
    );
  }

  String _getCategoryIcon(String categoryName) {
    final key = categoryName.trim().toLowerCase();
    for (final c in _allCategories) {
      final name = (c['name']?.toString() ?? '').trim().toLowerCase();
      if (name == key) {
        final icon = (c['icon']?.toString() ?? '').trim();
        if (icon.isNotEmpty) return icon;
      }
    }
    return categoryIconForName(categoryName);
  }

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final String? expCatsString = prefs.getString('group_expense_categories');
    final String? incCatsString = prefs.getString('group_income_categories');
    final List<Map<String, dynamic>> importedCategories = [];

    try {
      final rows = await Supabase.instance.client
          .from('categories')
          .select('name,icon,color')
          .eq('tricount_id', widget.tricountId);
      importedCategories.addAll(List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // If table/query is unavailable, keep local categories only.
    }

    List<Map<String, dynamic>> mergeByName(
        List<Map<String, dynamic>> base, List<Map<String, dynamic>> incoming) {
      final result = List<Map<String, dynamic>>.from(base);
      final indexByName = <String, int>{};
      for (var i = 0; i < result.length; i++) {
        final name = (result[i]['name']?.toString() ?? '').trim().toLowerCase();
        if (name.isNotEmpty) indexByName[name] = i;
      }

      for (final c in incoming) {
        final rawName = (c['name']?.toString() ?? '').trim();
        if (rawName.isEmpty) continue;
        final key = rawName.toLowerCase();
        final icon = (c['icon']?.toString() ?? '').trim();
        final payload = {
          'name': rawName,
          'icon': icon.isNotEmpty ? icon : categoryIconForName(rawName),
        };

        if (indexByName.containsKey(key)) {
          result[indexByName[key]!] = payload;
        } else {
          result.add(payload);
          indexByName[key] = result.length - 1;
        }
      }

      return result;
    }

    setState(() {
      final localExpense = expCatsString != null
          ? List<Map<String, dynamic>>.from(jsonDecode(expCatsString))
          : List<Map<String, dynamic>>.from(_defaultExpenseCategories);
      final localIncome = incCatsString != null
          ? List<Map<String, dynamic>>.from(jsonDecode(incCatsString))
          : List<Map<String, dynamic>>.from(_defaultIncomeCategories);

      _allExpenseCategories = mergeByName(localExpense, importedCategories);
      _allIncomeCategories = localIncome;
    });
    _saveCategories();
  }

  Future<void> _saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'group_expense_categories', jsonEncode(_allExpenseCategories));
    await prefs.setString(
        'group_income_categories', jsonEncode(_allIncomeCategories));
    final merged = <Map<String, dynamic>>[
      ..._allExpenseCategories,
      ..._allIncomeCategories,
    ];
    await prefs.setString('all_categories', jsonEncode(merged));
  }

  Future<void> _showCategoryDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
            _tabController.index == 1
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
                ..._allCategories.map((c) => _buildCategoryItem(
                    c['name'], _getCategoryIcon(c['name']?.toString() ?? ''))),
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

  Future<void> _showManageCategoriesDialog() async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: Text(
                _tabController.index == 1
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
                        children: [
                          ..._allCategories.map((c) => ListTile(
                                leading: Text(
                                    _getCategoryIcon(
                                        c['name']?.toString() ?? ''),
                                    style: const TextStyle(fontSize: 24)),
                                title: Text(c['name'],
                                    style:
                                        const TextStyle(color: Colors.white)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          color: Colors.blue),
                                      onPressed: () async {
                                        await _showEditCategoryDialog(c);
                                        setState(() {});
                                        this.setState(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          _allCategories.remove(c);
                                        });
                                        _saveCategories();
                                        this.setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        await _showAddCategoryDialog();
                        setState(() {}); // Refresh list
                        this.setState(() {}); // Refresh parent
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

  Future<void> _showEditCategoryDialog(Map<String, dynamic> category) async {
    final nameController = TextEditingController(text: category['name']);
    String selectedEmoji = _getCategoryIcon(category['name']);
    final emojiController = TextEditingController(text: selectedEmoji);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Edit Category',
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
                    category['name'] = categoryName;
                    category['icon'] = selectedEmoji;
                    _saveCategories();
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddCategoryDialog() async {
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
                    _allCategories.add({
                      'name': categoryName,
                      'icon': selectedEmoji,
                    });
                    _saveCategories();
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

  Widget _buildCategoryItem(String category, String icon) {
    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 24)),
      title: Text(
        category,
        style: const TextStyle(color: Colors.white),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      onTap: () {
        setState(() => _selectedCategory = category);
        Navigator.pop(context);
      },
      trailing: _selectedCategory == category
          ? const Icon(Icons.check, color: Color(0xFF0A84FF))
          : null,
    );
  }
}
