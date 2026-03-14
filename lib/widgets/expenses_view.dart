import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'grouped_expenses_list.dart';
import '../services/data_provider.dart';

class ExpensesView extends StatefulWidget {
  final String tricountId;

  const ExpensesView({super.key, required this.tricountId});

  @override
  State<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends State<ExpensesView> {
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedPayer;
  String _paymentStatus = 'All'; // 'All', 'Unpaid', 'Partially Paid', 'Paid'

  void _showFilterBottomSheet(List<String> categories, List<String> payers) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filters',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 16),
                  // Category
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedCategory,
                        dropdownColor: const Color(0xFF2C2C2E),
                        style: const TextStyle(color: Colors.white),
                        isDense: true,
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('All Categories',
                                  style: TextStyle(color: Colors.white))),
                          ...categories.map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  style:
                                      const TextStyle(color: Colors.white)))),
                        ],
                        onChanged: (val) =>
                            setModalState(() => _selectedCategory = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Paid By
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Paid By',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedPayer,
                        dropdownColor: const Color(0xFF2C2C2E),
                        style: const TextStyle(color: Colors.white),
                        isDense: true,
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('Anyone',
                                  style: TextStyle(color: Colors.white))),
                          ...payers.map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p,
                                  style:
                                      const TextStyle(color: Colors.white)))),
                        ],
                        onChanged: (val) =>
                            setModalState(() => _selectedPayer = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Status
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'My Status',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _paymentStatus,
                        dropdownColor: const Color(0xFF2C2C2E),
                        style: const TextStyle(color: Colors.white),
                        isDense: true,
                        items: ['All', 'Unpaid', 'Partially Paid', 'Paid']
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s,
                                    style:
                                        const TextStyle(color: Colors.white))))
                            .toList(),
                        onChanged: (val) =>
                            setModalState(() => _paymentStatus = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {}); // Update main view
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Apply Filters'),
                    ),
                  ),
                  const SizedBox(height: 16),
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
    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final allExpenses =
            DataProvider().expensesForTricount(widget.tricountId);

        if (DataProvider().isLoading && allExpenses.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (allExpenses.isEmpty) {
          return const Center(child: Text('No expenses'));
        }

        // Extract unique categories for filter
        final categories = allExpenses
            .map((e) => e['category'] as String?)
            .where((c) => c != null)
            .toSet()
            .toList();
        categories.sort();

        // Extract unique payers
        final payers = allExpenses
            .map((e) => e['paid_by'] as String?)
            .where((p) => p != null)
            .toSet()
            .toList();
        payers.sort();

        final currentUserId = Supabase.instance.client.auth.currentUser?.id;

        // Filter expenses
        final expenses = allExpenses.where((expense) {
          final name = (expense['name'] as String? ?? '').toLowerCase();
          final category = expense['category'] as String?;
          final paidBy = expense['paid_by'] as String?;

          final matchesSearch = name.contains(_searchQuery.toLowerCase());
          final matchesCategory =
              _selectedCategory == null || category == _selectedCategory;
          final matchesPayer =
              _selectedPayer == null || paidBy == _selectedPayer;

          bool matchesStatus = true;
          if (_paymentStatus != 'All') {
            if (currentUserId != null) {
              // Check my status in this expense
              final involved = expense['involved_participants'];
              double myAmount = 0;
              double myPaid = 0;

              if (involved is List) {
                for (var item in involved) {
                  if (item is Map) {
                    final uid = item['user_id'] ?? item['id'];
                    if (uid == currentUserId) {
                      myAmount =
                          double.tryParse(item['amount'].toString()) ?? 0;
                      myPaid = double.tryParse(
                              item['paid_amount']?.toString() ?? '0') ??
                          0;
                      break;
                    }
                  }
                }
              }

              if (myAmount == 0) {
                // Not involved
                matchesStatus = false;
              } else {
                if (_paymentStatus == 'Paid') {
                  matchesStatus = myPaid >= myAmount - 0.01;
                } else if (_paymentStatus == 'Unpaid') {
                  matchesStatus = myPaid <= 0.01;
                } else if (_paymentStatus == 'Partially Paid') {
                  matchesStatus = myPaid > 0.01 && myPaid < myAmount - 0.01;
                }
              }
            }
          }

          return matchesSearch &&
              matchesCategory &&
              matchesPayer &&
              matchesStatus;
        }).toList();

        // Calculate totals (based on filtered list or all list? Usually all list for summary, but maybe filtered for context.
        // Let's keep totals for ALL expenses to avoid confusion, or maybe show both.
        // Standard behavior is usually totals for the view. Let's do totals for the view.)

        // Actually, usually the top summary is "My Balance" / "Total" for the whole tricount.
        // If I filter, I probably just want to find a transaction.
        // Let's keep the totals based on ALL expenses so the user always knows their standing.

        // final currentUserId = Supabase.instance.client.auth.currentUser?.id; // Already defined above
        double totalExpenses = 0;
        double myExpenses = 0;
        for (var expense in allExpenses) {
          final value = double.tryParse(expense['value'].toString()) ?? 0;
          totalExpenses += value;
          if (expense['user_id'] == currentUserId) {
            myExpenses += value;
          }
        }

        return Column(
          children: [
            // Search and Filter Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search expenses...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.filter_list,
                        color: (_selectedCategory != null ||
                                _selectedPayer != null ||
                                _paymentStatus != 'All')
                            ? const Color(0xFF0A84FF)
                            : Colors.white),
                    onPressed: () => _showFilterBottomSheet(
                        categories.whereType<String>().toList(),
                        payers.whereType<String>().toList()),
                  ),
                ],
              ),
            ),

            // Totals Summary
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('My Expenses',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          '${myExpenses.toStringAsFixed(2)} ₹',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[300]),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Total Expenses',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${totalExpenses.toStringAsFixed(2)} ₹',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await DataProvider()
                      .refreshTricountExpenses(widget.tricountId);
                },
                child: expenses.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 100),
                          Center(child: Text('No matching expenses')),
                        ],
                      )
                    : GroupedExpensesList(
                        expenses: expenses,
                        tricountId: widget.tricountId,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
