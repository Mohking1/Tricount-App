import 'package:flutter/material.dart';
import '../services/balance_service.dart';
import '../services/data_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/expense_detail_screen.dart';

class BalanceView extends StatefulWidget {
  final String tricountId;

  const BalanceView({super.key, required this.tricountId});

  @override
  State<BalanceView> createState() => _BalanceViewState();
}

class _BalanceViewState extends State<BalanceView> {
  bool _showSpecific = false;
  String? _specificFromId;
  String? _specificToId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final dp = DataProvider();
        final tricount = dp.tricountById(widget.tricountId);
        final participants = tricount != null
            ? List<Map<String, dynamic>>.from(tricount['participants'] ?? [])
            : <Map<String, dynamic>>[];
        final expenses = dp.expensesForTricount(widget.tricountId);

        if (dp.isLoading && participants.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final balances =
            BalanceService.calculateBalancesFromData(participants, expenses);
        final payments = BalanceService.calculatePayments(balances);
        final specificDebts =
            BalanceService.getSpecificDebtsFromData(participants, expenses);
        final currentUser = Supabase.instance.client.auth.currentUser;

        return _buildPaymentsList(
            payments, specificDebts, currentUser, participants);
      },
    );
  }

  Widget _buildPaymentsList(
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> specificDebts,
    User? currentUser,
    List<Map<String, dynamic>> participants,
  ) {
    final filteredSpecificDebts = specificDebts.where((debt) {
      final matchesFrom =
          _specificFromId == null || debt['from_id'] == _specificFromId;
      final matchesTo = _specificToId == null || debt['to_id'] == _specificToId;
      return matchesFrom && matchesTo;
    }).toList();

    final specificDebtors = participants
        .where((p) => (p['id']?.toString().isNotEmpty ?? false))
        .toList();

    final specificCreditors = participants
        .where((p) => (p['id']?.toString().isNotEmpty ?? false))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Simplified', style: TextStyle(color: Colors.white)),
              Switch(
                value: _showSpecific,
                onChanged: (val) => setState(() {
                  _showSpecific = val;
                  if (!val) {
                    _specificFromId = null;
                    _specificToId = null;
                  }
                }),
                activeTrackColor: const Color(0xFF0A84FF),
              ),
              const Text('Specific', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        if (_showSpecific)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Debtor',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _specificFromId,
                            isDense: true,
                            dropdownColor: const Color(0xFF2C2C2E),
                            style: const TextStyle(color: Colors.white),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Anyone owes',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              ...specificDebtors
                                  .map((p) => DropdownMenuItem<String?>(
                                        value: p['id']?.toString(),
                                        child: Text(
                                          p['name']?.toString() ?? 'Unknown',
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                            ],
                            onChanged: (val) {
                              setState(() => _specificFromId = val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Creditor',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _specificToId,
                            isDense: true,
                            dropdownColor: const Color(0xFF2C2C2E),
                            style: const TextStyle(color: Colors.white),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Anyone is owed',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              ...specificCreditors
                                  .map((p) => DropdownMenuItem<String?>(
                                        value: p['id']?.toString(),
                                        child: Text(
                                          p['name']?.toString() ?? 'Unknown',
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                            ],
                            onChanged: (val) {
                              setState(() => _specificToId = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _specificFromId = null;
                        _specificToId = null;
                      });
                    },
                    child: const Text('Clear filters'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _showSpecific
              ? (filteredSpecificDebts.isEmpty
                  ? const Center(child: Text('No debts found'))
                  : ListView.builder(
                      itemCount: filteredSpecificDebts.length,
                      itemBuilder: (context, index) {
                        final debt = filteredSpecificDebts[index];
                        final amount =
                            double.tryParse(debt['amount'].toString()) ?? 0;
                        final currentUserName =
                            currentUser?.userMetadata?['name'];
                        final isCurrentUserDebtor = (debt['from_id'] != null &&
                                currentUser?.id == debt['from_id']) ||
                            (debt['from'] == currentUserName);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: InkWell(
                            onTap: () => _openExpenseFromDebt(context, debt),
                            onLongPress: isCurrentUserDebtor
                                ? () {
                                    if (debt['to_id'] != null &&
                                        currentUser != null) {
                                      _showSettleUpDialog(
                                        context,
                                        debt['to'],
                                        debt['to_id'],
                                        amount,
                                        currentUser.id,
                                        currentUserName ?? 'Me',
                                      );
                                    }
                                  }
                                : null,
                            child: ListTile(
                              title: Text(
                                  '${debt['from']} owes ${debt['to']} ${amount.toStringAsFixed(2)} ₹',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2),
                              subtitle: Text('For: ${debt['expense_name']}',
                                  overflow: TextOverflow.ellipsis, maxLines: 1),
                              trailing: const Icon(Icons.open_in_new),
                            ),
                          ),
                        );
                      },
                    ))
              : (payments.isEmpty
                  ? const Center(child: Text('No reimbursement needed'))
                  : ListView.builder(
                      itemCount: payments.length,
                      itemBuilder: (context, index) {
                        final payment = payments[index];
                        final currentUserName =
                            currentUser?.userMetadata?['name'];
                        final isCurrentUserPaying =
                            payment['from'] == currentUserName;
                        final isCurrentUserReceiving =
                            payment['to'] == currentUserName;

                        String message;
                        if (isCurrentUserPaying) {
                          message =
                              'You must pay ${payment['amount'].toStringAsFixed(2)} ₹ to ${payment['to']}';
                        } else if (isCurrentUserReceiving) {
                          message =
                              '${payment['from']} must pay you ${payment['amount'].toStringAsFixed(2)} ₹';
                        } else {
                          message =
                              '${payment['from']} must pay ${payment['amount'].toStringAsFixed(2)} ₹ to ${payment['to']}';
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: InkWell(
                            onTap: isCurrentUserPaying
                                ? () {
                                    final toName = payment['to'];
                                    final toParticipant =
                                        participants.firstWhere(
                                      (p) => p['name'] == toName,
                                      orElse: () => {},
                                    );
                                    final toId = toParticipant['id'];

                                    if (toId != null && currentUser != null) {
                                      _showSettleUpDialog(
                                        context,
                                        toName,
                                        toId,
                                        payment['amount'],
                                        currentUser.id,
                                        currentUserName ?? 'Me',
                                      );
                                    }
                                  }
                                : null,
                            child: ListTile(
                              leading: const Icon(Icons.payment),
                              title: Text(
                                message,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              trailing: isCurrentUserPaying
                                  ? const Icon(Icons.chevron_right)
                                  : null,
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  void _openExpenseFromDebt(BuildContext context, Map<String, dynamic> debt) {
    final expenseId = debt['expense_id']?.toString();
    if (expenseId == null || expenseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense link is unavailable')),
      );
      return;
    }

    final expense = DataProvider()
        .expensesForTricount(widget.tricountId)
        .where((e) => e['id']?.toString() == expenseId)
        .cast<Map<String, dynamic>>()
        .toList();

    if (expense.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense not found')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpenseDetailScreen(
          expense: expense.first,
          tricountId: widget.tricountId,
        ),
      ),
    );
  }

  Future<void> _showSettleUpDialog(
      BuildContext context,
      String toName,
      String toId,
      double amount,
      String currentUserId,
      String currentUserName) async {
    String paymentMethod = 'Online';
    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Mark as Paid'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('You are paying $toName'),
                const SizedBox(height: 16),
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payment Method:'),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Cash'),
                          Switch(
                            value: paymentMethod == 'Online',
                            onChanged: (val) {
                              setState(() {
                                paymentMethod = val ? 'Online' : 'Cash';
                              });
                            },
                            activeTrackColor: const Color(0xFF0A84FF),
                          ),
                          const Text('Online'),
                        ],
                      ),
                    ),
                  ],
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  // Create Expense
                  await Supabase.instance.client.from('expenses').insert({
                    'name': 'Payment to $toName',
                    'value': amount,
                    'paid_by': currentUserName, // Name
                    'user_id': currentUserId, // ID
                    'tricount_id': widget.tricountId,
                    'category': 'Transfer',
                    'payment_method': paymentMethod,
                    'created_at': selectedDate.toIso8601String(),
                    'involved_participants': [
                      {'user_id': toId, 'amount': amount, 'weight': 1}
                    ]
                  });

                  // Add to personal tracker as expense
                  try {
                    await Supabase.instance.client
                        .from('personal_transactions')
                        .insert({
                      'user_id': currentUserId,
                      'name': 'Settlement payment to $toName',
                      'amount': amount,
                      'type': 'expense',
                      'payment_mode': paymentMethod.toLowerCase(),
                      'category': 'Transfer',
                      'date': selectedDate.toIso8601String(),
                      'notes': 'Debt settlement',
                    });
                  } catch (e) {
                    debugPrint(
                        'Error syncing settlement to personal tracker: $e');
                  }

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        });
      },
    );
  }
}
