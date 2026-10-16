import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_home.dart';
import 'admin_settings.dart';
import 'app_controller.dart';
import 'common_widgets.dart';
import 'desktop_design.dart';
import 'desktop_icons.dart';
import 'desktop_drafts.dart';
import 'desktop_settings_shell.dart';
import 'desktop_period_filter.dart';
import 'formatters.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'notifications_page.dart';
import 'profit_page.dart';
import 'sales_report.dart';
import 'workflow_pages.dart';
import 'revenue_buckets.dart';

const receptionistDesktopPages = [
  'Sell',
  'Products',
  'Receive Stock',
  'Sales',
  'Customers',
  'Debtors',
  'Settings',
];
const adminDesktopPages = [
  'Dashboard',
  'Sell',
  'Products',
  'Inventory',
  'Sales',
  'Customers',
  'Debtors',
  'Staff',
  'Reports',
  'Profit',
  'Settings',
];
const _pageIcons = <String, IconData>{
  'Dashboard': Icons.dashboard_outlined,
  'Sell': Icons.shopping_cart_outlined,
  'Products': Icons.inventory_2_outlined,
  'Inventory': Icons.warehouse_outlined,
  'Receive Stock': Icons.add_box_outlined,
  'Sales': Icons.receipt_long_outlined,
  'Customers': Icons.people_outline,
  'Debtors': Icons.account_balance_wallet_outlined,
  'Staff': Icons.badge_outlined,
  'Reports': Icons.bar_chart_outlined,
  'Profit': Icons.calculate_outlined,
  'Settings': Icons.settings_outlined,
};

