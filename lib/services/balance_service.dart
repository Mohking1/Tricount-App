class BalanceService {
  static Map<String, double> calculateBalancesFromData(
      List<Map<String, dynamic>> participants, List<dynamic> expenses) {
    // Map ID to Name for easy lookup
    final Map<String, String> idToName = {};
    final Map<String, double> balances = {};

    for (var p in participants) {
      final name = p['name'] as String;
      final id = p['id'] as String;
      idToName[id] = name;
      balances[name] = 0.0;
    }

    for (var expense in expenses) {
      final double amount = double.tryParse(expense['value'].toString()) ?? 0;
      final String? payerId = expense['user_id'];
      final String payerName = expense['paid_by'] ?? 'Unknown';

      // 1. Credit the payer
      // Use ID if possible to find name, else use stored name
      String creditorName = payerName;
      if (payerId != null && idToName.containsKey(payerId)) {
        creditorName = idToName[payerId]!;
      }

      // If the payer is not in our participants list (e.g. left group), add them?
      // Or just use the name.
      if (!balances.containsKey(creditorName)) {
        balances[creditorName] = 0.0;
      }
      balances[creditorName] = balances[creditorName]! + amount;

      // 2. Debit the consumers
      final involved = expense['involved_participants'];

      if (involved is List && involved.isNotEmpty) {
        // New: List of Objects (Unequal/Equal with amounts)
        for (var item in involved) {
          if (item is Map) {
            final userId = item['user_id'] ?? item['id'];
            final userAmount = double.tryParse(item['amount'].toString()) ?? 0;
            final paidAmount =
                double.tryParse(item['paid_amount']?.toString() ?? '0') ?? 0;

            String debtorName = idToName[userId] ?? 'Unknown';

            if (!balances.containsKey(debtorName) && debtorName != 'Unknown') {
              balances[debtorName] = 0.0;
            }

            if (debtorName != 'Unknown') {
              balances[debtorName] =
                  balances[debtorName]! - userAmount + paidAmount;
            }

            // Reduce creditor's balance by the amount they have been paid back
            if (balances.containsKey(creditorName)) {
              balances[creditorName] = balances[creditorName]! - paidAmount;
            }
          }
        }
      } else {
        // Fallback: If involved_participants is empty or null, assume equal split among ALL participants
        // This matches the old behavior for legacy data that might lack this field
        if (participants.isNotEmpty) {
          final splitAmount = amount / participants.length;
          for (var name in balances.keys) {
            balances[name] = balances[name]! - splitAmount;
          }
        }
      }
    }

    return balances;
  }

  static List<Map<String, dynamic>> calculatePayments(
      Map<String, double> balances) {
    List<Map<String, dynamic>> payments = [];

    // Create two lists: debtors and creditors
    var debtors = balances.entries
        .where((e) => e.value < 0)
        .map((e) => {
              'name': e.key,
              'amount': e.value.abs(),
            })
        .toList();
    var creditors = balances.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'name': e.key,
              'amount': e.value,
            })
        .toList();

    // Sort by amount descending
    debtors.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    creditors.sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    while (debtors.isNotEmpty && creditors.isNotEmpty) {
      var debtor = debtors[0];
      var creditor = creditors[0];

      // Calculate payment amount
      double paymentAmount =
          (debtor['amount'] as double) < (creditor['amount'] as double)
              ? (debtor['amount'] as double)
              : (creditor['amount'] as double);

      payments.add({
        'from': debtor['name'],
        'to': creditor['name'],
        'amount': paymentAmount,
      });

      // Update amounts
      debtor['amount'] = (debtor['amount'] as double) - paymentAmount;
      creditor['amount'] = (creditor['amount'] as double) - paymentAmount;

      // Remove people who settled their account
      final debtorAmount = debtor['amount'] as double;
      final creditorAmount = creditor['amount'] as double;

      if (debtorAmount.abs() < 0.01) debtors.removeAt(0);
      if (creditorAmount.abs() < 0.01) creditors.removeAt(0);
    }

    return payments;
  }

  static List<Map<String, dynamic>> getSpecificDebtsFromData(
      List<Map<String, dynamic>> participants, List<dynamic> expenses) {
    final Map<String, String> idToName = {};
    for (var p in participants) {
      idToName[p['id']] = p['name'];
    }

    List<Map<String, dynamic>> debts = [];

    for (var expense in expenses) {
      final String? payerId = expense['user_id'];
      final String payerName = expense['paid_by'] ?? 'Unknown';
      final involved = expense['involved_participants'];

      if (involved is List) {
        for (var item in involved) {
          if (item is Map) {
            final userId = item['user_id'] ?? item['id'];
            if (userId == payerId) continue; // Don't owe yourself

            final userAmount = double.tryParse(item['amount'].toString()) ?? 0;
            final paidAmount =
                double.tryParse(item['paid_amount']?.toString() ?? '0') ?? 0;
            final remaining = userAmount - paidAmount;

            if (remaining > 0.01) {
              debts.add({
                'from': idToName[userId] ?? 'Unknown',
                'from_id': userId,
                'to': payerName,
                'to_id': payerId,
                'amount': remaining,
                'expense_name': expense['name'],
                'date': expense['created_at'],
              });
            }
          }
        }
      }
    }

    return debts;
  }
}
