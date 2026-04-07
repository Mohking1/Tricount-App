import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'add_expense_screen.dart';
import '../services/sync_service.dart';
import '../utils/category_icon_utils.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final Map<String, dynamic> expense;
  final String tricountId;

  const ExpenseDetailScreen({
    super.key,
    required this.expense,
    required this.tricountId,
  });

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  List<Map<String, dynamic>> _participants = [];
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _fetchParticipants();
  }

  Future<void> _fetchParticipants() async {
    try {
      // Fetch Tricount participants to map IDs to Names/Photos
      final tricountRes = await Supabase.instance.client
          .from('tricounts')
          .select('participants')
          .eq('id', widget.tricountId)
          .single();

      final List<dynamic> allParticipants = tricountRes['participants'] ?? [];

      // Parse involved_participants from expense
      // It can be a list of strings (IDs) or list of objects {user_id, amount}
      final involvedData = widget.expense['involved_participants'];
      List<Map<String, dynamic>> involvedList = [];

      if (involvedData is List) {
        for (var item in involvedData) {
          if (item is Map) {
            // New: List of objects {user_id, amount}
            final userId =
                item['user_id'] ?? item['id']; // Handle both just in case
            final amount = double.tryParse(item['amount'].toString()) ?? 0;

            final p = allParticipants.firstWhere(
              (p) => p['id'] == userId,
              orElse: () => {'id': userId, 'name': 'Unknown'},
            );

            involvedList.add({
              ...p,
              'amount': amount,
              'paid_amount': item['paid_amount'],
              'payment_method': item['payment_method'],
              'payment_date': item['payment_date'],
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _participants = involvedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching participants: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this expense?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteExpense();
    }
  }

  Future<void> _markAsPaidForParticipant(
      String participantId, double amountToPay) async {
    if (participantId.isEmpty) return;

    // Show payment method and date dialog
    String paymentMethod = 'Online';
    DateTime selectedDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Mark as Paid'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹${amountToPay.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text('Payment Method:',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => paymentMethod = 'Cash'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: paymentMethod == 'Cash'
                                  ? const Color(0xFF30D158)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text('Cash',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => paymentMethod = 'Online'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: paymentMethod == 'Online'
                                  ? const Color(0xFF0A84FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text('Online',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Date:'),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
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
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: Text(
                        "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                        style: const TextStyle(color: Color(0xFF0A84FF)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          );
        });
      },
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final involvedData =
          List<dynamic>.from(widget.expense['involved_participants'] ?? []);
      bool updated = false;

      final updatedInvolved = involvedData.map((item) {
        if (item is Map) {
          final userId = item['user_id'] ?? item['id'];
          if (userId == participantId) {
            final currentPaid =
                double.tryParse(item['paid_amount']?.toString() ?? '0') ?? 0;
            final newPaid = currentPaid + amountToPay;
            updated = true;
            return {
              ...item,
              'paid_amount': newPaid,
              'payment_method': paymentMethod,
              'payment_date': selectedDate.toIso8601String(),
            };
          }
        }
        return item;
      }).toList();

      if (updated) {
        final updateData = {'involved_participants': updatedInvolved};
        await SyncService().updateExpense(widget.expense['id'], updateData);

        // Update local widget state
        widget.expense['involved_participants'] = updatedInvolved;
        _hasChanges = true;
        await _fetchParticipants();

        // Add to personal tracker as income for the expense payer
        await _addPaymentToPersonalTracker(
          amountToPay,
          paymentMethod,
          selectedDate,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment marked successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating payment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPaymentToPersonalTracker(
      double amount, String paymentMethod, DateTime date) async {
    try {
      final payerId = widget.expense['user_id'];
      final currentUser = Supabase.instance.client.auth.currentUser;

      // Only add income if current user is the one who paid the original expense
      if (currentUser == null || payerId != currentUser.id) return;

      await Supabase.instance.client.from('personal_transactions').insert({
        'user_id': currentUser.id,
        'name': 'Payment received - ${widget.expense['name']}',
        'amount': amount,
        'type': 'income',
        'payment_mode': paymentMethod.toLowerCase(),
        'category': 'Reimbursement',
        'date': date.toIso8601String(),
        'notes': 'Received payment for group expense',
      });
    } catch (e) {
      debugPrint('Error adding payment to personal tracker: $e');
    }
  }

  Widget _buildMyStatus(String currentUserId) {
    final myEntry = _participants.firstWhere(
      (p) => p['id'] == currentUserId,
      orElse: () => {},
    );

    if (myEntry.isEmpty) return const SizedBox.shrink();

    final amount = double.tryParse(myEntry['amount'].toString()) ?? 0;
    // We need to get paid_amount from the raw expense data because _participants might not have it if we didn't map it
    // Actually _fetchParticipants maps it? Let's check.
    // _fetchParticipants maps: involvedList.add({ ...p, 'amount': amount });
    // It does NOT map 'paid_amount'. I should fix _fetchParticipants too.
    // But I can get it from widget.expense['involved_participants'] directly.

    final rawInvolved = widget.expense['involved_participants'] as List;
    final myRaw = rawInvolved.firstWhere(
        (e) => (e['user_id'] ?? e['id']) == currentUserId,
        orElse: () => {});
    final paid = double.tryParse(myRaw['paid_amount']?.toString() ?? '0') ?? 0;
    final remaining = amount - paid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Share',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: remaining <= 0.01 ? Colors.green : Colors.red),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Share:',
                        style: TextStyle(color: Colors.grey)),
                    Text('₹${amount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Paid:', style: TextStyle(color: Colors.grey)),
                    Text('₹${paid.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.green)),
                  ],
                ),
                const Divider(color: Colors.grey),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Remaining:',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('₹${remaining.toStringAsFixed(2)}',
                        style: TextStyle(
                            color:
                                remaining <= 0.01 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                if (remaining > 0.01) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _markAsPaidForParticipant(
                              currentUserId, remaining),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Pay'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _markAsPaidForParticipant(
                              currentUserId, remaining),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                          ),
                          child: const Text('Mark Paid'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('You have paid your share',
                          style: TextStyle(color: Colors.green)),
                    ],
                  )
                ]
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _deleteExpense() async {
    try {
      await SyncService().deleteExpense(widget.expense['id']);

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate change
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting expense: $e')),
        );
      }
    }
  }

  Future<void> _editExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          tricountId: widget.tricountId,
          expense: widget.expense,
        ),
      ),
    );

    if (result == true) {
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateTime = DateTime.parse(widget.expense['created_at']);
    final formattedDate = DateFormat('EEEE d MMMM, yyyy').format(dateTime);
    final amount = double.tryParse(widget.expense['value'].toString()) ?? 0;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Find payer details
    // We need to fetch payer details from tricount participants list too,
    // but we don't have the full list here unless we fetch it or pass it.
    // For now, let's use the 'paid_by' name stored in expense or try to find in _participants if they are involved.
    // Ideally we should fetch the payer profile.

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _hasChanges),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit') {
                _editExpense();
              } else if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Category Icon
                  Text(
                    _getCategoryIcon(widget.expense['category']),
                    style: const TextStyle(fontSize: 64),
                  ),
                  const SizedBox(height: 16),
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      widget.expense['name'] ?? 'Unnamed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Date
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Paid By Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paid By',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.grey[800],
                                child: const Icon(Icons.person,
                                    color: Colors.white),
                                // TODO: Show actual avatar
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.expense['paid_by'] ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    if (widget.expense['user_id'] ==
                                        currentUserId)
                                      Text(
                                        'Me',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(
                                      0xFFFF9F0A), // Orange color from screenshot
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  if (currentUserId != null &&
                      widget.expense['user_id'] != currentUserId)
                    _buildMyStatus(currentUserId),

                  // Participants Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Participants',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Long press a participant to mark their share as paid',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children:
                                _participants.asMap().entries.map((entry) {
                              final index = entry.key;
                              final p = entry.value;
                              final isLast = index == _participants.length - 1;
                              final participantId =
                                  (p['id'] ?? p['user_id'])?.toString() ?? '';
                              final participantAmount =
                                  double.tryParse(p['amount'].toString()) ?? 0;
                              final participantPaid = double.tryParse(
                                      p['paid_amount']?.toString() ?? '0') ??
                                  0;
                              final participantRemaining =
                                  participantAmount - participantPaid;
                              final payerId =
                                  widget.expense['user_id']?.toString() ?? '';
                              final canMarkForRow = participantId.isNotEmpty &&
                                  participantRemaining > 0.01 &&
                                  participantId != payerId;

                              return Column(
                                children: [
                                  GestureDetector(
                                    onLongPress: canMarkForRow
                                        ? () => _markAsPaidForParticipant(
                                              participantId,
                                              participantRemaining,
                                            )
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: Colors.grey[800],
                                            backgroundImage: p['photo_url'] !=
                                                    null
                                                ? NetworkImage(p['photo_url'])
                                                : null,
                                            child: p['photo_url'] == null
                                                ? const Icon(Icons.person,
                                                    color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p['name'] ?? 'Unknown',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                                if (p['id'] == currentUserId)
                                                  Text(
                                                    'Me',
                                                    style: TextStyle(
                                                      color: Colors.grey[400],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                _buildPaymentStatus(p),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '₹${participantAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      color: Colors.grey[800],
                                      indent: 16,
                                      endIndent: 16,
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildPaymentStatus(Map<String, dynamic> participant) {
    final amount = double.tryParse(participant['amount'].toString()) ?? 0;
    final paidAmount =
        double.tryParse(participant['paid_amount']?.toString() ?? '0') ?? 0;
    final paymentMethod = participant['payment_method'];
    final paymentDate = participant['payment_date'];

    if (paidAmount <= 0) return const SizedBox.shrink();

    final isPaid = paidAmount >= amount - 0.01;

    String statusText =
        isPaid ? 'Paid' : 'Paid ₹${paidAmount.toStringAsFixed(2)}';
    Color statusColor = isPaid ? Colors.green : Colors.orange;

    List<String> details = [];
    if (paymentMethod != null) {
      details.add(paymentMethod);
    }
    if (paymentDate != null) {
      try {
        final date = DateTime.parse(paymentDate);
        details.add(DateFormat('dd/MM/yyyy').format(date));
      } catch (e) {
        // Invalid date format
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (details.isNotEmpty)
          Text(
            details.join(' • '),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
    );
  }

  String _getCategoryIcon(String? categoryName) {
    return categoryIconForName(categoryName);
  }
}
