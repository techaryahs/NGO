import 'package:flutter/material.dart';
import 'dart:async';
import '../../../services/service_locator.dart';
import '../../../models/inventory_item_model.dart';
import '../../../models/purchase_model.dart';
import '../../../models/expense_entry_model.dart';
import '../../../models/salary_model.dart';
import '../../../utils/responsive_layout.dart';

/// Dashboard sub-tab showcasing NGO financial statistics and stock status
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _service = ServiceLocator().inventoryExpenseService;

  List<InventoryItemModel> _items = [];
  List<PurchaseModel> _purchases = [];
  List<ExpenseEntryModel> _expenses = [];
  List<SalaryModel> _salaries = [];

  StreamSubscription? _itemsSub;
  StreamSubscription? _purchasesSub;
  StreamSubscription? _expensesSub;
  StreamSubscription? _salariesSub;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscribeStreams();
  }

  void _subscribeStreams() {
    _itemsSub = _service.getInventoryItemsStream().listen((data) {
      if (mounted)
        setState(() {
          _items = data;
          _loading = false;
        });
    });
    _purchasesSub = _service.getPurchasesStream().listen((data) {
      if (mounted)
        setState(() {
          _purchases = data;
          _loading = false;
        });
    });
    _expensesSub = _service.getExpenseEntriesStream().listen((data) {
      if (mounted)
        setState(() {
          _expenses = data;
          _loading = false;
        });
    });
    _salariesSub = _service.getSalariesStream().listen((data) {
      if (mounted)
        setState(() {
          _salaries = data;
          _loading = false;
        });
    });
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    _purchasesSub?.cancel();
    _expensesSub?.cancel();
    _salariesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3B6D11)),
      );
    }

    final now = DateTime.now();

    // 1. Calculations
    // Monthly Expenses (Purchases + Expense Entries in current month/year)
    final monthlyPurchases = _purchases
        .where(
          (p) =>
              p.purchaseDate.month == now.month &&
              p.purchaseDate.year == now.year,
        )
        .fold<double>(0, (sum, p) => sum + p.totalAmount);
    final monthlyGeneralExpenses = _expenses
        .where(
          (e) =>
              e.expenseDate.month == now.month &&
              e.expenseDate.year == now.year,
        )
        .fold<double>(0, (sum, e) => sum + e.totalAmount);
    final totalExpenseMonth = monthlyPurchases + monthlyGeneralExpenses;

    // Yearly Expenses
    final yearlyPurchases = _purchases
        .where((p) => p.purchaseDate.year == now.year)
        .fold<double>(0, (sum, p) => sum + p.totalAmount);
    final yearlyGeneralExpenses = _expenses
        .where((e) => e.expenseDate.year == now.year)
        .fold<double>(0, (sum, e) => sum + e.totalAmount);
    final totalExpenseYear = yearlyPurchases + yearlyGeneralExpenses;

    // Salaries This Month
    final totalSalariesMonth = _salaries
        .where(
          (s) => s.createdAt.month == now.month && s.createdAt.year == now.year,
        )
        .fold<double>(0, (sum, s) => sum + s.netSalary);

    // Pending Payments Count (status = 'Pending' or 'Partial' across transactions)
    final pendingPurchases = _purchases
        .where((p) => p.paymentDetails.paymentStatus != 'Paid')
        .length;
    final pendingExpenses = _expenses
        .where((e) => e.paymentDetails.paymentStatus != 'Paid')
        .length;
    final pendingSalaries = _salaries
        .where((s) => s.paymentDetails.paymentStatus != 'Paid')
        .length;
    final totalPendingPayments =
        pendingPurchases + pendingExpenses + pendingSalaries;

    // Low Stock Items Count
    final lowStockCount = _items.where((item) => item.isLowStock).length;

    // 2. Chart data preparations
    // Last 6 months trend data
    final Map<String, double> last6MonthsData = {};
    for (int i = 5; i >= 0; i--) {
      final targetDate = DateTime(now.year, now.month - i, 1);
      final monthName = _getMonthName(targetDate.month);
      final monthPurchases = _purchases
          .where(
            (p) =>
                p.purchaseDate.month == targetDate.month &&
                p.purchaseDate.year == targetDate.year,
          )
          .fold<double>(0, (sum, p) => sum + p.totalAmount);
      final monthExpenses = _expenses
          .where(
            (e) =>
                e.expenseDate.month == targetDate.month &&
                e.expenseDate.year == targetDate.year,
          )
          .fold<double>(0, (sum, e) => sum + e.totalAmount);
      last6MonthsData[monthName] = monthPurchases + monthExpenses;
    }

    // Category breakdown data
    final Map<String, double> categoryBreakdown = {};
    for (final p in _purchases) {
      final cat = p.itemName.isNotEmpty ? p.itemName : 'Materials';
      categoryBreakdown[cat] = (categoryBreakdown[cat] ?? 0.0) + p.totalAmount;
    }
    for (final e in _expenses) {
      categoryBreakdown[e.category] =
          (categoryBreakdown[e.category] ?? 0.0) + e.totalAmount;
    }
    // Sort and get top 4 categories
    final sortedCategories = categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = sortedCategories.take(4).toList();

    // Payment methods distribution
    final Map<String, double> paymentMethods = {};
    for (final p in _purchases) {
      final method = p.paymentDetails.paymentMethod;
      paymentMethods[method] = (paymentMethods[method] ?? 0.0) + p.totalAmount;
    }
    for (final e in _expenses) {
      final method = e.paymentDetails.paymentMethod;
      paymentMethods[method] = (paymentMethods[method] ?? 0.0) + e.totalAmount;
    }
    for (final s in _salaries) {
      final method = s.paymentDetails.paymentMethod;
      paymentMethods[method] = (paymentMethods[method] ?? 0.0) + s.netSalary;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: KPI Stat Cards
          // Row 1: KPI Stat Cards
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFFAFDF7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE4EFD5)),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.dashboard_rounded, color: Color(0xFF3B6D11)),
                      SizedBox(width: 10),
                      Text(
                        "Financial Overview",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF27500A),
                        ),
                      ),
                    ],
                  ),
                ),

                // Row 1
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _overviewItem(
                          "₹${totalExpenseMonth.toStringAsFixed(0)}",
                          "Monthly Expense",
                          Icons.receipt_long_rounded,
                          const Color(0xFF3B6D11),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _overviewItem(
                          "₹${totalExpenseYear.toStringAsFixed(0)}",
                          "Annual Expense",
                          Icons.analytics_rounded,
                          const Color(0xFF639922),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Row 2
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _overviewItem(
                          "₹${totalSalariesMonth.toStringAsFixed(0)}",
                          "Salaries Disbursed",
                          Icons.badge_rounded,
                          const Color(0xFF27500A),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _overviewItem(
                          "$totalPendingPayments",
                          "Pending Payments",
                          Icons.pending_actions_rounded,
                          totalPendingPayments > 0
                              ? const Color(0xFFC62828)
                              : const Color(0xFF3B6D11),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Row 3
                _overviewItem(
                  "$lowStockCount",
                  "Low Stock Items",
                  Icons.warning_amber_rounded,
                  lowStockCount > 0
                      ? const Color(0xFFF57F17)
                      : const Color(0xFF3B6D11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          // Row 2: Charts and breakdowns
          ResponsiveLayout(
            mobile: Column(
              children: [
                _buildMonthlyTrendChart(last6MonthsData),
                const SizedBox(height: 20),
                _buildCategoryChart(topCategories),
                const SizedBox(height: 20),
                _buildPaymentMethodChart(paymentMethods),
              ],
            ),
            tablet: Column(
              children: [
                _buildMonthlyTrendChart(last6MonthsData),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildCategoryChart(topCategories)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildPaymentMethodChart(paymentMethods)),
                  ],
                ),
              ],
            ),
            desktop: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _buildMonthlyTrendChart(last6MonthsData),
                ),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _buildCategoryChart(topCategories)),
                const SizedBox(width: 20),
                Expanded(
                  flex: 3,
                  child: _buildPaymentMethodChart(paymentMethods),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendChart(Map<String, double> last6MonthsData) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFDF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Monthly Spend Trend (Last 6 Months)",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                ),
              ),
              const Text(
                "Aggregated purchases and operational bills",
                style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
              ),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: ResponsiveLayout.isDesktop(context) ? 2.5 : 1.5,
                child: _CustomBarChart(data: last6MonthsData),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryChart(List<MapEntry<String, double>> topCategories) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFDF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Expense Distribution",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                ),
              ),
              const Text(
                "Proportion of top expense categories",
                style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
              ),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 1.5,
                child: Row(
                  children: [
                    // Custom Painted Donut Chart
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CustomPaint(
                          painter: _DonutChartPainter(
                            values: topCategories.map((c) => c.value).toList(),
                            colors: const [
                              Color(0xFF3B6D11),
                              Color(0xFF639922),
                              Color(0xFF8BBF48),
                              Color(0xFFC0DD97),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Custom Legends
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(topCategories.length, (index) {
                          final colors = const [
                            Color(0xFF3B6D11),
                            Color(0xFF639922),
                            Color(0xFF8BBF48),
                            Color(0xFFC0DD97),
                          ];
                          final cat = topCategories[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colors[index % colors.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat.key,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF27500A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  "₹${cat.value.toStringAsFixed(0)}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF639922),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentMethodChart(Map<String, double> paymentMethods) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFDF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Payment Channels",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF27500A),
                ),
              ),
              const Text(
                "Spend volume breakdown by transaction method",
                style: TextStyle(fontSize: 11, color: Color(0xFF639922)),
              ),
              const SizedBox(height: 25),
              // Payment Methods progress bars
              ...paymentMethods.entries.map((entry) {
                final total = paymentMethods.values.fold<double>(
                  0,
                  (s, v) => s + v,
                );
                final pct = total > 0 ? (entry.value / total) : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                            ),
                          ),
                          Text(
                            "₹${entry.value.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(1)}%)",
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF639922),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: const Color(0xFFEAF3DE),
                          color: const Color(0xFF3B6D11),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  String _getMonthName(int month) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return "";
  }

  Widget _overviewItem(String value, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF639922),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI Stat Card Widget ──────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Container(
        height: 105,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFDF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF639922),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom Gradient Bar Chart ────────────────────────────────────────────────
// class _CustomBarChart extends StatelessWidget {
//   final Map<String, double> data;
//   const _CustomBarChart({required this.data});

//   @override
//   Widget build(BuildContext context) {
//     if (data.isEmpty) {
//       return const Center(
//         child: Text("No operational data available", style: TextStyle(color: Color(0xFF639922), fontSize: 12)),
//       );
//     }
//     final maxValue = data.values.fold<double>(0, (max, val) => val > max ? val : max);
//     final themeColor = const Color(0xFF3B6D11);

//     return Row(
//       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//       crossAxisAlignment: CrossAxisAlignment.end,
//       children: data.entries.map((entry) {
//         final pct = maxValue > 0 ? (entry.value / maxValue) : 0.0;
//         final barHeight = (pct * 130.0).clamp(5.0, 130.0);

//         return Column(
//           mainAxisAlignment: MainAxisAlignment.end,
//           children: [
//             Text(
//               "₹${entry.value.toStringAsFixed(0)}",
//               style: const TextStyle(
//                 fontSize: 10,
//                 fontWeight: FontWeight.bold,
//                 color: Color(0xFF27500A),
//               ),
//             ),
//             const SizedBox(height: 6),
//             Container(
//               width: 32,
//               height: barHeight,
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [themeColor, themeColor.withOpacity(0.45)],
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                 ),
//                 borderRadius: const BorderRadius.only(
//                   topLeft: Radius.circular(5),
//                   topRight: Radius.circular(5),
//                 ),
//                 boxShadow: [
//                   BoxShadow(
//                     color: themeColor.withOpacity(0.12),
//                     blurRadius: 3,
//                     offset: const Offset(0, 1.5),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 6),
//             Text(
//               entry.key,
//               style: const TextStyle(
//                 fontSize: 10.5,
//                 fontWeight: FontWeight.w600,
//                 color: Color(0xFF639922),
//               ),
//             ),
//           ],
//         );
//       }).toList(),
//     );
//   }
// }
// ── Custom Gradient Bar Chart ────────────────────────────────────────────────
class _CustomBarChart extends StatelessWidget {
  final Map<String, double> data;
  const _CustomBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          "No operational data available",
          style: TextStyle(color: Color(0xFF639922), fontSize: 12),
        ),
      );
    }
    final maxValue = data.values.fold<double>(
      0,
      (max, val) => val > max ? val : max,
    );
    final themeColor = const Color(0xFF3B6D11);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.entries.map((entry) {
        final pct = maxValue > 0 ? (entry.value / maxValue) : 0.0;

        return Expanded(
          // ← distribute width evenly
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.max, // ← fill the row's height
            children: [
              Text(
                "₹${entry.value.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF27500A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Flexible(
                // ← yields space when constrained
                child: FractionallySizedBox(
                  heightFactor: pct.clamp(
                    0.05,
                    1.0,
                  ), // ← relative to available height
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [themeColor, themeColor.withOpacity(0.45)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withOpacity(0.12),
                          blurRadius: 3,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF639922),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Custom Donut Chart Painter ───────────────────────────────────────────────
class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  _DonutChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = values.fold(0, (sum, item) => sum + item);
    if (total == 0) {
      // Draw standard empty circle
      final paint = Paint()
        ..color = const Color(0xFFEAF3DE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width / 2 - 10,
        paint,
      );
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final strokeWidth = radius * 0.40;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -3.1415926535 / 2; // Start drawing at top

    for (int i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweepAngle = (values[i] / total) * 2 * 3.1415926535;
      paint.color = colors[i % colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
