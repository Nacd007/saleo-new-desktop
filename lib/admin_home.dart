import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as staff_image;

import 'app_controller.dart';
import 'credit_collections.dart';
import 'admin_settings.dart';
import 'auth_service.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'notifications_page.dart';
import 'pin_input.dart';
import 'product_management_view.dart';
import 'product_import_service.dart';
import 'product_performance.dart';
import 'printer_settings.dart';
import 'sales_report.dart';
import 'profit_page.dart';
import 'workflow_pages.dart';
import 'receptionist_home.dart';
import 'session_widgets.dart';

// Desktop entry points reuse the existing, tested business screens.
Widget desktopProductsPage(AppController c) =>
    _ProductsPage(controller: c, filter: ProductStatusFilter.all);
Widget desktopStaffPage(AppController c) => _StaffPage(controller: c);
Widget desktopSalesPage(AppController c) =>
    _AdminSalesPage(controller: c, initialPeriod: ReportPeriod.today);

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;
  ProductStatusFilter _productFilter = ProductStatusFilter.all;
  ReportPeriod _salesPeriod = ReportPeriod.today;
  static const _labels = [
    'Dashboard',
    'Products',
    'Inventory',
    'Sales',
    'Customers',
    'Debtors',
    'Staff',
    'Reports',
    'Settings',
    'More',
    'Profit',
    'Approvals',
  ];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.inventory_2_outlined,
    Icons.warehouse_outlined,
    Icons.receipt_long_outlined,
    Icons.people_outline,
    Icons.account_balance_wallet_outlined,
    Icons.badge_outlined,
    Icons.bar_chart_outlined,
    Icons.settings_outlined,
    Icons.more_horiz,
    Icons.calculate_outlined,
    Icons.fact_check_outlined,
  ];
  static const _phonePages = [0, 1, 3, 9, 8];

  @override
  void initState() {
    super.initState();
    widget.controller.loadStaff();
  }

  void _navigate(int page) => setState(() => _index = page);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // Tablets always expose the full workspace; phones group secondary pages.
    final sidebar = MediaQuery.sizeOf(context).width >= 720;
    final activeIndex = sidebar && _index == 9 ? 0 : _index;
    final phoneIndex = _phonePages.indexOf(activeIndex);
    const sidebarPages = [0, 1, 2, 3, 4, 5, 6, 7, 10, 11, 8];
    final pages = IndexedStack(
      index: activeIndex,
      children: [
        _Dashboard(
          controller: controller,
          onNavigate: _navigate,
          onProductsFilter: (filter) => setState(() {
            _productFilter = filter;
            _index = 1;
          }),
          onSalesPeriod: (period) => setState(() {
            _salesPeriod = period;
            _index = 3;
          }),
        ),
        _ProductsPage(controller: controller, filter: _productFilter),
        InventoryPage(controller: controller),
        _AdminSalesPage(
          controller: controller,
          initialPeriod: _salesPeriod,
          initialAllDates: false,
        ),
        EnhancedCustomersScreen(controller: controller, embedded: true),
        DebtorsScreen(controller: controller, embedded: true),
        _StaffPage(controller: controller),
        SalesReportPage(
          sales: controller.sales,
          onRefresh: controller.refresh,
          controller: controller,
        ),
        AdminSettingsPage(
          controller: controller,
          staffPageBuilder: (_) => _StaffPage(controller: controller),
        ),
        ListView(
          key: const PageStorageKey('mobile-more'),
          padding: const EdgeInsets.all(16),
          children: [
            Text('More tools', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final page in [2, 4, 5, 6, 7, 10, 11])
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_icons[page]),
                  title: Text(_labels[page]),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _navigate(page),
                ),
              ),
          ],
        ),
        ProfitPage(controller: controller),
        ApprovalPage(controller: controller),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          activeIndex == 9 ? 'More' : _labels[activeIndex],
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'New sale',
            icon: const Icon(Icons.point_of_sale_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('New sale')),
                  body: NewSaleScreen(controller: controller),
                ),
              ),
            ),
          ),
          NotificationBell(controller: controller),
          PrinterStatusChip(controller: controller, iconOnly: !sidebar),
          SizedBox(width: sidebar ? 8 : 2),
          SyncBadge(controller: controller, compact: true, iconOnly: !sidebar),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                confirmSignOut(context, controller);
              } else if (value == 'printer') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PrinterSettingsScreen(controller: controller),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'printer', child: Text('Printer & sync')),
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: sidebar
          ? Row(
              children: [
                SizedBox(
                  width: 202,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight < 620
                              ? 620
                              : constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            extended: true,
                            minExtendedWidth: 202,
                            groupAlignment: -1,
                            selectedIndex: sidebarPages.indexOf(activeIndex),
                            onDestinationSelected: (index) =>
                                _navigate(sidebarPages[index]),
                            leading: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'saleo',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            destinations: [
                              for (final page in sidebarPages)
                                NavigationRailDestination(
                                  icon: Icon(_icons[page]),
                                  label: Text(_labels[page]),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages),
              ],
            )
          : pages,
      bottomNavigationBar: sidebar
          ? null
          : NavigationBar(
              selectedIndex: phoneIndex < 0 ? 3 : phoneIndex,
              onDestinationSelected: (index) => _navigate(_phonePages[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: 'Products',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: 'Sales',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.controller,
    required this.onNavigate,
    required this.onProductsFilter,
    required this.onSalesPeriod,
  });

  final AppController controller;
  final ValueChanged<int> onNavigate;
  final ValueChanged<ProductStatusFilter> onProductsFilter;
  final ValueChanged<ReportPeriod> onSalesPeriod;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month);
    final completedSales = controller.sales
        .where((sale) => !sale.voided)
        .toList();
    final todaySales = completedSales.where(
      (sale) => !sale.createdAt.toLocal().isBefore(today),
    );
    final weeklySales = completedSales.where(
      (sale) => !sale.createdAt.toLocal().isBefore(weekStart),
    );
    final monthlySales = completedSales.where(
      (sale) => !sale.createdAt.toLocal().isBefore(monthStart),
    );
    int revenue(Iterable<Sale> sales) =>
        sales.fold(0, (total, sale) => total + sale.totalCents);
    final todayRevenue = revenue(todaySales);
    final weeklyRevenue = revenue(weeklySales);
    final monthlyRevenue = revenue(monthlySales);
    final averageSale = completedSales.isEmpty
        ? 0
        : revenue(completedSales) ~/ completedSales.length;
    final latestSale = completedSales.isEmpty
        ? null
        : completedSales.reduce(
            (current, next) =>
                current.createdAt.isAfter(next.createdAt) ? current : next,
          );
    final activeProducts = controller.products
        .where((product) => product.active)
        .length;
    final inactiveProducts = controller.products.length - activeProducts;
    final sellingForms = controller.products.fold<int>(
      0,
      (total, product) => total + product.forms.length,
    );
    final receptionistTotals = <String, int>{};
    for (final sale in controller.sales.where((sale) => !sale.voided)) {
      receptionistTotals.update(
        sale.receptionistName,
        (value) => value + sale.totalCents,
        ifAbsent: () => sale.totalCents,
      );
    }
    final topReceptionists = receptionistTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _DashboardWelcome(
            companyName: controller.currentCompany?.name ?? 'Saleo',
            userName: controller.currentUser?.displayName ?? 'Administrator',
            todayRevenue: todayRevenue,
            todayTransactions: todaySales.length,
            lowStockCount: controller.lowStockProducts.length,
          ),
          const SizedBox(height: 14),
          CreditCollectionsPanel(
            sales: controller.sales,
            payments: controller.creditPayments,
          ),
          const SizedBox(height: 14),
          Text(
            'Quick actions',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => onNavigate(1),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Products'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => onNavigate(2),
                icon: const Icon(Icons.warehouse_outlined),
                label: const Text('Inventory'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => onNavigate(3),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Sales history'),
              ),
              OutlinedButton.icon(
                onPressed: latestSale == null
                    ? null
                    : () => showReceipt(
                        context,
                        latestSale,
                        reprint: true,
                        controller: controller,
                      ),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Latest receipt'),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Debtors'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DebtorsScreen(controller: controller),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.people_outline),
                label: const Text('Customers'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        EnhancedCustomersScreen(controller: controller),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Staff'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Staff')),
                      body: _StaffPage(controller: controller),
                    ),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.bar_chart),
                label: const Text('Reports'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Reports')),
                      body: SalesReportPage(
                        sales: controller.sales,
                        onRefresh: controller.refresh,
                        controller: controller,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          DashboardActivityCard(controller: controller),
          const SizedBox(height: 18),
          Text(
            'Products',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _DashboardMetricGrid(
            children: [
              MetricCard(
                label: 'Total products',
                value: '${controller.products.length}',
                icon: Icons.inventory_2_outlined,
                color: Colors.teal,
                supportingText: 'All products in your catalogue',
                onTap: () => onProductsFilter(ProductStatusFilter.all),
              ),
              MetricCard(
                label: 'Active products',
                value: '$activeProducts',
                icon: Icons.check_circle_outline,
                color: Colors.green,
                supportingText: 'Currently available for selling',
                onTap: () => onProductsFilter(ProductStatusFilter.active),
              ),
              MetricCard(
                label: 'Selling forms',
                value: '$sellingForms',
                icon: Icons.sell_outlined,
                color: Theme.of(context).colorScheme.primary,
                supportingText: 'Boxes, packs and single bottles',
                onTap: () => onProductsFilter(ProductStatusFilter.all),
              ),
              MetricCard(
                label: 'Inactive products',
                value: '$inactiveProducts',
                icon: Icons.remove_circle_outline,
                color: inactiveProducts == 0 ? Colors.blueGrey : Colors.red,
                supportingText: inactiveProducts == 0
                    ? 'Nothing needs attention'
                    : 'Review products not currently sold',
                onTap: () => onProductsFilter(ProductStatusFilter.inactive),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Sales',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _DashboardMetricGrid(
            children: [
              MetricCard(
                label: "Today's sales",
                value: 'GH₵ ${money(todayRevenue)}',
                icon: Icons.today_outlined,
                color: Colors.green,
                supportingText: '${todaySales.length} transactions today',
                onTap: () => onSalesPeriod(ReportPeriod.today),
              ),
              MetricCard(
                label: 'Weekly sales',
                value: 'GH₵ ${money(weeklyRevenue)}',
                icon: Icons.date_range_outlined,
                color: Colors.teal,
                supportingText: '${weeklySales.length} transactions this week',
                onTap: () => onSalesPeriod(ReportPeriod.week),
              ),
              MetricCard(
                label: 'Monthly sales',
                value: 'GH₵ ${money(monthlyRevenue)}',
                icon: Icons.calendar_month_outlined,
                color: Colors.indigo,
                supportingText:
                    '${monthlySales.length} transactions this month',
                onTap: () => onSalesPeriod(ReportPeriod.month),
              ),
              MetricCard(
                label: 'Average transaction',
                value: 'GH₵ ${money(averageSale)}',
                icon: Icons.analytics_outlined,
                color: Colors.deepPurple,
                supportingText: completedSales.isEmpty
                    ? 'No completed sales yet'
                    : 'Across ${completedSales.length} completed sales',
                onTap: () => onSalesPeriod(ReportPeriod.year),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Product performance',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ProductPerformanceCard(controller: controller),
          const SizedBox(height: 18),
          Text(
            'Receptionist performance',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: topReceptionists.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No receptionist sales recorded yet.'),
                      ),
                    ]
                  : topReceptionists
                        .map(
                          (entry) => ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(entry.key),
                            trailing: Text(
                              money(entry.value),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SyncBadge(controller: controller),
                  const SizedBox(height: 12),
                  Text(
                    controller.syncMessage ??
                        'Synchronization is checked automatically.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: controller.syncPending,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome({
    required this.companyName,
    required this.userName,
    required this.todayRevenue,
    required this.todayTransactions,
    required this.lowStockCount,
  });

  final String companyName;
  final String userName;
  final int todayRevenue;
  final int todayTransactions;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final initial = companyName.trim().isEmpty
        ? 'S'
        : companyName.trim().substring(0, 1).toUpperCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0xFF123B78), Color(0xFF1768B8)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $userName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$companyName • ${_dashboardDate(now)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
            final summary = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _WelcomeStat(
                  label: 'Sales today',
                  value: 'GH₵ ${money(todayRevenue)}',
                ),
                _WelcomeStat(
                  label: 'Transactions',
                  value: '$todayTransactions',
                ),
                _WelcomeStat(label: 'Low stock', value: '$lowStockCount'),
              ],
            );
            final logo = CircleAvatar(
              radius: constraints.maxWidth < 700 ? 24 : 27,
              backgroundColor: Colors.white.withValues(alpha: .2),
              foregroundColor: Colors.white,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      logo,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 18),
                  summary,
                ],
              );
            }
            return Row(
              children: [
                logo,
                const SizedBox(width: 14),
                Expanded(child: details),
                const SizedBox(width: 16),
                summary,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeStat extends StatelessWidget {
  const _WelcomeStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 104),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _dashboardDate(DateTime date) {
  const months = [
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
    'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class _DashboardMetricGrid extends StatelessWidget {
  const _DashboardMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: children.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 132,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemBuilder: (context, index) => children[index],
      );
    },
  );
}

enum ProductStatusFilter { all, active, inactive }

extension ProductStatusFilterLabel on ProductStatusFilter {
  String get label => switch (this) {
    ProductStatusFilter.all => 'All',
    ProductStatusFilter.active => 'Active',
    ProductStatusFilter.inactive => 'Inactive',
  };
}

class _ProductsPage extends StatefulWidget {
  const _ProductsPage({required this.controller, required this.filter});

  final AppController controller;
  final ProductStatusFilter filter;

  @override
  State<_ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<_ProductsPage> {
  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => ProductManagementView(
    key: ValueKey(
      'products-${controller.currentCompany?.companyId}-${controller.currentUser?.id}',
    ),
    controller: controller,
    initialStatus: widget.filter.label,
    onAdd: () => _addProduct(context),
    onImport: () => _importProducts(context),
    onCategory: () => _createCategory(context),
    onSample: () => _showImportSample(context),
    onTemplate: (format) => _downloadImportTemplate(context, format),
    onEdit: (product) => _editProduct(context, product),
    onAddForm: (product) => _addForm(context, product),
    onEditForm: (product, form) => _editForm(context, product, form),
  );

  Future<void> _importProducts(BuildContext context) async {
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    if (selection.isEmpty || !context.mounted) return;
    final file = selection.single;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    if (bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The spreadsheet could not be opened.')),
      );
      return;
    }
    ProductImportResult result;
    try {
      result = const ProductImportService().parse(bytes, file.extension ?? '');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This spreadsheet could not be read.')),
      );
      return;
    }
    if (!context.mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              result.errors.isEmpty
                  ? 'Import ${result.rows.length} rows?'
                  : 'Spreadsheet needs attention',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Required headings: product_name, product_code, category, '
                      'selling_form and price. Optional stock headings are shown '
                      'in the downloadable sample. Saleo product and inventory exports can be imported back here.',
                    ),
                    if (result.errors.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ...result.errors
                          .take(12)
                          .map(
                            (error) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(
                                '• $error',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                    ] else ...[
                      const SizedBox(height: 14),
                      ...result.rows
                          .take(8)
                          .map(
                            (row) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${row.name} — ${row.form}'),
                              subtitle: Text('${row.code} · ${row.category}'),
                              trailing: Text(money(row.priceCents)),
                            ),
                          ),
                      if (result.rows.length > 8)
                        Text('And ${result.rows.length - 8} more rows…'),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(result.canImport ? 'Cancel' : 'Close'),
              ),
              if (result.canImport)
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Import'),
                ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final rowsToImport = await _reviewImportConflicts(context, result.rows);
    if (!context.mounted || rowsToImport.isEmpty) return;
    await controller.importProducts(rowsToImport);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${rowsToImport.length} spreadsheet rows imported.'),
      ),
    );
  }

  Future<List<ProductImportRow>> _reviewImportConflicts(
    BuildContext context,
    List<ProductImportRow> rows,
  ) async {
    final productsByCode = {
      for (final product in controller.products)
        product.code.toUpperCase(): product,
    };
    final productsByName = {
      for (final product in controller.products)
        product.name.toLowerCase(): product,
    };
    final conflictCodes = <String, Product>{};
    for (final row in rows) {
      final code = row.code.toUpperCase();
      final byCode = productsByCode[code];
      final byName = productsByName[row.name.toLowerCase()];
      if (byCode != null ||
          (byName != null && byName.code.toUpperCase() != code)) {
        conflictCodes[code] = byCode ?? byName!;
      }
    }
    if (conflictCodes.isEmpty) return rows;
    final selectedCodes = <String>{};
    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Review product conflicts'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Some uploaded products already exist by code or name. Select the ones you want to replace/update. Unselected conflicts will be skipped.',
                      ),
                      const SizedBox(height: 12),
                      ...conflictCodes.entries.map((entry) {
                        final uploaded = rows.firstWhere(
                          (row) => row.code.toUpperCase() == entry.key,
                        );
                        final existing = entry.value;
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: selectedCodes.contains(entry.key),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selectedCodes.add(entry.key);
                            } else {
                              selectedCodes.remove(entry.key);
                            }
                          }),
                          title: Text(uploaded.name),
                          subtitle: Text(
                            'Uploaded: ${uploaded.code} · ${uploaded.category}\n'
                            'Existing: ${existing.code} · ${existing.name} · ${existing.category}',
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel import'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!proceed) return const [];
    return rows.where((row) {
      final code = row.code.toUpperCase();
      return !conflictCodes.containsKey(code) || selectedCodes.contains(code);
    }).toList();
  }

  Future<void> _showImportSample(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Product import sample'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use one row for each selling form. Rows with the same product code belong to one product.',
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: ProductImportService.sampleHeaders
                      .map((header) => DataColumn(label: Text(header)))
                      .toList(),
                  rows: ProductImportService.sampleRows
                      .map(
                        (row) => DataRow(
                          cells: row
                              .map((value) => DataCell(Text('$value')))
                              .toList(),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _downloadImportTemplate(
    BuildContext context,
    String extension,
  ) async {
    const service = ProductImportService();
    final excel = extension == 'xlsx';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save Saleo product template',
      fileName: 'saleo-product-import-template.$extension',
      bytes: excel ? service.sampleExcel() : service.sampleCsv(),
      mimeType: excel
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv',
    );
    if (!context.mounted || uri == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template saved to ${uri.toString()}')),
    );
  }

  Future<void> _createCategory(BuildContext context) async {
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create category'),
        content: TextField(
          controller: field,
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (field.text.trim().isNotEmpty) {
                Navigator.pop(context, field.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null) return;
    try {
      await controller.createCategory(name);
      if (mounted) setState(() {});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _addProduct(BuildContext context) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final category = TextEditingController();
    final form = TextEditingController();
    final baseUnit = TextEditingController();
    final unitsPerForm = TextEditingController(text: '1');
    final price = TextEditingController();
    final openingStock = TextEditingController(text: '0');
    final lowStockThreshold = TextEditingController(text: '0');
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add product'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Product code',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      helperText:
                          'Create categories from the Products toolbar.',
                    ),
                    items: controller.productCategories
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        )
                        .toList(),
                    onChanged: (name) => category.text = name ?? '',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: form,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'First selling form',
                      hintText: 'Box, Half box, Pack, Single',
                      helperText: 'You can add more selling forms after saving the product.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: unitsPerForm,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Units in this form',
                      hintText: '1',
                      helperText: 'Optional. Example: Box = 10 pieces. Use 1 for a single item.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: baseUnit,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Smallest stock unit',
                      hintText: 'piece, bottle, small bag, pack',
                      helperText: 'The app stores inventory in this unit for accurate deduction.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Price'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: openingStock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Opening stock',
                      helperText: 'Enter how many of the first selling form you received.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lowStockThreshold,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Low-stock alert level',
                      helperText: 'Enter this in the first selling form above. Saleo converts it to stock units. Use 0 to turn alerts off.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ) ??
        false;
    if (!saved) return;
    final value = double.tryParse(price.text.trim());
    final opening = int.tryParse(openingStock.text.trim());
    final unitCount = int.tryParse(
      unitsPerForm.text.trim().isEmpty ? '1' : unitsPerForm.text.trim(),
    );
    final threshold = int.tryParse(lowStockThreshold.text.trim());
    if (name.text.trim().isEmpty ||
        code.text.trim().isEmpty ||
        category.text.trim().isEmpty ||
        form.text.trim().isEmpty ||
        baseUnit.text.trim().isEmpty ||
        value == null ||
        value <= 0 ||
        unitCount == null ||
        unitCount <= 0 ||
        opening == null ||
        opening < 0 ||
        threshold == null ||
        threshold < 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check the product and stock values.')),
        );
      }
      return;
    }
    await controller.addProduct(
      name: name.text,
      code: code.text,
      category: category.text,
      formName: form.text,
      priceCents: (value * 100).round(),
      baseUnit: baseUnit.text,
      unitsPerForm: unitCount,
      openingStockBase: opening * unitCount,
      lowStockThreshold: threshold * unitCount,
    );
  }

  Future<void> _addForm(BuildContext context, Product product) async {
    final result = await showDialog<SellingFormEdit>(
      context: context,
      builder: (_) => SellingFormEditor(
        product: product,
        form: SellingForm(
          id: -1,
          productId: product.id,
          name: '',
          priceCents: 0,
          active: true,
          unitsPerForm: 1,
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    await controller.addSellingForm(
      product,
      result.name,
      result.priceCents,
      result.units,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selling form saved on this device. Synchronization requested.',
          ),
        ),
      );
    }
  }

  Future<void> _editForm(
    BuildContext context,
    Product product,
    SellingForm form,
  ) async {
    final result = await showDialog<SellingFormEdit>(
      context: context,
      builder: (_) => SellingFormEditor(product: product, form: form),
    );
    if (result == null || !context.mounted) return;
    await controller.updateSellingForm(
      form,
      result.name,
      result.priceCents,
      result.active,
      result.units,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Selling form saved on this device. Synchronization requested.',
        ),
      ),
    );
  }

  Future<void> _editProduct(BuildContext context, Product product) async {
    final name = TextEditingController(text: product.name);
    final category = TextEditingController(text: product.category);
    Uint8List? selectedImage;
    var removeImage = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: selectedImage != null
                      ? MemoryImage(selectedImage!)
                      : (!removeImage && product.imageBytes != null
                            ? MemoryImage(product.imageBytes!)
                            : null),
                  child:
                      selectedImage == null &&
                          (removeImage || product.imageBytes == null)
                      ? const Icon(Icons.inventory_2_outlined, size: 34)
                      : null,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          type: FileType.image,
                          compressionQuality: 70,
                        );
                        if (picked.isEmpty) return;
                        final bytes = await picked.single.readAsBytes();
                        if (bytes.length > 600000 || !context.mounted) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Choose an image smaller than 600 KB.',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        setDialogState(() {
                          selectedImage = bytes;
                          removeImage = false;
                        });
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose image'),
                    ),
                    if (product.imageBytes != null || selectedImage != null)
                      TextButton.icon(
                        onPressed: () => setDialogState(() {
                          selectedImage = null;
                          removeImage = true;
                        }),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: category,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    helperText:
                        'Use an existing category name or create a new one.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true ||
        name.text.trim().isEmpty ||
        category.text.trim().isEmpty) {
      return;
    }
    await controller.updateProductDetails(
      product: product,
      name: name.text.trim(),
      category: category.text.trim(),
      imageBytes: selectedImage,
      removeImage: removeImage,
    );
  }
}

