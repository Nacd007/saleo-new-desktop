import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'workflow_pages.dart';
import 'appearance_settings.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'printer_settings.dart';
import 'sales_report.dart';
import 'session_widgets.dart';
import 'notifications_page.dart';
import 'desktop_checkout_ui.dart';

enum _PaymentChoice { cash, mobileMoneyFull, mobileMoneyPart, debt, partDebt }

class _RecordedPayment {
  const _RecordedPayment({
    required this.method,
    required this.cashCents,
    required this.mobileMoneyCents,
    required this.cashTenderedCents,
    required this.changeGivenCents,
    this.debtCents = 0,
  });

  final String method;
  final int cashCents;
  final int mobileMoneyCents;
  final int cashTenderedCents;
  final int changeGivenCents;
  final int debtCents;
}

class _PaymentChoiceTile extends StatelessWidget {
  const _PaymentChoiceTile({
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: Text(title),
    );
  }
}

class ReceptionistHome extends StatefulWidget {
  const ReceptionistHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReceptionistHome> createState() => _ReceptionistHomeState();
}

class _ReceptionistHomeState extends State<ReceptionistHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final allowReceiving = controller.inventoryPreferences.staffCanReceiveStock;
    final titles = allowReceiving
        ? ['New sale', 'Sales', 'Receive stock', 'Settings']
        : ['New sale', 'Sales', 'Settings'];
    final sideNavigation = useSideNavigation(
      context,
      controller.inventoryPreferences.navigation,
    );
    final compactTopBar = MediaQuery.sizeOf(context).width < 600;
    final pageChildren = <Widget>[
      NewSaleScreen(controller: controller),
      SalesReportPage(
        controller: controller,
        sales: controller.sales,
        onRefresh: controller.refresh,
      ),
      if (allowReceiving)
        InventoryPage(controller: controller, receiveOnly: true),
      _ReceptionistSettings(controller: controller),
    ];
    if (_index >= pageChildren.length) _index = pageChildren.length - 1;
    final pages = IndexedStack(index: _index, children: pageChildren);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titles[_index],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              controller.currentUser!.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          NotificationBell(controller: controller),
          PrinterStatusChip(controller: controller, iconOnly: compactTopBar),
          SizedBox(width: compactTopBar ? 2 : 8),
          SyncBadge(
            controller: controller,
            compact: true,
            iconOnly: compactTopBar,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') confirmSignOut(context, controller);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: sideNavigation
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      selectedIcon: Icon(Icons.point_of_sale),
                      label: Text('Sell'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('Sales'),
                    ),
                    if (allowReceiving)
                      const NavigationRailDestination(
                        icon: Icon(Icons.add_box_outlined),
                        selectedIcon: Icon(Icons.add_box),
                        label: Text('Receive'),
                      ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages),
              ],
            )
          : pages,
      bottomNavigationBar: sideNavigation
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.point_of_sale_outlined),
                  selectedIcon: Icon(Icons.point_of_sale),
                  label: 'Sell',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Sales',
                ),
                if (allowReceiving)
                  const NavigationDestination(
                    icon: Icon(Icons.add_box_outlined),
                    selectedIcon: Icon(Icons.add_box),
                    label: 'Receive',
                  ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}

