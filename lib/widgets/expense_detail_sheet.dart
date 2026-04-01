import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpenseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> expense;
  final String tricountId;

  const ExpenseDetailSheet({
    super.key,
    required this.expense,
    required this.tricountId,
  });

  @override
  Widget build(BuildContext context) {
    final dateTime = DateTime.parse(expense['created_at']);
    final formattedDate = DateFormat('dd/MM/yyyy').format(dateTime);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  expense['name'] ?? 'Unnamed',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
          _buildInfoRow('Amount',
              '${(double.tryParse(expense['value']?.toString() ?? '0') ?? 0).toStringAsFixed(2)} ₹'),
          _buildInfoRow('Paid by', expense['paid_by'] ?? 'Unspecified'),
          _buildInfoRow('Category', expense['category'] ?? 'Other'),
          if (expense['payment_method'] != null)
            _buildInfoRow('Payment Method', expense['payment_method']),
          _buildInfoRow('Date', formattedDate),
          const SizedBox(height: 16),
          if (expense['photo_url'] != null) ...[
            const Text(
              'Proof',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showFullScreenImage(context, expense['photo_url']),
              child: Hero(
                tag: expense['photo_url'],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    expense['photo_url'],
                    fit: BoxFit.cover,
                    height: 200,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
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

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Hero(
              tag: imageUrl,
              child: Image.network(imageUrl),
            ),
          ),
        ),
      ),
    );
  }
}