class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({super.key, required this.controller});
  final AppController controller;
  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  int _index = 0;
  bool _collapsed = false;
  AppController get c => widget.controller;
  bool get admin => c.currentUser?.role == UserRole.admin;
  List<String> get labels =>
      admin ? adminDesktopPages : receptionistDesktopPages;
  @override
  void initState() {
    super.initState();
    if (admin) unawaited(c.loadStaff());
  }

  void _go(String title) {
    final index = labels.indexOf(title);
    if (index >= 0) {
      setState(() => _index = index);
      if (title == 'Debtors') unawaited(c.refresh());
    }
  }

  void _approvals() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Approvals & corrections')),
        body: ApprovalPage(controller: c),
      ),
    ),
  );
  Widget _page(String title) => switch (title) {
    'Dashboard' => DesktopDashboard(controller: c, onNavigate: _go),
    'Sell' => DesktopSellPage(controller: c),
    'Products' =>
      admin
          ? desktopProductsPage(c)
          : ReceptionistProductCatalogue(controller: c),
    'Inventory' => InventoryPage(controller: c),
    'Receive Stock' =>
      c.inventoryPreferences.staffCanReceiveStock
          ? InventoryPage(controller: c, receiveOnly: true)
          : const Center(
              child: Text(
                'Your administrator has not enabled stock receiving for your account.',
              ),
            ),
    'Sales' => desktopSalesPage(c),
    'Customers' => EnhancedCustomersScreen(controller: c, embedded: true),
    'Debtors' => DebtorsScreen(controller: c, embedded: true),
    'Staff' => desktopStaffPage(c),
    'Reports' => SalesReportPage(
      controller: c,
      sales: c.sales,
      onRefresh: c.refresh,
    ),
    'Profit' => ProfitPage(controller: c),
    'Settings' => const SizedBox.shrink(),
    _ => const SizedBox.shrink(),
  };
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sidebarText = scheme.onSurface;
    final selected = Theme.of(context).colorScheme.primaryContainer;
    return Scaffold(
      body: Stack(
        children: [
          Offstage(
            offstage: labels[_index] == 'Settings',
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _collapsed ? 72 : 180,
                  key: const ValueKey('workspace-sidebar'),
                  color: scheme.surfaceContainerLowest,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 22,
                        ),
                        child: _collapsed
                            ? Icon(
                                Icons.receipt_long_outlined,
                                color: sidebarText,
                              )
                            : SaleoBrand(color: sidebarText),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(10, 24, 10, 0),
                          children: [
                            for (var i = 0; i < labels.length; i++)
                              if (labels[i] != 'Settings')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Tooltip(
                                    message: _collapsed ? labels[i] : '',
                                    child: Material(
                                      color: i == _index
                                          ? selected
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => _go(labels[i]),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              DesktopGraphicIcon(labels[i]),
                                              if (!_collapsed) ...[
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    labels[i],
                                                    style: TextStyle(
                                                      color: sidebarText,
                                                      fontWeight: i == _index
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            key: const ValueKey('pinned-settings'),
                            leading: const DesktopGraphicIcon('Settings'),
                            title: _collapsed ? null : const Text('Settings'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            onTap: () => _go('Settings'),
                          ),
                        ),
                      ),
                      Divider(color: sidebarText.withValues(alpha: .15)),
                      if (!_collapsed) ...[
                        _identity(
                          c.currentCompany?.name ?? 'Company',
                          'Company',
                          sidebarText,
                          Icons.storefront_outlined,
                        ),
                        _identity(
                          c.currentUser?.displayName ?? '',
                          admin ? 'Administrator' : 'Receptionist',
                          sidebarText,
                          Icons.person_outline,
                        ),
                      ],
                      Align(
                        alignment: _collapsed
                            ? Alignment.center
                            : Alignment.centerRight,
                        child: IconButton(
                          tooltip: _collapsed
                              ? 'Expand sidebar'
                              : 'Collapse sidebar',
                          onPressed: () =>
                              setState(() => _collapsed = !_collapsed),
                          icon: Icon(
                            _collapsed
                                ? Icons.chevron_right
                                : Icons.chevron_left,
                            color: sidebarText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 68,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              labels[_index],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child:
                                    c.syncState == AppSyncState.offline ||
                                        c.syncState == AppSyncState.failed
                                    ? Container(
                                        key: const ValueKey(
                                          'sync-header-notice',
                                        ),
                                        height: 40,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.errorContainer,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.cloud_off_outlined,
                                              size: 18,
                                              color: scheme.onErrorContainer,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Tooltip(
                                                message: c.syncMessage ?? 'Sync failed. Saved records are retained.',
                                                child: Text(
                                                  c.syncMessage ?? 'Sync failed. Saved records are retained.',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        scheme.onErrorContainer,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  admin &&
                                                      c
                                                              .syncService
                                                              .lastCustomerUploadError !=
                                                          null
                                                  ? () => _go('Customers')
                                                  : c.syncPending,
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    scheme.onErrorContainer,
                                              ),
                                              child: Text(
                                                admin &&
                                                        c
                                                                .syncService
                                                                .lastCustomerUploadError !=
                                                            null
                                                    ? 'Fix customers'
                                                    : 'Retry',
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            if (MediaQuery.sizeOf(context).width > 1150)
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await showSearch<String>(
                                    context: context,
                                    delegate: _WorkspaceSearch(c, labels),
                                  );
                                  if (result != null && mounted) _go(result);
                                },
                                icon: const Icon(Icons.search, size: 18),
                                label: const Text('Search Saleo'),
                              ),
                            const SizedBox(width: 12),
                            if (admin && c.pendingApprovalCount > 0)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .error,
                                ),
                                onPressed: _approvals,
                                icon: const Icon(
                                  Icons.pending_actions,
                                  size: 18,
                                ),
                                label: Text(
                                  'Pending approvals ${c.pendingApprovalCount}',
                                ),
                              ),
                            NotificationBell(controller: c),
                            PrinterStatusChip(
                              controller: c,
                              iconOnly: MediaQuery.sizeOf(context).width < 1200,
                            ),
                            IconButton(
                              tooltip: c.syncMessage ?? 'Synchronize now',
                              onPressed: c.syncState == AppSyncState.syncing
                                  ? null
                                  : c.syncPending,
                              icon: SyncBadge(controller: c, iconOnly: true),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: [
                            for (final title in labels)
                              KeyedSubtree(
                                key: ValueKey(title),
                                child: _page(title),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              c.summary.pendingSync == 0
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_upload_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${c.summary.pendingSync} sales awaiting upload • ${c.syncState.name}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Text(
                              c.lastSuccessfulSync == null
                                  ? 'Not synced this session'
                                  : 'Last sync ${saleDate(c.lastSuccessfulSync!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (labels[_index] == 'Settings')
            DesktopSettingsWorkspace(
              controller: c,
              onClose: () => _go(admin ? 'Dashboard' : 'Sell'),
            ),
        ],
      ),
    );
  }

  Widget _identity(String name, String subtitle, Color color, IconData icon) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withValues(alpha: .65),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _WorkspaceSearch extends SearchDelegate<String> {
  _WorkspaceSearch(this.c, this.pages);
  final AppController c;
  final List<String> pages;
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, ''),
    icon: const Icon(Icons.arrow_back),
  );
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);
  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.toLowerCase();
    return ListView(
      children: [
        for (final p in pages.where((p) => p.toLowerCase().contains(q)))
          ListTile(
            leading: Icon(_pageIcons[p]),
            title: Text(p),
            onTap: () => close(context, p),
          ),
        if (q.isNotEmpty) ...[
          for (final p
              in c.activeProducts
                  .where(
                    (p) => '${p.name} ${p.code} ${p.category}'
                        .toLowerCase()
                        .contains(q),
                  )
                  .take(12))
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(p.name),
              subtitle: Text(
                '${p.category} • ${productStockText(p, p.currentStock)}',
              ),
              onTap: () => close(context, 'Products'),
            ),
          for (final s
              in c.sales
                  .where(
                    (s) =>
                        '${s.receiptNumber} ${s.receptionistName} ${s.customerName}'
                            .toLowerCase()
                            .contains(q),
                  )
                  .take(12))
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(s.receiptNumber),
              subtitle: Text(
                'GHS ${money(s.totalCents)} • ${saleDate(s.createdAt)}',
              ),
              onTap: () => close(context, 'Sales'),
            ),
        ],
      ],
    );
  }
}

class ReceptionistProductCatalogue extends StatefulWidget {
  const ReceptionistProductCatalogue({super.key, required this.controller});
  final AppController controller;
  @override
  State<ReceptionistProductCatalogue> createState() =>
      _ReceptionistProductCatalogueState();
}

class _ReceptionistProductCatalogueState
    extends State<ReceptionistProductCatalogue> {
  String _query = '';
  String? _category;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final products = c.activeProducts
        .where(
          (p) =>
              (_category == null || p.category == _category) &&
              '${p.name} ${p.code}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search products or codes',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                hint: const Text('All categories'),
                value: _category,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All categories'),
                  ),
                  for (final cat in {
                    for (final p in c.activeProducts) p.category,
                  })
                    DropdownMenuItem(value: cat, child: Text(cat)),
                ],
                onChanged: (v) =>
                    setState(() => _category = v == '' ? null : v),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? const Center(child: Text('No matching products.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: products.length,
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ExpansionTile(
                          leading: p.imageBytes == null
                              ? const Icon(Icons.inventory_2_outlined)
                              : Image.memory(
                                  p.imageBytes!,
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                ),
                          title: Text(p.name),
                          subtitle: Text('${p.category} • ${p.code}'),
                          trailing: Text(productStockText(p, p.currentStock)),
                          children: [
                            for (final f in p.forms)
                              ListTile(
                                title: Text(f.name),
                                subtitle: Text(
                                  '${f.unitsPerForm} single units per form',
                                ),
                                trailing: Text('GHS ${money(f.priceCents)}'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class DesktopDashboard extends StatefulWidget {
  const DesktopDashboard({
    super.key,
    required this.controller,
    required this.onNavigate,
  });
  final AppController controller;
  final void Function(String) onNavigate;
  @override
  State<DesktopDashboard> createState() => _DesktopDashboardState();
}

String _soldStockText(AppController c, String code, int quantity) {
  final product = c.products.where((p) => p.code == code).firstOrNull;
  return product == null
      ? '$quantity single units'
      : productStockText(product, quantity);
}

class _DesktopDashboardState extends State<DesktopDashboard> {
  ReportPeriod _period = ReportPeriod.today;
  DateTimeRange? _custom;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final range = _custom ?? desktopReportRange(_period, DateTime.now());
    final sales =
        c.sales
            .where((s) => !s.voided && desktopDateInRange(s.createdAt, range))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final revenue = sales.fold<int>(0, (n, s) => n + s.totalCents);
    final debt = c.debtors.fold<int>(0, (n, d) => n + d.outstandingCents);
    final quantities = <String, int>{};
    for (final s in sales) {
      for (final i in s.items) {
        quantities.update(
          i.productCode,
          (n) => n + i.quantity * i.unitsPerForm,
          ifAbsent: () => i.quantity * i.unitsPerForm,
        );
      }
    }
    final top = quantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your business at a glance',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(c.currentCompany?.name ?? 'Saleo'),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => widget.onNavigate('Sell'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New sale'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onNavigate('Inventory'),
              icon: const Icon(Icons.add_box_outlined, size: 18),
              label: const Text('Receive stock'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopPeriodFilter(
          period: _period,
          customRange: _custom,
          onChanged: (p, r) => setState(() {
            _period = p;
            _custom = r;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in [
                ('Sales revenue', 'GHS ${money(revenue)}', Icons.trending_up),
                (
                  'Transactions',
                  '${sales.length}',
                  Icons.receipt_long_outlined,
                ),
                (
                  'Outstanding debt',
                  'GHS ${money(debt)}',
                  Icons.account_balance_wallet_outlined,
                ),
                (
                  'Low-stock products',
                  '${c.lowStockProducts.length}',
                  Icons.warning_amber_outlined,
                ),
              ])
                SizedBox(
                  width: box.maxWidth >= 900
                      ? (box.maxWidth - 36) / 4
                      : (box.maxWidth - 12) / 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metric.$1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                metric.$3,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  metric.$2,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final chart = Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales overview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Sales value in GHS • ${desktopRangeLabel(range)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 225,
                      child: RevenueBars(sales: sales, range: range),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Credit sales count once. Debt repayments are collections, not new sales.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
            final products = Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top-selling products',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (top.isEmpty) const Text('No sales in this period.'),
                    for (final entry in top.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.products
                                      .where((p) => p.code == entry.key)
                                      .firstOrNull
                                      ?.name ??
                                  entry.key,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _soldStockText(c, entry.key, entry.value),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: entry.value / top.first.value,
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
            return box.maxWidth < 900
                ? Column(
                    children: [chart, const SizedBox(height: 14), products],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: chart),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: products),
                    ],
                  );
          },
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent transactions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => widget.onNavigate('Sales'),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                if (sales.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No sales in this period.'),
                  ),
                for (final s in sales.take(6))
                  ListTile(
                    dense: true,
                    title: Text(s.receiptNumber),
                    subtitle: Text(
                      '${s.customerCompany ?? s.customerName ?? 'Walk-in customer'} • ${s.receptionistName} • ${saleDate(s.createdAt)}',
                    ),
                    trailing: Text('GHS ${money(s.totalCents)}'),
                    onTap: () => widget.onNavigate('Sales'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RevenueBars extends StatelessWidget {
  const RevenueBars({super.key, required this.sales, required this.range});
  final List<Sale> sales;
  final DateTimeRange range;
  @override
  Widget build(BuildContext context) {
    final buckets = buildRevenueBuckets(sales, range);
    final values = buckets.values;
    final count = values.length;
    final max = values.fold<int>(0, (a, b) => a > b ? a : b);
    if (max == 0) {
      return const Center(child: Text('No sales for the selected dates.'));
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Peak: GHS ${money(max)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${desktopDateLabel(buckets.starts[i])} to ${desktopDateLabel(buckets.ends[i].subtract(const Duration(microseconds: 1)))} • GHS ${money(values[i])}',
                    child: LayoutBuilder(
                      builder: (context, box) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: box.maxHeight * values[i] / max,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              desktopDateLabel(range.start),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              desktopDateLabel(range.end.subtract(const Duration(days: 1))),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
