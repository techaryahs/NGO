import 'package:flutter/material.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/expense_entries_tab.dart';
import 'tabs/salaries_tab.dart';
import 'tabs/reports_tab.dart';

/// Container Screen for the Inventory & Expense Management Module
class InventoryExpenseScreen extends StatefulWidget {
  const InventoryExpenseScreen({super.key});

  @override
  State<InventoryExpenseScreen> createState() => _InventoryExpenseScreenState();
}

class _InventoryExpenseScreenState extends State<InventoryExpenseScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F7EA),
        body: Column(
          children: [
            // Top tab navigation bar with green theme
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFAFDF7),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                ),
              ),
              alignment: Alignment.centerLeft,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Color(0xFF3B6D11),
                labelColor: Color(0xFF3B6D11),
                unselectedLabelColor: Color(0xFF639922),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 3.0,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  fontFamily: 'Segoe UI',
                ),
                unselectedLabelStyle: TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13.5,
                ),
                tabs: [
                  Tab(text: "Dashboard"),
                  Tab(text: "Expenses"),
                  Tab(text: "Salary"),
                  Tab(text: "Reports"),
                ],
              ),
            ),
            
            // Expanded content section
            const Expanded(
              child: TabBarView(
                children: [
                  DashboardTab(),
                  ExpenseEntriesTab(),
                  SalariesTab(),
                  ReportsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
