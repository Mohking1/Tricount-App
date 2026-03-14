import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/data_provider.dart';

class InsightsView extends StatefulWidget {
  final String tricountId;

  const InsightsView({super.key, required this.tricountId});

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  // Filters
  String _timeFilter = 'All'; // 'Month', 'Year', 'All'
  String _scopeFilter = 'For the Group'; // 'For Me', 'For the Group'
  DateTime _selectedDate = DateTime.now();
  int _touchedIndex = -1;
  List<Map<String, dynamic>> _allCategories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final String? allCatsString = prefs.getString('all_categories');
    if (allCatsString != null) {
      setState(() {
        _allCategories =
            List<Map<String, dynamic>>.from(jsonDecode(allCatsString));
      });
    }
  }

  Map<String, dynamic> _processData(List<Map<String, dynamic>> allExpenses) {
    final Map<String, double> categoryTotals = {};
    double totalAmount = 0;

    final currentUser = Supabase.instance.client.auth.currentUser;

    for (var expense in allExpenses) {
      final DateTime date = DateTime.parse(expense['created_at']);
      final double amount = (expense['value'] as num).toDouble();
      final String category = expense['category'] ?? 'Other';

      // 1. Time Filter
      bool matchesTime = true;
      if (_timeFilter == 'Month') {
        matchesTime = date.month == _selectedDate.month &&
            date.year == _selectedDate.year;
      } else if (_timeFilter == 'Year') {
        matchesTime = date.year == _selectedDate.year;
      }

      if (!matchesTime) continue;

      // 2. Scope Filter
      // "For the Group": All expenses
      // "For Me": My share of expenses (Consumption)
      double amountToAdd = amount;

      if (_scopeFilter == 'For Me') {
        double myShare = 0;
        final involved = expense['involved_participants'];

        if (involved is List) {
          for (var item in involved) {
            if (item is Map) {
              // List of Objects - Unequal Split
              // [{'user_id': '...', 'amount': 10}]
              final userId = item['user_id'] ?? item['id'];
              if (userId == currentUser?.id) {
                myShare = (item['amount'] as num).toDouble();
                break;
              }
            }
          }
        }

        if (myShare == 0) continue; // I'm not involved, so skip for "For Me"
        amountToAdd = myShare;
      }

      categoryTotals[category] = (categoryTotals[category] ?? 0) + amountToAdd;
      totalAmount += amountToAdd;
    }

    return {
      'categoryTotals': categoryTotals,
      'totalAmount': totalAmount,
    };
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

        final data = _processData(allExpenses);
        final categoryTotals = data['categoryTotals'] as Map<String, double>;
        final totalAmount = data['totalAmount'] as double;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildTimeFilter(),
              if (_timeFilter != 'All') ...[
                const SizedBox(height: 16),
                _buildDateSelector(),
              ],
              const SizedBox(height: 16),
              _buildChartCard(categoryTotals, totalAmount),
              const SizedBox(height: 16),
              _buildCategoryList(categoryTotals),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeFilter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        children: ['Month', 'Year', 'All'].map((filter) {
          final isSelected = _timeFilter == filter;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _timeFilter = filter;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.grey[800] : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () {
            setState(() {
              if (_timeFilter == 'Month') {
                _selectedDate =
                    DateTime(_selectedDate.year, _selectedDate.month - 1);
              } else {
                _selectedDate = DateTime(_selectedDate.year - 1);
              }
            });
          },
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 120),
          alignment: Alignment.center,
          child: Text(
            _formatDateSelector(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: () {
            setState(() {
              if (_timeFilter == 'Month') {
                _selectedDate =
                    DateTime(_selectedDate.year, _selectedDate.month + 1);
              } else {
                _selectedDate = DateTime(_selectedDate.year + 1);
              }
            });
          },
        ),
      ],
    );
  }

  String _formatDateSelector() {
    if (_timeFilter == 'Month') {
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${months[_selectedDate.month - 1]} ${_selectedDate.year}';
    } else {
      return '${_selectedDate.year}';
    }
  }

  Widget _buildChartCard(
      Map<String, double> categoryTotals, double totalAmount) {
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedCategories.isEmpty) {
      return Card(
        color: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 32),
              const Center(
                child: Text(
                  'No expenses found',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
              const SizedBox(height: 32),
              // Scope Dropdown
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _scopeFilter,
                    dropdownColor: Colors.grey[800],
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold),
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.black),
                    items: ['For Me', 'For the Group'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          value,
                          style: TextStyle(
                            color: value == _scopeFilter
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _scopeFilter = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Top 3 for legend
    final topCategories = sortedCategories.take(3).toList();

    return Card(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'All',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Pie Chart
                SizedBox(
                  height: 150,
                  width: 150,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse
                                .touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                      sections: _buildPieSections(sortedCategories),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Legend & Total
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      Text(
                        '₹ ${totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...topCategories.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getCategoryColor(e.key),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Scope Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _scopeFilter,
                  dropdownColor: Colors.grey[800],
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.black),
                  items: ['For Me', 'For the Group'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(
                        value,
                        style: TextStyle(
                          color: value == _scopeFilter
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _scopeFilter = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(
      List<MapEntry<String, double>> sortedCategories) {
    if (sortedCategories.isEmpty) return [];

    return sortedCategories.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final isTouched = index == _touchedIndex;
      final radius = isTouched ? 80.0 : 75.0;

      return PieChartSectionData(
        color: _getCategoryColor(data.key),
        value: data.value,
        title: '',
        radius: radius,
      );
    }).toList();
  }

  Widget _buildCategoryList(Map<String, double> categoryTotals) {
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: sortedCategories.map((entry) {
        return Container(
          margin: const EdgeInsets.only(bottom: 1),
          color: const Color(0xFF1C1C1E),
          child: ListTile(
            leading: Text(
              _getCategoryEmoji(entry.key),
              style: const TextStyle(fontSize: 24),
            ),
            title: Text(
              entry.key,
              style: const TextStyle(color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            trailing: Text(
              '₹ ${entry.value.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food':
      case 'Restaurants & Bars':
        return const Color(0xFFFFCC00); // Yellow/Orange
      case 'Groceries':
        return const Color(0xFF5AC8FA); // Cyan
      case 'Accommodation':
      case 'Rent & Charges':
        return const Color(0xFF007AFF); // Blue
      case 'Transport':
        return const Color(0xFF34C759); // Green
      case 'Furniture':
        return const Color(0xFFAF52DE); // Purple
      case 'Shopping':
        return const Color(0xFFFF2D55); // Pink
      case 'Entertainment':
        return const Color(0xFF5856D6); // Indigo
      case 'Other':
      default:
        return Colors.grey;
    }
  }

  String _getCategoryEmoji(String category) {
    // Check all categories (including edited defaults)
    final cat = _allCategories.firstWhere(
      (c) => c['name'] == category,
      orElse: () => <String, dynamic>{},
    );
    if (cat.isNotEmpty) {
      return cat['icon'];
    }

    // Fallback for legacy categories or if not found in list
    switch (category) {
      case 'Food':
        return '🍔';
      case 'Transport':
        return '🚌';
      case 'Accommodation':
        return '🏠';
      case 'Entertainment':
        return '🎬';
      case 'Shopping':
        return '🛍️';
      case 'Other':
        return '📦';
      case 'Rent & Charges':
        return '🏠';
      case 'Restaurants & Bars':
        return '🍔';
      case 'Groceries':
        return '🛒';
      case 'Furniture':
        return '🪑';
      default:
        return '📦';
    }
  }
}
