import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/data_provider.dart';

class PersonalInsightsView extends StatelessWidget {
  final String userId;

  const PersonalInsightsView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
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

        final transactions = dp.myPersonalTransactions;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryCards(transactions),
                const SizedBox(height: 24),
                _buildCategoryChart(transactions),
                const SizedBox(height: 24),
                _buildMonthlyChart(transactions),
                const SizedBox(height: 24),
                _buildTopCategories(transactions),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> transactions) {
    double totalIncome = 0;
    double totalExpense = 0;

    for (var t in transactions) {
      final amount = double.tryParse(t['amount'].toString()) ?? 0;
      if (t['type'] == 'income') {
        totalIncome += amount;
      } else {
        totalExpense += amount;
      }
    }

    final balance = totalIncome - totalExpense;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Income',
            totalIncome,
            Icons.trending_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Expense',
            totalExpense,
            Icons.trending_down,
            Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Balance',
            balance,
            Icons.account_balance,
            balance >= 0 ? Colors.blue : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(List<Map<String, dynamic>> transactions) {
    final expenseTransactions =
        transactions.where((t) => t['type'] == 'expense').toList();

    if (expenseTransactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, double> categoryTotals = {};
    for (var t in expenseTransactions) {
      final category = t['category'] as String;
      final amount = double.tryParse(t['amount'].toString()) ?? 0;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expense by Category',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 380;
              final chartSize = isCompact ? 180.0 : 200.0;

              return Column(
                children: [
                  SizedBox(
                    height: chartSize,
                    width: chartSize,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: isCompact ? 34 : 40,
                        sections: sortedCategories.map((entry) {
                          return PieChartSectionData(
                            color: _getCategoryColor(entry.key),
                            value: entry.value,
                            title: '',
                            radius: isCompact ? 54 : 60,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...sortedCategories.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getCategoryColor(entry.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '₹${entry.value.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart(List<Map<String, dynamic>> transactions) {
    final now = DateTime.now();
    final monthsAgo = DateTime(now.year, now.month - 5, 1);

    final Map<String, double> monthlyIncome = {};
    final Map<String, double> monthlyExpense = {};

    for (var t in transactions) {
      final date = DateTime.parse(t['date']);
      if (date.isBefore(monthsAgo)) continue;

      final monthKey = '${date.month}/${date.year}';
      final amount = double.tryParse(t['amount'].toString()) ?? 0;

      if (t['type'] == 'income') {
        monthlyIncome[monthKey] = (monthlyIncome[monthKey] ?? 0) + amount;
      } else {
        monthlyExpense[monthKey] = (monthlyExpense[monthKey] ?? 0) + amount;
      }
    }

    if (monthlyIncome.isEmpty && monthlyExpense.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monthly Trend',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'Chart visualization coming soon',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategories(List<Map<String, dynamic>> transactions) {
    final expenseTransactions =
        transactions.where((t) => t['type'] == 'expense').toList();

    if (expenseTransactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, double> categoryTotals = {};
    for (var t in expenseTransactions) {
      final category = t['category'] as String;
      final amount = double.tryParse(t['amount'].toString()) ?? 0;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topCategories = sortedCategories.take(5).toList();
    final total = categoryTotals.values.reduce((sum, amount) => sum + amount);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Spending Categories',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...topCategories.map((entry) {
            final percentage = (entry.value / total) * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹${entry.value.toStringAsFixed(2)} (${percentage.toStringAsFixed(2)}%)',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
      case 'Restaurants & Bars':
        return const Color(0xFFFFCC00);
      case 'Groceries':
        return const Color(0xFF5AC8FA);
      case 'Accommodation':
      case 'Rent & Charges':
        return const Color(0xFF007AFF);
      case 'Transport':
        return const Color(0xFF34C759);
      case 'Furniture':
        return const Color(0xFFAF52DE);
      case 'Shopping':
        return const Color(0xFFFF2D55);
      case 'Entertainment':
        return const Color(0xFF5856D6);
      case 'Other':
      default:
        return _fallbackCategoryColor(category);
    }
  }

  Color _fallbackCategoryColor(String category) {
    const palette = [
      Color(0xFF64B5F6),
      Color(0xFF81C784),
      Color(0xFFFFB74D),
      Color(0xFFBA68C8),
      Color(0xFF4DB6AC),
      Color(0xFFA1887F),
      Color(0xFFFF8A65),
      Color(0xFF90A4AE),
      Color(0xFFDCE775),
      Color(0xFFF06292),
    ];
    final key = category.trim().toLowerCase();
    final hash =
        key.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return palette[hash % palette.length];
  }
}
