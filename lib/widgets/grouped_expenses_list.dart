import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/expense_detail_screen.dart';
import '../utils/category_icon_utils.dart';

class GroupedExpensesList extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;
  final String tricountId;

  const GroupedExpensesList({
    super.key,
    required this.expenses,
    required this.tricountId,
  });

  String _getCategoryEmoji(String? category) {
    return categoryIconForName(category);
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Map<String, List<Map<String, dynamic>>> _groupExpensesByDate() {
    final groupedExpenses = <String, List<Map<String, dynamic>>>{};

    for (var expense in expenses) {
      final createdAtStr = expense['created_at'] as String?;

      if (createdAtStr != null) {
        final date = DateTime.parse(createdAtStr);
        final dateString = _formatDate(date);

        groupedExpenses.putIfAbsent(dateString, () => []);
        groupedExpenses[dateString]!.add(expense);
      }
    }

    return groupedExpenses;
  }

  @override
  Widget build(BuildContext context) {
    final groupedExpenses = _groupExpensesByDate();
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groupedExpenses.length,
      itemBuilder: (context, index) {
        final dateString = groupedExpenses.keys.elementAt(index);
        final dayExpenses = groupedExpenses[dateString]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                dateString,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...dayExpenses.map((expense) {
              bool isPaid = false;
              bool isPartiallyPaid = false;

              if (currentUserId != null) {
                if (expense['user_id'] == currentUserId) {
                  isPaid = true;
                }
                final involved = expense['involved_participants'];
                if (!isPaid && involved is List) {
                  for (var item in involved) {
                    if (item is Map) {
                      final uid = item['user_id'] ?? item['id'];
                      if (uid == currentUserId) {
                        final amount =
                            double.tryParse(item['amount'].toString()) ?? 0;
                        final paid = double.tryParse(
                                item['paid_amount']?.toString() ?? '0') ??
                            0;
                        if (amount > 0) {
                          if (paid >= amount - 0.01) {
                            isPaid = true;
                          } else if (paid > 0) {
                            isPartiallyPaid = true;
                          }
                        }
                      }
                    }
                  }
                }
              }

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _getCategoryEmoji(expense['category']),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                title: Text(
                  expense['name'] ?? 'Unnamed',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          const TextSpan(text: 'Paid by: '),
                          TextSpan(
                            text: expense['paid_by'] ?? 'Unspecified',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (expense['category'] != null) ...[
                            const TextSpan(text: ' • '),
                            TextSpan(
                              text: expense['category'],
                              style:
                                  const TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isPaid)
                      const Text(
                        'You paid your share',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      )
                    else if (isPartiallyPaid)
                      const Text(
                        'Partially paid',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                  ],
                ),
                trailing: Text(
                  '${(double.tryParse(expense['value']?.toString() ?? '0') ?? 0).toStringAsFixed(2)} ₹',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExpenseDetailScreen(
                        expense: expense,
                        tricountId: tricountId,
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }
}
