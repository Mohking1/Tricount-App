import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'add_personal_transaction_screen.dart';
import '../widgets/personal_insights_view.dart';
import '../services/data_provider.dart';

class PersonalTrackerScreen extends StatefulWidget {
  const PersonalTrackerScreen({super.key});

  @override
  State<PersonalTrackerScreen> createState() => _PersonalTrackerScreenState();
}

class _PersonalTrackerScreenState extends State<PersonalTrackerScreen> {
  int _selectedTab = 0;
  String _filterType = 'All'; // All, Income, Expense
  String? _selectedCategory;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Personal Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: Column(
          children: [
            _buildBalanceCard(currentUser.id),
            _buildTabBar(),
            Expanded(
              child: _selectedTab == 0
                  ? _buildTransactionsList(currentUser.id)
                  : PersonalInsightsView(userId: currentUser.id),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddPersonalTransactionScreen(),
            ),
          );
          if (result == true && mounted) {
            setState(() {});
          }
        },
        backgroundColor: const Color(0xFF0A84FF),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBalanceCard(String userId) {
    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final balanceData = DataProvider().myPersonalBalance;
        final cashBalance = balanceData != null
            ? (double.tryParse(
                    balanceData['cash_balance']?.toString() ?? '0') ??
                0.0)
            : 0.0;
        final onlineBalance = balanceData != null
            ? (double.tryParse(
                    balanceData['online_balance']?.toString() ?? '0') ??
                0.0)
            : 0.0;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '₹${(cashBalance + onlineBalance).toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildBalanceItem(
                      'Cash',
                      cashBalance,
                      Icons.money,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBalanceItem(
                      'Online',
                      onlineBalance,
                      Icons.credit_card,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBalanceItem(String title, double balance, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 0
                      ? const Color(0xFF0A84FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Transactions',
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
              onTap: () => setState(() => _selectedTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 1
                      ? const Color(0xFF0A84FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Insights',
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
    );
  }

  Widget _buildTransactionsList(String userId) {
    return ListenableBuilder(
      listenable: DataProvider(),
      builder: (context, _) {
        final dp = DataProvider();

        if (dp.isLoading && dp.myPersonalTransactions.isEmpty) {
          return Container(
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        var transactions =
            List<Map<String, dynamic>>.from(dp.myPersonalTransactions);

        // Apply filters
        if (_filterType != 'All') {
          transactions = transactions
              .where((t) =>
                  t['type'].toString().toLowerCase() ==
                  _filterType.toLowerCase())
              .toList();
        }

        if (_selectedCategory != null) {
          transactions = transactions
              .where((t) => t['category'] == _selectedCategory)
              .toList();
        }

        if (_startDate != null) {
          transactions = transactions.where((t) {
            final date = DateTime.parse(t['date']);
            return date.isAfter(_startDate!.subtract(const Duration(days: 1)));
          }).toList();
        }

        if (_endDate != null) {
          transactions = transactions.where((t) {
            final date = DateTime.parse(t['date']);
            return date.isBefore(_endDate!.add(const Duration(days: 1)));
          }).toList();
        }

        if (transactions.isEmpty) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: Text('No transactions yet'),
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: RefreshIndicator(
            onRefresh: () async {
              await DataProvider().refreshPersonal();
            },
            child: ListView.builder(
              itemCount: transactions.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return _buildTransactionCard(transaction);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final isIncome = transaction['type'] == 'income';
    final date = DateTime.parse(transaction['date']);
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(date);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isIncome
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: isIncome ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          transaction['name'] ?? 'Unnamed',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  transaction['payment_mode'] == 'cash'
                      ? Icons.money
                      : Icons.credit_card,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${transaction['payment_mode']} • ${transaction['category']}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formattedDate,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: Text(
          '${isIncome ? '+' : '-'}₹${(double.tryParse(transaction['amount']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}',
          style: TextStyle(
            color: isIncome ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        onTap: () => _showTransactionDetails(transaction),
      ),
    );
  }

  void _showFilterDialog() {
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
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _filterType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      labelStyle: TextStyle(color: Colors.grey),
                    ),
                    dropdownColor: const Color(0xFF2C2C2E),
                    items: ['All', 'Income', 'Expense']
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type,
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setModalState(() => _filterType = val!);
                      setState(() => _filterType = val!);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _filterType = 'All';
                              _selectedCategory = null;
                              _startDate = null;
                              _endDate = null;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final isIncome = transaction['type'] == 'income';
        final date = DateTime.parse(transaction['date']);
        final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(date);

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      transaction['name'] ?? 'Unnamed',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow(
                  'Amount',
                  '₹${(double.tryParse(transaction['amount']?.toString() ?? '0') ?? 0).toStringAsFixed(2)}',
                  isIncome ? Colors.green : Colors.red),
              _buildDetailRow('Type', isIncome ? 'Income' : 'Expense', null),
              _buildDetailRow(
                  'Payment Mode', transaction['payment_mode'], null),
              _buildDetailRow('Category', transaction['category'], null),
              _buildDetailRow('Date', formattedDate, null),
              if (transaction['notes'] != null)
                _buildDetailRow('Notes', transaction['notes'], null),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteTransaction(transaction['id']);
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Delete',
                          style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(String transactionId) async {
    try {
      await Supabase.instance.client
          .from('personal_transactions')
          .delete()
          .eq('id', transactionId);

      if (mounted) {
        DataProvider().refreshPersonal();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction deleted'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting transaction: $e')),
        );
      }
    }
  }
}