class _ReceptionistSettings extends StatelessWidget {
  const _ReceptionistSettings({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Approvals & corrections'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ApprovalPage(controller: controller),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('Pending receipt printing'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Pending receipts')),
                body: PendingPrintPage(controller: controller),
              ),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text(
            'Appearance & navigation',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Light or dark mode; fixed side navigation on tablets',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AppearanceSettingsScreen(controller: controller),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text(
            'Printer & synchronization',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Connect and test a receipt printer'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PrinterSettingsScreen(controller: controller),
            ),
          ),
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Log out'),
        onTap: controller.signingOut
            ? null
            : () => confirmSignOut(context, controller),
      ),
    ],
  );
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({
    super.key,
    required this.controller,
    this.receiptHostContext,
  });

  final AppController controller;
  final BuildContext? receiptHostContext;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _search = TextEditingController();
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final categories = [
      'All',
      ...{for (final product in controller.activeProducts) product.category},
    ];
    final query = _search.text.trim().toLowerCase();
    final products = controller.activeProducts.where((product) {
      final categoryMatch = _category == 'All' || product.category == _category;
      final queryMatch =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
      return categoryMatch && queryMatch && product.forms.isNotEmpty;
    }).toList();

    final desktop = MediaQuery.sizeOf(context).width >= 1050;
    if (desktop) {
      return Row(
        children: [
          Expanded(
            flex: 8,
            child: DesktopProductGrid(
              controller: controller,
              onAdd: (product, form) => controller.addToCart(product, form, 1),
            ),
          ),
          SizedBox(
            width: (MediaQuery.sizeOf(context).width * .23).clamp(320.0, 410.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CartSheet(
                    controller: controller,
                    hostContext: widget.receiptHostContext ?? context,
                    closeSheet: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final catalogue = Stack(
      children: [
        RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search products or codes',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${products.length} products',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Tap a selling form',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: Text('No products match your search.')),
                )
              else
                ...products.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      color: product.currentStock <= 0
                          ? Theme.of(context).colorScheme.surfaceContainerHigh
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${product.code} - ${product.category}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        product.currentStock <= 0
                                            ? 'No recorded stock • sale allowed with confirmation'
                                            : '${productStockText(product, product.currentStock)} recorded',
                                        style: TextStyle(
                                          color: product.currentStock <= 0
                                              ? Colors.orange.shade800
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  backgroundImage: product.imageBytes == null
                                      ? null
                                      : MemoryImage(product.imageBytes!),
                                  child: product.imageBytes == null
                                      ? Icon(
                                          Icons.inventory_2_outlined,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: product.forms
                                  .where((form) => form.active)
                                  .map(
                                    (form) => ActionChip(
                                      onPressed: () =>
                                          _chooseQuantity(product, form),
                                      label: Text(
                                        '${form.name}  ${money(form.priceCents)}',
                                      ),
                                      avatar: const Icon(
                                        Icons.add_circle_outline,
                                        size: 18,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (controller.cart.isNotEmpty && !desktop)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: FilledButton.icon(
              onPressed: _openCart,
              icon: Badge(
                label: Text('${controller.cartItemCount}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              label: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('View current sale'),
                  Text(money(controller.cartTotalCents)),
                ],
              ),
            ),
          ),
      ],
    );
    if (!desktop) return catalogue;
    return Row(
      children: [
        Expanded(child: catalogue),
        const VerticalDivider(width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: _CartSheet(controller: controller, hostContext: context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseQuantity(Product product, SellingForm form) async {
    var quantity = 1;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${form.name} - ${money(form.priceCents)} each',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: quantity > 1
                            ? () => setSheetState(() => quantity--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          '$quantity',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        onPressed: () => setSheetState(() => quantity++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      widget.controller.addToCart(product, form, quantity);
                      Navigator.pop(context);
                    },
                    child: Text('Add - ${money(form.priceCents * quantity)}'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCart() async {
    final hostContext = widget.receiptHostContext ?? context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: _CartSheet(
          controller: widget.controller,
          hostContext: hostContext,
        ),
      ),
    );
  }
}

class _CartSheet extends StatelessWidget {
  const _CartSheet({
    required this.controller,
    required this.hostContext,
    this.closeSheet = true,
  });

  final AppController controller;
  final BuildContext hostContext;
  final bool closeSheet;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Current sale',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '${controller.cartItemCount} total items',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: controller.cart.isEmpty && !closeSheet
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 44,
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: .5),
                          ),
                          const SizedBox(height: 14),
                          const Text('Start your next sale'),
                          const SizedBox(height: 6),
                          Text(
                            'Choose a selling form and add products from the catalogue.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: controller.cart.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final line = controller.cart[index];
                        if (!closeSheet) {
                          return DesktopCartRow(
                            line: line,
                            quantityEditor: _CartQuantityEditor(
                              key: ValueKey(line.form.id),
                              quantity: line.quantity,
                              onChanged: (v) =>
                                  controller.setCartQuantity(index, v),
                            ),
                            onMinus: () => controller.setCartQuantity(
                              index,
                              line.quantity - 1,
                            ),
                            onPlus: () => controller.setCartQuantity(
                              index,
                              line.quantity + 1,
                            ),
                            onRemove: () =>
                                controller.setCartQuantity(index, 0),
                          );
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${line.product.name} - ${line.form.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${money(line.form.priceCents)} each'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => controller.setCartQuantity(
                                  index,
                                  line.quantity - 1,
                                ),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              _CartQuantityEditor(
                                key: ValueKey(line.form.id),
                                quantity: line.quantity,
                                onChanged: (quantity) =>
                                    controller.setCartQuantity(index, quantity),
                              ),
                              IconButton(
                                onPressed: () => controller.setCartQuantity(
                                  index,
                                  line.quantity + 1,
                                ),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              SizedBox(
                                width: 78,
                                child: Text(
                                  money(line.lineTotalCents),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Total price',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'GHS ${money(controller.cartTotalCents)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: controller.cart.isEmpty || controller.busy
                  ? null
                  : () => _confirmComplete(context),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Review products and payment'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _confirmComplete(BuildContext context) async {
    final reviewed = await showDialog<bool>(
      context: context,
      builder: (_) => CheckoutProductsReview(lines: List.of(controller.cart)),
    );
    if (reviewed != true || !context.mounted) return;
    final navigator = Navigator.of(hostContext);
    final messenger = ScaffoldMessenger.of(hostContext);
    var choice = _PaymentChoice.cash;
    final mobileAmount = TextEditingController();
    final debtAmount = TextEditingController();
    final partMomoAmount = TextEditingController();
    final cashReceived = TextEditingController(
      text: money(controller.cartTotalCents),
    );
    final customerName = TextEditingController();
    final customerPhone = TextEditingController();
    final customerCompany = TextEditingController();
    final customerAddress = TextEditingController();
    final collectedBy = TextEditingController();
    final collectorPhone = TextEditingController();
    CustomerRecord? selectedCustomer;
    var useExistingCustomer = true;
    var splitEntry = 'momo';
    var partPaymentSource = 'cash';
    final payment = await showDialog<_RecordedPayment>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final enteredSplitCents =
              ((double.tryParse(mobileAmount.text.trim().replaceAll(',', '')) ??
                          0) *
                      100)
                  .round();
          final splitIsValid =
              enteredSplitCents > 0 &&
              enteredSplitCents < controller.cartTotalCents;
          final enteredMobileCents = splitEntry == 'momo'
              ? enteredSplitCents
              : controller.cartTotalCents - enteredSplitCents;
          final remainingCash = controller.cartTotalCents - enteredMobileCents;
          final enteredCashCents =
              ((double.tryParse(cashReceived.text.trim().replaceAll(',', '')) ??
                          0) *
                      100)
                  .round();
          final enteredDebtCents =
              ((double.tryParse(debtAmount.text.trim().replaceAll(',', '')) ??
                          0) *
                      100)
                  .round();
          final enteredPartMomoCents =
              ((double.tryParse(
                            partMomoAmount.text.trim().replaceAll(',', ''),
                          ) ??
                          0) *
                      100)
                  .round();
          final partDebtIsValid =
              enteredDebtCents > 0 &&
              enteredDebtCents < controller.cartTotalCents;
          final partSplitIsValid =
              partPaymentSource != 'cash_momo' ||
              (enteredPartMomoCents > 0 &&
                  enteredPartMomoCents < enteredDebtCents);
          final debtRequiresCustomer =
              choice == _PaymentChoice.debt ||
              choice == _PaymentChoice.partDebt;
          final phone = customerPhone.text.trim();
          final phoneIsValid =
              phone.isEmpty ||
              (phone.length >= 3 &&
                  phone.length <= 40 &&
                  RegExp(r'\d').hasMatch(phone));
          final debtCustomerIsValid =
              !debtRequiresCustomer ||
              (customerCompany.text.trim().isNotEmpty &&
                  phone.isNotEmpty &&
                  phoneIsValid &&
                  customerAddress.text.trim().isNotEmpty);
          final collectorIsValid =
              !debtRequiresCustomer ||
              (collectedBy.text.trim().isNotEmpty &&
                  collectorPhone.text.trim().isNotEmpty);
          final existingDebt = selectedCustomer == null
              ? 0
              : controller.debtors
                    .where(
                      (debtor) =>
                          debtor.customerPhone.replaceAll(RegExp(r'\D'), '') ==
                          selectedCustomer!.phone.replaceAll(RegExp(r'\D'), ''),
                    )
                    .fold<int>(
                      0,
                      (sum, debtor) => sum + debtor.outstandingCents,
                    );
          final cashRequired = switch (choice) {
            _PaymentChoice.mobileMoneyPart => remainingCash,
            _PaymentChoice.partDebt => 0,
            _PaymentChoice.debt || _PaymentChoice.mobileMoneyFull => 0,
            _PaymentChoice.cash => controller.cartTotalCents,
          };
          final cashEntryIsValid =
              choice == _PaymentChoice.mobileMoneyFull ||
              choice == _PaymentChoice.debt ||
              choice == _PaymentChoice.partDebt ||
              choice == _PaymentChoice.mobileMoneyPart ||
              enteredCashCents >= cashRequired;
          final changeDue =
              choice == _PaymentChoice.mobileMoneyFull ||
                  choice == _PaymentChoice.debt
              ? 0
              : enteredCashCents - cashRequired;
          return AlertDialog(
            constraints: checkoutDialogConstraints(context),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('How was this sale paid?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'GHS ${money(controller.cartTotalCents)}',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (controller.inventoryPreferences.collectCustomerDetails ||
                      debtRequiresCustomer) ...[
                    const SizedBox(height: 12),
                    if (debtRequiresCustomer &&
                        controller.customers.isNotEmpty) ...[
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.people_outline),
                            label: Text(
                              debtRequiresCustomer
                                  ? 'Existing debtor'
                                  : 'Existing customer',
                            ),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: Text(
                              debtRequiresCustomer
                                  ? 'New debtor'
                                  : 'New customer',
                            ),
                          ),
                        ],
                        selected: {useExistingCustomer},
                        onSelectionChanged: (values) => setDialogState(() {
                          useExistingCustomer = values.first;
                          if (!useExistingCustomer) {
                            selectedCustomer = null;
                            customerName.clear();
                            customerPhone.clear();
                            customerCompany.clear();
                            customerAddress.clear();
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (controller.customers.isNotEmpty &&
                        (!debtRequiresCustomer || useExistingCustomer)) ...[
                      CheckoutCompanyPicker(
                        customers: controller.customers,
                        selected: selectedCustomer,
                        credit: debtRequiresCustomer,
                        onSelected: (customer) => setDialogState(() {
                          selectedCustomer = customer;
                          customerName.text = customer.name;
                          customerPhone.text = customer.phone;
                          customerCompany.text = customer.companyName;
                          customerAddress.text = customer.address;
                        }),
                      ),
                      if (selectedCustomer != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Previous owing: GHS ${money(existingDebt)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: existingDebt > 0
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF067647),
                          ),
                        ),
                        if (debtRequiresCustomer) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: customerCompany,
                            readOnly: selectedCustomer!.companyName.isNotEmpty,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Company name',
                              prefixIcon: Icon(Icons.business_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: customerPhone,
                            readOnly:
                                selectedCustomer!.phone.isNotEmpty &&
                                phoneIsValid,
                            keyboardType: TextInputType.phone,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Company phone number',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: customerAddress,
                            readOnly: selectedCustomer!.address.isNotEmpty,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Business address or location',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (!debtRequiresCustomer ||
                        !useExistingCustomer ||
                        controller.customers.isEmpty) ...[
                      if (!debtRequiresCustomer) ...[
                        TextField(
                          controller: customerName,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Customer name (optional)',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: customerPhone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: debtRequiresCustomer
                              ? 'Company phone number'
                              : 'Phone number (optional)',
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: customerCompany,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: debtRequiresCustomer
                              ? 'Company name'
                              : 'Company name (optional)',
                          prefixIcon: const Icon(Icons.business_outlined),
                        ),
                      ),
                      if (debtRequiresCustomer) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: customerAddress,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Business address or location',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                      ],
                    ],
                    if (debtRequiresCustomer) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: collectedBy,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Received by',
                          helperText:
                              'Full name of the person receiving the goods',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: collectorPhone,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Receiver phone number',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  _PaymentChoiceTile(
                    selected: choice == _PaymentChoice.cash,
                    title: 'Cash',
                    onTap: () =>
                        setDialogState(() => choice = _PaymentChoice.cash),
                  ),
                  _PaymentChoiceTile(
                    selected: choice == _PaymentChoice.mobileMoneyFull,
                    title: 'MOMO - full',
                    onTap: () => setDialogState(
                      () => choice = _PaymentChoice.mobileMoneyFull,
                    ),
                  ),
                  _PaymentChoiceTile(
                    selected: choice == _PaymentChoice.mobileMoneyPart,
                    title: 'Cash + MOMO',
                    onTap: () => setDialogState(
                      () => choice = _PaymentChoice.mobileMoneyPart,
                    ),
                  ),
                  _PaymentChoiceTile(
                    selected: choice == _PaymentChoice.debt,
                    title: 'Debt / Pay later',
                    onTap: () =>
                        setDialogState(() => choice = _PaymentChoice.debt),
                  ),
                  _PaymentChoiceTile(
                    selected: choice == _PaymentChoice.partDebt,
                    title: 'Part payment + debt',
                    onTap: () =>
                        setDialogState(() => choice = _PaymentChoice.partDebt),
                  ),
                  if (debtRequiresCustomer && !debtCustomerIsValid) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Company name, company phone and business address are required for credit sales.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!collectorIsValid) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Receiver name and phone number are required for credit sales.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (choice == _PaymentChoice.mobileMoneyPart) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: splitEntry,
                      decoration: const InputDecoration(
                        labelText: 'Amount you want to enter',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'momo',
                          child: Text('MOMO amount'),
                        ),
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('Cash amount'),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        splitEntry = value ?? 'momo';
                        mobileAmount.clear();
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mobileAmount,
                      autofocus: true,
                      inputFormatters: const [_MoneyInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: splitEntry == 'momo'
                            ? 'MOMO amount'
                            : 'Cash amount',
                        prefixText: 'GHS ',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      splitIsValid
                          ? splitEntry == 'momo'
                                ? 'Cash balance: GHS ${money(remainingCash)}'
                                : 'MOMO balance: GHS ${money(enteredMobileCents)}'
                          : 'Enter an amount below the sale total.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: splitIsValid
                            ? const Color(0xFF067647)
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (choice == _PaymentChoice.partDebt) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: debtAmount,
                      autofocus: true,
                      inputFormatters: const [_MoneyInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount paid now',
                        prefixText: 'GHS ',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      partDebtIsValid
                          ? 'New debt from this sale: GHS ${money(controller.cartTotalCents - enteredDebtCents)}'
                          : 'Enter the amount being paid below the sale total.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: partDebtIsValid
                            ? const Color(0xFF067647)
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: partPaymentSource,
                      decoration: const InputDecoration(
                        labelText: 'How is the part payment being paid?',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'momo', child: Text('MOMO')),
                        DropdownMenuItem(
                          value: 'cash_momo',
                          child: Text('Cash + MOMO'),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        partPaymentSource = value ?? 'cash';
                        partMomoAmount.clear();
                      }),
                    ),
                    if (partPaymentSource == 'cash_momo') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: partMomoAmount,
                        inputFormatters: const [_MoneyInputFormatter()],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'MOMO amount from payment',
                          prefixText: 'GHS ',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        partSplitIsValid
                            ? 'Cash amount: GHS ${money(enteredDebtCents - enteredPartMomoCents)}'
                            : 'MOMO must be below the amount paid now.',
                      ),
                    ],
                  ],
                  if (choice == _PaymentChoice.cash) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: cashReceived,
                      inputFormatters: const [_MoneyInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cash received',
                        prefixText: 'GHS ',
                        helperText: 'Cash required: GHS ${money(cashRequired)}',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Change to customer',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              cashEntryIsValid
                                  ? 'GHS ${money(changeDue)}'
                                  : 'Enter enough cash',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cashEntryIsValid
                                    ? null
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    (choice == _PaymentChoice.mobileMoneyPart &&
                            !splitIsValid) ||
                        (choice == _PaymentChoice.partDebt &&
                            (!partDebtIsValid || !partSplitIsValid)) ||
                        !debtCustomerIsValid ||
                        !phoneIsValid ||
                        !collectorIsValid ||
                        !cashEntryIsValid
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        final total = controller.cartTotalCents;
                        final recorded = switch (choice) {
                          _PaymentChoice.cash => _RecordedPayment(
                            method: 'cash',
                            cashCents: total,
                            mobileMoneyCents: 0,
                            cashTenderedCents: enteredCashCents,
                            changeGivenCents: changeDue,
                          ),
                          _PaymentChoice.mobileMoneyFull => _RecordedPayment(
                            method: 'mobile_money_full',
                            cashCents: 0,
                            mobileMoneyCents: total,
                            cashTenderedCents: 0,
                            changeGivenCents: 0,
                          ),
                          _PaymentChoice.mobileMoneyPart => _RecordedPayment(
                            method: 'mobile_money_part',
                            cashCents: remainingCash,
                            mobileMoneyCents: enteredMobileCents,
                            cashTenderedCents: remainingCash,
                            changeGivenCents: 0,
                          ),
                          _PaymentChoice.debt => _RecordedPayment(
                            method: 'debt',
                            cashCents: 0,
                            mobileMoneyCents: 0,
                            cashTenderedCents: 0,
                            changeGivenCents: 0,
                            debtCents: total,
                          ),
                          _PaymentChoice.partDebt => _RecordedPayment(
                            method: 'part_payment_debt',
                            cashCents: partPaymentSource == 'momo'
                                ? 0
                                : partPaymentSource == 'cash_momo'
                                ? enteredDebtCents - enteredPartMomoCents
                                : enteredDebtCents,
                            mobileMoneyCents: partPaymentSource == 'momo'
                                ? enteredDebtCents
                                : partPaymentSource == 'cash_momo'
                                ? enteredPartMomoCents
                                : 0,
                            cashTenderedCents: partPaymentSource == 'momo'
                                ? 0
                                : partPaymentSource == 'cash_momo'
                                ? enteredDebtCents - enteredPartMomoCents
                                : enteredDebtCents,
                            changeGivenCents: 0,
                            debtCents: total - enteredDebtCents,
                          ),
                        };
                        final confirmedPayment = await showDialog<bool>(
                          context: context,
                          builder: (reviewContext) => AlertDialog(
                            constraints: checkoutDialogConstraints(
                              reviewContext,
                            ),
                            icon: Icon(
                              Icons.verified_outlined,
                              color: Theme.of(reviewContext)
                                  .colorScheme
                                  .primary,
                            ),
                            title: const Text('Confirm payment received'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckoutSummaryRow(
                                    label: 'Sale total',
                                    value: 'GHS ${money(total)}',
                                    emphasized: true,
                                  ),
                                  const SizedBox(height: 8),
                                  CheckoutSummaryRow(
                                    label: 'Cash received',
                                    value:
                                        'GHS ${money(recorded.cashTenderedCents)}',
                                  ),
                                  CheckoutSummaryRow(
                                    label: 'MOMO received',
                                    value:
                                        'GHS ${money(recorded.mobileMoneyCents)}',
                                  ),
                                  if (recorded.changeGivenCents > 0)
                                    CheckoutSummaryRow(
                                      label: 'Change',
                                      value:
                                          'GHS ${money(recorded.changeGivenCents)}',
                                    ),
                                  if (recorded.debtCents > 0) ...[
                                    const Divider(),
                                    CheckoutSummaryRow(
                                      label: 'Previous balance',
                                      value: 'GHS ${money(existingDebt)}',
                                    ),
                                    CheckoutSummaryRow(
                                      label: 'Credit from this sale',
                                      value: 'GHS ${money(recorded.debtCents)}',
                                    ),
                                    CheckoutSummaryRow(
                                      label: 'Total balance due',
                                      value:
                                          'GHS ${money(existingDebt + recorded.debtCents)}',
                                      emphasized: true,
                                    ),
                                    CheckoutSummaryRow(
                                      label: 'Company',
                                      value: customerCompany.text.trim(),
                                    ),
                                    CheckoutSummaryRow(
                                      label: 'Received by',
                                      value:
                                          '${collectedBy.text.trim()} · ${collectorPhone.text.trim()}',
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Text(
                                    recorded.debtCents == total
                                        ? 'Confirm this credit sale. No payment was received.'
                                        : 'Confirm that you actually received the amounts shown above.',
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(reviewContext, false),
                                child: const Text('Edit payment'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(reviewContext, true),
                                child: const Text('Confirm & finalize'),
                              ),
                            ],
                          ),
                        );
                        if (confirmedPayment == true && context.mounted) {
                          Navigator.pop(context, recorded);
                        }
                      },
                child: const Text('Complete sale'),
              ),
            ],
          );
        },
      ),
    );
    if (payment == null || !context.mounted) return;
    final savedCustomerCompany = customerCompany.text.trim();
    final savedCustomerName = payment.debtCents > 0
        ? savedCustomerCompany
        : customerName.text.trim();
    final savedCustomerPhone = customerPhone.text.trim();
    final savedCustomerAddress = customerAddress.text.trim();
    final savedCollectedBy = collectedBy.text.trim();
    final savedCollectorPhone = collectorPhone.text.trim();
    final shortages = await controller.getCartStockShortages();
    if (!context.mounted) return;
    if (shortages.isNotEmpty) {
      final sellAnyway =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.inventory_2_outlined),
              title: const Text('Recorded stock is too low'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saleo has less recorded stock than this sale needs:',
                    ),
                    const SizedBox(height: 12),
                    ...shortages.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• ${item.product.name}: ${item.availableBase} '
                          '${item.product.baseUnit}${item.availableBase == 1 ? '' : 's'} '
                          'recorded, ${item.requiredBase} needed',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'If you can physically see the stock, you may continue. '
                      'The administrator will receive a stock-discrepancy alert.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Return to sale'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm stock & sell'),
                ),
              ],
            ),
          ) ??
          false;
      if (!sellAnyway || !context.mounted) return;
    }
    Sale? sale;
    try {
      sale = await controller.completeSale(
        paymentMethod: payment.method,
        cashCents: payment.cashCents,
        mobileMoneyCents: payment.mobileMoneyCents,
        cashTenderedCents: payment.cashTenderedCents,
        changeGivenCents: payment.changeGivenCents,
        debtCents: payment.debtCents,
        customerName: savedCustomerName,
        customerPhone: savedCustomerPhone,
        customerCompany: savedCustomerCompany,
        customerAddress: savedCustomerAddress,
        collectedBy: savedCollectedBy,
        collectorPhone: savedCollectorPhone,
        allowStockOverride: shortages.isNotEmpty,
      );
    } catch (_) {
      if (!hostContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The sale could not be saved. Please check stock and try again.',
          ),
        ),
      );
      return;
    }
    if (!hostContext.mounted || sale == null) return;
    if (closeSheet) navigator.pop();
    await showReceipt(hostContext, sale, controller: controller);
  }
}

class _MoneyInputFormatter extends TextInputFormatter {
  const _MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (!RegExp(r'^\d*(?:\.\d{0,2})?$').hasMatch(raw)) return oldValue;
    if (raw.isEmpty) return newValue;

    final parts = raw.split('.');
    final integerText = parts.first.isEmpty ? '0' : parts.first;
    final integer = int.tryParse(integerText) ?? 0;
    final grouped = integer.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    final formatted = parts.length == 2 ? '$grouped.${parts[1]}' : grouped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CartQuantityEditor extends StatefulWidget {
  const _CartQuantityEditor({
    super.key,
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  State<_CartQuantityEditor> createState() => _CartQuantityEditorState();
}

class _CartQuantityEditorState extends State<_CartQuantityEditor> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.quantity}');
  }

  @override
  void didUpdateWidget(covariant _CartQuantityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.quantity != widget.quantity) {
      _controller.text = '${widget.quantity}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      ),
      onChanged: (value) {
        final quantity = int.tryParse(value);
        if (quantity != null) widget.onChanged(quantity);
      },
    ),
  );
}