const _staffRoles = [
  'Cashier',
  'Receptionist',
  'Salesperson',
  'Storekeeper',
  'Supervisor',
  'Custom',
];

class _StaffPage extends StatelessWidget {
  const _StaffPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final receptionists = controller.currentCompany != null
        ? controller.staff
        : controller.users
              .where((user) => user.role == UserRole.receptionist)
              .map(
                (user) => StaffMember(
                  id: user.id,
                  username: user.username,
                  displayName: user.displayName,
                  active: user.active,
                  archivedAt: user.archivedAt,
                  recoverUntil: user.archivedAt?.add(const Duration(days: 90)),
                  jobTitle: user.jobTitle,
                ),
              )
              .toList();
    receptionists.sort((a, b) {
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: receptionists.isEmpty ? 1 : receptionists.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (receptionists.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.group_add_outlined, size: 42),
                      SizedBox(height: 10),
                      Text(
                        'No staff yet',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Add a staff member or send a secure email invitation.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            final user = receptionists[index];
            final firstArchived =
                user.isArchived &&
                (index == 0 || !receptionists[index - 1].isArchived);
            final card = Card(
              color: user.isArchived
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: user.photoBytes == null
                      ? null
                      : MemoryImage(user.photoBytes!),
                  child: user.photoBytes != null
                      ? null
                      : user.isArchived
                      ? const Icon(Icons.archive_outlined)
                      : Text(user.displayName.substring(0, 1).toUpperCase()),
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  user.isArchived
                      ? '${user.jobTitle} • @${user.username} • Archived until ${_staffDate(user.recoverUntil)}'
                      : '${user.jobTitle} • @${user.username} • ${user.active ? 'Active' : 'Inactive'}',
                ),
                trailing: user.isArchived
                    ? FilledButton.tonalIcon(
                        onPressed: user.canRecover
                            ? () => _restore(context, user)
                            : null,
                        icon: const Icon(Icons.restore, size: 18),
                        label: Text(user.canRecover ? 'Restore' : 'Expired'),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: user.active,
                            onChanged: (value) =>
                                _setActive(context, user, value),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editStaff(context, user);
                              }
                              if (value == 'photo') _staffPhoto(context, user);
                              if (value == 'removePhoto') {
                                _staffPhoto(context, user, remove: true);
                              }
                              if (value == 'reset') _resetPin(context, user);
                              if (value == 'archive') _archive(context, user);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit details & role'),
                              ),
                              if (controller.currentCompany != null)
                                const PopupMenuItem(
                                  value: 'photo',
                                  child: Text('Add / change photo'),
                                ),
                              if (user.photoBytes != null)
                                const PopupMenuItem(
                                  value: 'removePhoto',
                                  child: Text('Remove photo'),
                                ),
                              if (controller.currentCompany != null)
                                const PopupMenuItem(
                                  value: 'reset',
                                  child: Text('Reset PIN'),
                                ),
                              if (!user.active)
                                const PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.archive_outlined),
                                    title: Text('Move to archive'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            );
            if (!firstArchived) return card;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 10, 4, 8),
                  child: Text(
                    'ARCHIVE • RECOVERABLE FOR 90 DAYS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                card,
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _addStaff(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add staff'),
          ),
        ),
      ],
    );
  }

  Future<void> _addStaff(BuildContext context) async {
    final displayName = TextEditingController();
    final username = TextEditingController();
    final pin = TextEditingController();
    final email = TextEditingController();
    final customRole = TextEditingController();
    var inviteByEmail = false;
    var jobTitle = 'Cashier';
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(inviteByEmail ? 'Invite staff' : 'Add staff'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Create now')),
                        ButtonSegment(value: true, label: Text('Email invite')),
                      ],
                      selected: {inviteByEmail},
                      onSelectionChanged: (value) =>
                          setDialogState(() => inviteByEmail = value.first),
                    ),
                    const SizedBox(height: 16),
                    if (inviteByEmail) ...[
                      const Text(
                        'Saleo will email a secure one-time link. The staff member chooses their own username and PIN.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Staff email',
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: displayName,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FourDigitPinField(
                        controller: pin,
                        label: 'Temporary 4-digit PIN',
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: jobTitle,
                      decoration: const InputDecoration(labelText: 'Job role'),
                      items: _staffRoles
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => jobTitle = value ?? jobTitle),
                    ),
                    if (jobTitle == 'Custom') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customRole,
                        decoration: const InputDecoration(
                          labelText: 'Custom job role',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'The job role is a label only. It does not give administrator permissions.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(inviteByEmail ? 'Send invitation' : 'Create'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!saved) return;
    final selectedRole = jobTitle == 'Custom'
        ? customRole.text.trim()
        : jobTitle;
    if (selectedRole.isEmpty) return;
    if (inviteByEmail) {
      try {
        await controller.inviteReceptionist(email.text, jobTitle: selectedRole);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation sent to ${email.text.trim()}.')),
        );
      } on AuthException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    if (displayName.text.trim().isNotEmpty &&
        username.text.trim().isNotEmpty &&
        RegExp(r'^\d{4}$').hasMatch(pin.text)) {
      try {
        await controller.addReceptionist(
          username: username.text,
          displayName: displayName.text,
          password: pin.text,
          jobTitle: selectedRole,
        );
      } on AuthException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _setActive(
    BuildContext context,
    StaffMember member,
    bool active,
  ) async {
    try {
      if (controller.currentCompany != null) {
        await controller.setStaffActive(member, active);
      } else {
        final local = controller.users.firstWhere(
          (user) => user.id == member.id,
        );
        await controller.setUserActive(local, active);
      }
    } on AuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _staffPhoto(
    BuildContext context,
    StaffMember member, {
    bool remove = false,
  }) async {
    try {
      Uint8List? bytes;
      if (!remove) {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png'],
        );
        if (result.isEmpty) return;
        final raw = await result.single.readAsBytes();
        if (raw.length > 600 * 1024) {
          throw const AuthException(
            'Choose a JPEG or PNG smaller than 600 KB.',
          );
        }
        final decoded = staff_image.decodeImage(raw);
        if (decoded == null) {
          throw const AuthException('This photo could not be read.');
        }
        final resized = staff_image.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 384 : null,
          height: decoded.height > decoded.width ? 384 : null,
        );
        bytes = Uint8List.fromList(staff_image.encodeJpg(resized, quality: 85));
      }
      await controller.updateStaffPhoto(member, bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remove
                  ? 'Staff photo removed from the server.'
                  : 'Staff photo saved to the server.',
            ),
          ),
        );
      }
    } on AuthException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The photo could not be saved. Check the file and your connection, then try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editStaff(BuildContext context, StaffMember member) async {
    final displayName = TextEditingController(text: member.displayName);
    final username = TextEditingController(text: member.username);
    final knownRole = _staffRoles.contains(member.jobTitle)
        ? member.jobTitle
        : 'Custom';
    var selectedRole = knownRole;
    final customRole = TextEditingController(
      text: knownRole == 'Custom' ? member.jobTitle : '',
    );
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Edit ${member.displayName}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: displayName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(labelText: 'Job role'),
                      items: _staffRoles
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(
                        () => selectedRole = value ?? selectedRole,
                      ),
                    ),
                    if (selectedRole == 'Custom') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customRole,
                        decoration: const InputDecoration(
                          labelText: 'Custom job role',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'This job title does not change administrator permissions.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    final jobTitle = selectedRole == 'Custom'
        ? customRole.text.trim()
        : selectedRole;
    final name = displayName.text.trim();
    final handle = username.text.trim();
    displayName.dispose();
    username.dispose();
    customRole.dispose();
    if (!saved || name.isEmpty || handle.isEmpty || jobTitle.isEmpty) return;
    try {
      await controller.updateStaffDetails(
        member,
        username: handle,
        displayName: name,
        jobTitle: jobTitle,
      );
    } on AuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _resetPin(BuildContext context, StaffMember member) async {
    final pin = TextEditingController();
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Reset PIN for ${member.displayName}'),
            content: FourDigitPinField(
              controller: pin,
              label: 'New 4-digit PIN',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Update PIN'),
              ),
            ],
          ),
        ) ??
        false;
    if (!saved || !RegExp(r'^\d{4}$').hasMatch(pin.text)) return;
    try {
      await controller.resetStaffPin(member, pin.text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PIN updated for ${member.displayName}.')),
      );
    } on AuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _archive(BuildContext context, StaffMember member) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.archive_outlined),
            title: Text('Archive ${member.displayName}?'),
            content: const Text(
              'This staff member will remain recoverable for 90 days and will move to the bottom of the list.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Move to archive'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await controller.archiveStaff(member);
    } on Object catch (error) {
      if (!context.mounted) return;
      final message = error is AuthException ? error.message : '$error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _restore(BuildContext context, StaffMember member) async {
    try {
      await controller.restoreStaff(member);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.displayName} restored as inactive.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      final message = error is AuthException ? error.message : '$error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

String _staffDate(DateTime? value) {
  if (value == null) return 'unavailable';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class _AdminSalesPage extends StatefulWidget {
  const _AdminSalesPage({
    required this.controller,
    required this.initialPeriod,
    this.initialAllDates = false,
  });

  final AppController controller;
  final ReportPeriod initialPeriod;
  final bool initialAllDates;

  @override
  State<_AdminSalesPage> createState() => _AdminSalesPageState();
}

class _AdminSalesPageState extends State<_AdminSalesPage> {
  late bool _allDates;
  DateTimeRange? _range;
  late ReportPeriod _period;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _allDates = widget.initialAllDates;
  }

  @override
  void didUpdateWidget(covariant _AdminSalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPeriod != widget.initialPeriod) {
      setState(() {
        _period = widget.initialPeriod;
        _allDates = false;
        _range = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceSales = _range == null && !_allDates
        ? salesForPeriod(widget.controller.sales, _period)
        : widget.controller.sales;
    final sales = sourceSales.where((sale) {
      final date = sale.createdAt.toLocal();
      final matchesRange =
          _range == null ||
          (!date.isBefore(_range!.start) &&
              date.isBefore(_range!.end.add(const Duration(days: 1))));
      final q = _query.toLowerCase();
      final matchesQuery =
          q.isEmpty ||
          sale.receiptNumber.toLowerCase().contains(q) ||
          [
            sale.receptionistName,
            sale.receptionistUsername,
            sale.customerName ?? '',
            sale.customerCompany ?? '',
            sale.collectedBy ?? '',
            sale.customerPhone ?? '',
            ...sale.items.map((i) => i.productName),
          ].join(' ').toLowerCase().contains(q);
      return matchesRange && matchesQuery;
    }).toList();
    final total = sales
        .where((sale) => !sale.voided)
        .fold<int>(0, (sum, sale) => sum + sale.totalCents);
    final valid = sales.where((sale) => !sale.voided);
    final cash = valid.fold<int>(0, (sum, sale) => sum + sale.cashCents);
    final mobile = valid.fold<int>(
      0,
      (sum, sale) => sum + sale.mobileMoneyCents,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search receipts, receptionists, companies, customers or products',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...ReportPeriod.values.map(
                      (period) => Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text(period.label),
                          selected:
                              !_allDates && _range == null && _period == period,
                          onSelected: (_) => setState(() {
                            _period = period;
                            _allDates = false;
                            _range = null;
                          }),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: const Text('All dates'),
                        selected: _allDates && _range == null,
                        onSelected: (_) => setState(() {
                          _allDates = true;
                          _range = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        _range == null
                            ? 'Select date range'
                            : '${_range!.start.day}/${_range!.start.month}/${_range!.start.year} - ${_range!.end.day}/${_range!.end.month}/${_range!.end.year}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Text(
                          '${sales.length} sales - ${money(total)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Cash ${money(cash)}'),
                      Text('MOMO ${money(mobile)}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SalesList(
            sales: sales,
            canVoid: true,
            onVoid: _voidSale,
            controller: widget.controller,
            footer: SalesCharts(
              sales: sales,
              movements: widget.controller.stockMovements,
              range:
                  _range ??
                  DateTimeRange(
                    start: _allDates
                        ? DateTime(2020)
                        : reportStart(_period, DateTime.now()),
                    end: DateTime.now(),
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (range != null) {
      setState(() {
        _range = range;
        _allDates = false;
      });
    }
  }

  Future<void> _voidSale(Sale sale) async {
    final reason = TextEditingController();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Void ${sale.receiptNumber}?'),
            content: TextField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Required reason'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Void sale'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && reason.text.trim().isNotEmpty) {
      await widget.controller.voidSale(sale, reason.text);
    }
  }
}
