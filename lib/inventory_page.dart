import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'formatters.dart';
import 'inventory_export_service.dart';
import 'models.dart';
import 'profit_calculator.dart';
import 'stock_receipt_export_service.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.controller,
    this.initialProductId,
    this.receiveOnly = false,
  });

  final AppController controller;
  final int? initialProductId;
  final bool receiveOnly;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _DiscrepancyPanel extends StatelessWidget {
  const _DiscrepancyPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final unresolved = controller.stockDiscrepancies
        .where((item) => !item.isResolved)
        .toList();
    return Card(
      color: Theme.of(context).colorScheme.errorContainer
          .withValues(alpha: .35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unresolved stock discrepancies',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'These are kept separate from physical stock. Receiving new goods will not deduct them.',
            ),
            const SizedBox(height: 8),
            ...unresolved.map((item) {
              final product = controller.products
                  .where((product) => product.id == item.productId)
                  .firstOrNull;
              return Dismissible(
                key: ValueKey('stock-discrepancy-${item.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  color: Theme.of(context).colorScheme.error,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  await controller.resolveStockDiscrepancy(
                    item,
                    'Cleared by administrator',
                  );
                  return true;
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(
                    product?.name ?? 'Product ${item.productId}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Unresolved discrepancy: ${_formatStock(product ?? _fallbackProduct(item.productId), item.quantityBase)}\n'
                    '${item.createdBy} • ${_shortDate(item.createdAt)}',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => _resolve(context, item),
                    child: const Text('Clear'),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    StockDiscrepancy discrepancy,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear discrepancy?'),
            content: const Text(
              'The alert will be cleared, but Saleo will keep the original discrepancy and this action in the audit history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear alert'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await controller.resolveStockDiscrepancy(
      discrepancy,
      'Cleared by administrator',
    );
  }
}

class _RecentReceivedPanel extends StatelessWidget {
  const _RecentReceivedPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final today = controller.stockReceipts
        .where(
          (receipt) =>
              receipt.status == StockReceiptStatus.confirmed &&
              _sameDay(
                receipt.confirmedAt ?? receipt.createdAt,
                DateTime.now(),
              ),
        )
        .take(5)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recently received today',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            ...today.expand(
              (receipt) => receipt.items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_box_outlined),
                  title: Text(item.productName),
                  subtitle: Text(
                    '${item.quantityForms} ${item.formName} • ${receipt.supplierName ?? 'No supplier'}',
                  ),
                  trailing: Text(
                    '+${item.quantityBase}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveStockView extends StatefulWidget {
  const _ReceiveStockView({required this.controller});

  final AppController controller;

  @override
  State<_ReceiveStockView> createState() => _ReceiveStockViewState();
}

class _ReceiveStockViewState extends State<_ReceiveStockView> {
  final _supplier = TextEditingController();
  final _invoice = TextEditingController();
  final List<StockReceiptDraftItem> _items = [];
  bool _saving = false;

  @override
  void dispose() {
    _supplier.dispose();
    _invoice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.controller.currentUser?.role == UserRole.admin;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text(
          'New delivery',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select the products received. Edit any line before reviewing and confirming the delivery.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _supplier,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Supplier (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _invoice,
                  decoration: const InputDecoration(
                    labelText: 'Invoice number (optional)',
                    helperText: 'Duplicate invoice numbers are blocked.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ..._items.indexed.map((entry) {
          final index = entry.$1;
          final item = entry.$2;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                item.product.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${item.quantityForms} ${item.form.name} × ${item.form.unitsPerForm} ${item.product.baseUnit}'
                '${!isAdmin || item.purchaseCostCents == null ? '' : '\nCost: GHS ${money(item.purchaseCostCents!)} each'}'
                '${item.batchNumber?.isEmpty ?? true ? '' : ' • Batch ${item.batchNumber}'}',
              ),
              onTap: _saving ? null : () => _addItem(editIndex: index),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit item',
                    onPressed: _saving
                        ? null
                        : () => _addItem(editIndex: index),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _items.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving || widget.controller.products.isEmpty
              ? null
              : _addItem,
          icon: const Icon(Icons.add),
          label: const Text('Add product to delivery'),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              title: const Text(
                'Delivery total',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${_items.length} product lines'),
              trailing: Text(
                '${_items.fold<int>(0, (sum, item) => sum + item.quantityBase)} base units',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(confirm: false),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _reviewAndConfirm(),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Review & confirm'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _addItem({int? editIndex}) async {
    final existing = editIndex == null ? null : _items[editIndex];
    Product selectedProduct =
        existing?.product ??
        widget.controller.products
            .where((product) => product.active)
            .firstOrNull ??
        widget.controller.products.first;
    SellingForm? selectedForm =
        existing?.form ??
        selectedProduct.forms.where((form) => form.active).firstOrNull;
    final quantity = TextEditingController(
      text: '${existing?.quantityForms ?? 1}',
    );
    final cost = TextEditingController(
      text: existing?.purchaseCostCents == null
          ? ''
          : money(existing!.purchaseCostCents!),
    );
    final batch = TextEditingController(text: existing?.batchNumber ?? '');
    final search = TextEditingController();
    final searchFocus = FocusNode();
    searchFocus.addListener(() {
      if (searchFocus.hasFocus) search.clear();
    });
    DateTime? expiry = existing?.expiryDate;
    TransitionRoute<dynamic>? productDialog;
    final added =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              productDialog =
                  ModalRoute.of(context) as TransitionRoute<dynamic>?;
              return AlertDialog(
                title: Text(
                  existing == null
                      ? 'Add received product'
                      : 'Edit received product',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownMenu<Product>(
                        controller: search,
                        focusNode: searchFocus,
                        initialSelection: selectedProduct,
                        expandedInsets: EdgeInsets.zero,
                        enableFilter: true,
                        enableSearch: true,
                        requestFocusOnTap: true,
                        leadingIcon: IconButton(
                          tooltip: 'Search products',
                          onPressed: () {
                            search.clear();
                            searchFocus.requestFocus();
                          },
                          icon: const Icon(Icons.search),
                        ),
                        label: const Text('Search product'),
                        helperText: 'Search by product name, code or category',
                        dropdownMenuEntries: widget.controller.products
                            .where((product) => product.active)
                            .map(
                              (product) => DropdownMenuEntry(
                                value: product,
                                label:
                                    '${product.name} · ${product.code} · ${product.category}',
                              ),
                            )
                            .toList(),
                        filterCallback: (entries, query) {
                          final value = query.trim().toLowerCase();
                          if (value.isEmpty) return entries;
                          return entries
                              .where(
                                (entry) =>
                                    entry.label.toLowerCase().contains(value),
                              )
                              .toList();
                        },
                        onSelected: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            selectedProduct = value;
                            selectedForm = value.forms
                                .where((form) => form.active)
                                .firstOrNull;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<SellingForm>(
                        key: ValueKey(selectedProduct.id),
                        initialValue: selectedForm,
                        decoration: const InputDecoration(
                          labelText: 'Form received',
                        ),
                        items: selectedProduct.forms
                            .where((form) => form.active)
                            .map(
                              (form) => DropdownMenuItem(
                                value: form,
                                child: Text(
                                  '${form.name} (${form.unitsPerForm} ${selectedProduct.baseUnit})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedForm = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final current = int.tryParse(quantity.text) ?? 1;
                              if (current > 1) quantity.text = '${current - 1}';
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Expanded(
                            child: TextField(
                              controller: quantity,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'Quantity of forms',
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              final current = int.tryParse(quantity.text) ?? 0;
                              quantity.text = '${current + 1}';
                            },
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.controller.currentUser?.role == UserRole.admin)
                        TextField(
                          controller: cost,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText:
                                'Purchase cost per received form (optional)',
                            prefixText: 'GHS ',
                            helperText: 'For example, cost of one crate. Blank means unknown.',
                            helperMaxLines: 2,
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: batch,
                        decoration: const InputDecoration(
                          labelText: 'Batch number (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: Text(
                          expiry == null
                              ? 'Expiry date (optional)'
                              : '${expiry!.day}/${expiry!.month}/${expiry!.year}',
                        ),
                        trailing: expiry == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                onPressed: () =>
                                    setDialogState(() => expiry = null),
                                icon: const Icon(Icons.close),
                              ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(DateTime.now().year + 20),
                          );
                          if (date != null) setDialogState(() => expiry = date);
                        },
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
                    onPressed: () {
                      if (widget.controller.currentUser?.role ==
                              UserRole.admin &&
                          cost.text.trim().isNotEmpty &&
                          parseProfitMoney(cost.text) == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a valid purchase cost, such as 150.00 or 1,500.00.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: Text(existing == null ? 'Add' : 'Save changes'),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;
    final count = int.tryParse(quantity.text.trim());
    final parsedCost = parseProfitMoney(cost.text);
    final form = selectedForm;
    final batchValue = batch.text.trim();
    await productDialog?.completed;
    quantity.dispose();
    cost.dispose();
    batch.dispose();
    search.dispose();
    searchFocus.dispose();
    if (!mounted || !added || count == null || count <= 0 || form == null) {
      return;
    }
    setState(() {
      final updated = StockReceiptDraftItem(
        product: selectedProduct,
        form: form,
        quantityForms: count,
        purchaseCostCents: parsedCost,
        batchNumber: batchValue,
        expiryDate: expiry,
      );
      if (editIndex == null) {
        _items.add(updated);
      } else {
        _items[editIndex] = updated;
      }
    });
  }

  Future<void> _reviewAndConfirm() async {
    final isAdmin = widget.controller.currentUser?.role == UserRole.admin;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              isAdmin ? 'Review received stock' : 'Submit stock for approval?',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supplier: ${_supplier.text.trim().isEmpty ? 'Not entered' : _supplier.text.trim()}',
                  ),
                  Text(
                    'Invoice: ${_invoice.text.trim().isEmpty ? 'Not entered' : _invoice.text.trim()}',
                  ),
                  const Divider(height: 24),
                  ..._items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${item.product.name}: ${item.quantityForms} ${item.form.name} = ${item.quantityBase} ${item.product.baseUnit}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAdmin
                        ? 'Your confirmed delivery will be posted without an approval request.'
                        : 'An admin must approve this delivery before it updates inventory.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(isAdmin ? 'Continue' : 'Submit for approval'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    if (isAdmin) {
      final finalConfirmation = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add this delivery to inventory?'),
          content: const Text(
            'Confirm that the products, forms and quantities match the goods actually received. This will update stock when synchronized.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm delivery'),
            ),
          ],
        ),
      );
      if (finalConfirmation != true || !mounted) return;
    }
    await _save(confirm: true);
  }

  Future<void> _save({required bool confirm}) async {
    setState(() => _saving = true);
    try {
      await widget.controller.receiveStock(
        items: List.unmodifiable(_items),
        supplierName: _supplier.text,
        invoiceNumber: _invoice.text,
        confirm: confirm,
      );
      if (!mounted) return;
      setState(() {
        _items.clear();
        _supplier.clear();
        _invoice.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !confirm
                ? 'Delivery draft saved.'
                : widget.controller.currentUser?.role == UserRole.admin
                ? 'Delivery confirmed; stock will be posted on synchronization.'
                : 'Delivery submitted for admin approval.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReceivingHistoryView extends StatefulWidget {
  const _ReceivingHistoryView({required this.controller});

  final AppController controller;

  @override
  State<_ReceivingHistoryView> createState() => _ReceivingHistoryViewState();
}

class _ReceivingHistoryViewState extends State<_ReceivingHistoryView> {
  ProductPerformancePeriod _period = ProductPerformancePeriod.today;

  @override
  Widget build(BuildContext context) {
    final start = _receiptPeriodStart(_period);
    final receipts = widget.controller.stockReceipts
        .where((receipt) => !receipt.createdAt.toLocal().isBefore(start))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProductPerformancePeriod.values
              .map(
                (period) => ChoiceChip(
                  label: Text(_receiptPeriodLabel(period)),
                  selected: period == _period,
                  onSelected: (_) => setState(() => _period = period),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: receipts.isEmpty
                  ? null
                  : () => _export(context, receipts, excel: false),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Export CSV'),
            ),
            OutlinedButton.icon(
              onPressed: receipts.isEmpty
                  ? null
                  : () => _export(context, receipts, excel: true),
              icon: const Icon(Icons.grid_on_outlined),
              label: const Text('Export Excel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (receipts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No received-stock records in this period.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...receipts.map(
            (receipt) => Card(
              child: ExpansionTile(
                leading: Icon(
                  receipt.status == StockReceiptStatus.confirmed
                      ? Icons.check_circle_outline
                      : receipt.status == StockReceiptStatus.reversed
                      ? Icons.undo
                      : Icons.edit_note_outlined,
                ),
                title: Text(
                  receipt.invoiceNumber?.isNotEmpty == true
                      ? 'Invoice ${receipt.invoiceNumber}'
                      : 'Delivery ${receipt.receiptUuid.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${receipt.supplierName ?? 'No supplier'} • ${_shortDate(receipt.createdAt)}\n'
                  '${receipt.status.name.toUpperCase()} • ${receipt.items.length} lines • ${receipt.totalUnits} units',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  ...receipt.items.map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.productName),
                      subtitle: Text('${item.quantityForms} ${item.formName}'),
                      trailing: Text('${item.quantityBase} units'),
                    ),
                  ),
                  if (receipt.status == StockReceiptStatus.draft &&
                      !widget.controller.workflows.any(
                        (w) => w['uuid'] == receipt.receiptUuid,
                      ))
                    FilledButton.icon(
                      onPressed: () => _submitDraft(receipt),
                      icon: const Icon(Icons.check),
                      label: const Text('Submit for verification'),
                    ),
                  if (receipt.status == StockReceiptStatus.confirmed)
                    OutlinedButton.icon(
                      onPressed: () => _reverse(context, receipt),
                      icon: const Icon(Icons.undo),
                      label: const Text('Reverse with reason'),
                    ),
                  if (receipt.status == StockReceiptStatus.reversed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Reversal reason: ${receipt.reversalReason ?? 'Not entered'}',
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _submitDraft(StockReceipt receipt) async {
    final isAdmin = widget.controller.currentUser?.role == UserRole.admin;
    final reviewed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review saved delivery'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...receipt.items.map(
                (item) => Text(
                  '${item.productName}: ${item.quantityForms} ${item.formName}',
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
            child: Text(isAdmin ? 'Continue' : 'Submit for approval'),
          ),
        ],
      ),
    );
    if (reviewed != true || !mounted) return;
    if (isAdmin) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm delivery'),
          content: const Text(
            'Confirm these quantities match the goods received. The server will add this delivery to inventory without a separate approval request.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add to inventory'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await widget.controller.submitStockForApproval(receipt);
  }

  Future<void> _reverse(BuildContext context, StockReceipt receipt) async {
    final reason = TextEditingController();
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reverse this delivery?'),
            content: TextField(
              controller: reason,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Required reason'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reverse'),
              ),
            ],
          ),
        ) ??
        false;
    final value = reason.text.trim();
    reason.dispose();
    if (!confirmed || value.isEmpty) return;
    try {
      await widget.controller.reverseStockReceipt(receipt, value);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _export(
    BuildContext context,
    List<StockReceipt> receipts, {
    required bool excel,
  }) async {
    final result = excel
        ? await const StockReceiptExportService().saveExcel(receipts)
        : await const StockReceiptExportService().saveCsv(receipts);
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Receiving history saved to $result')),
    );
  }
}

class _InventoryPageState extends State<InventoryPage> {
  final _search = TextEditingController();
  String _stockStatus = 'all';
  DateTime? _customStart;
  DateTime? _customEnd;
  late int? _focusedProductId;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    _focusedProductId = widget.initialProductId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (widget.receiveOnly) {
        return _ReceiveStockView(controller: controller);
      }
      final period = controller.inventoryPreferences.defaultPeriod;
      final range = _customStart != null && _customEnd != null
          ? (start: _customStart!, end: _customEnd!)
          : _periodRange(period, controller.inventoryPreferences.weekStartsOn);
      final query = _search.text.trim().toLowerCase();
      final products = controller.products.where((product) {
        final matchesSearch =
            query.isEmpty ||
            product.name.toLowerCase().contains(query) ||
            product.code.toLowerCase().contains(query) ||
            product.category.toLowerCase().contains(query);
        final matchesStatus = switch (_stockStatus) {
          'available' => product.currentStock > 0 && !product.isLowStock,
          'low' => product.isLowStock,
          'out' => product.currentStock <= 0,
          _ => true,
        };
        final matchesFocus =
            _focusedProductId == null || product.id == _focusedProductId;
        return matchesSearch && matchesStatus && matchesFocus;
      }).toList()..sort(_productSort);
      final overview = RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) =>
                          setState(() => _focusedProductId = null),
                      decoration: InputDecoration(
                        labelText: 'Find inventory',
                        hintText: 'Product, code or category',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: InventoryPeriod.values
                            .map(
                              (value) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(value.label),
                                  selected:
                                      _customStart == null && period == value,
                                  onSelected: (_) {
                                    setState(() {
                                      _customStart = null;
                                      _customEnd = null;
                                    });
                                    controller.saveInventoryPreferences(
                                      controller.inventoryPreferences.copyWith(
                                        defaultPeriod: value,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _stockStatus,
                            decoration: const InputDecoration(
                              labelText: 'Stock status',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All stock'),
                              ),
                              DropdownMenuItem(
                                value: 'available',
                                child: Text('Available'),
                              ),
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Low stock'),
                              ),
                              DropdownMenuItem(
                                value: 'out',
                                child: Text('Out of stock'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _stockStatus = value ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _pickDateAndTime,
                          icon: const Icon(Icons.date_range_outlined),
                          label: const Text('Date & time'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: products.isEmpty
                              ? null
                              : () => _exportInventory(context, products),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Export inventory'),
                        ),
                      ],
                    ),
                    if (_customStart != null && _customEnd != null) ...[
                      const SizedBox(height: 10),
                      InputChip(
                        avatar: const Icon(Icons.schedule, size: 18),
                        label: Text(_customRangeDescription(range)),
                        onDeleted: () => setState(() {
                          _customStart = null;
                          _customEnd = null;
                        }),
                      ),
                    ],
                    if (_focusedProductId != null) ...[
                      const SizedBox(height: 10),
                      InputChip(
                        avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                        label: const Text('Showing selected product'),
                        onDeleted: () =>
                            setState(() => _focusedProductId = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _customStart == null
                  ? _periodDescription(period, range)
                  : _customRangeDescription(range),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryCard(
                  label: 'Products shown',
                  value: '${products.length}',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.teal,
                ),
                _SummaryCard(
                  label: 'Low stock',
                  value: '${controller.lowStockProducts.length}',
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                _SummaryCard(
                  label: 'Unread alerts',
                  value: '${controller.unreadNotificationCount}',
                  icon: Icons.notifications_none,
                  color: Colors.indigo,
                ),
              ],
            ),
            if (controller.stockDiscrepancies.any(
              (item) => !item.isResolved,
            )) ...[
              const SizedBox(height: 18),
              _DiscrepancyPanel(controller: controller),
            ],
            if (controller.stockReceipts.any(
              (receipt) =>
                  receipt.status == StockReceiptStatus.confirmed &&
                  _sameDay(
                    receipt.confirmedAt ?? receipt.createdAt,
                    DateTime.now(),
                  ),
            )) ...[
              const SizedBox(height: 18),
              _RecentReceivedPanel(controller: controller),
            ],
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Text(
                  'Stock by product',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                SegmentedButton<InventoryViewMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: InventoryViewMode.cards,
                      icon: Icon(Icons.view_agenda_outlined),
                      label: Text('Cards'),
                    ),
                    ButtonSegment(
                      value: InventoryViewMode.table,
                      icon: Icon(Icons.table_rows_outlined),
                      label: Text('Table'),
                    ),
                  ],
                  selected: {controller.inventoryPreferences.inventoryView},
                  onSelectionChanged: (value) =>
                      controller.saveInventoryPreferences(
                        controller.inventoryPreferences.copyWith(
                          inventoryView: value.first,
                        ),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Opening and closing stock use each product’s smallest sellable unit.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (products.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Add a product to begin tracking inventory.'),
                ),
              )
            else if (controller.inventoryPreferences.inventoryView ==
                InventoryViewMode.table)
              _InventoryTable(
                controller: controller,
                products: products,
                range: range,
              )
            else
              ...products.map(
                (product) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProductInventoryCard(
                    controller: controller,
                    product: product,
                    range: range,
                  ),
                ),
              ),
          ],
        ),
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.dashboard_outlined),
                    label: Text('Overview'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.add_box_outlined),
                    label: Text('Receive stock'),
                  ),
                  ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.history),
                    label: Text('Receiving history'),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (value) =>
                    setState(() => _section = value.first),
              ),
            ),
          ),
          Expanded(
            child: switch (_section) {
              1 => _ReceiveStockView(controller: controller),
              2 => _ReceivingHistoryView(controller: controller),
              _ => overview,
            },
          ),
        ],
      );
    },
  );

  Future<void> _pickDateAndTime() async {
    final now = DateTime.now();
    final initialStart = _customStart ?? DateTime(now.year, now.month, now.day);
    final initialEnd = (_customEnd ?? now).subtract(
      _customEnd == null ? Duration.zero : const Duration(minutes: 1),
    );
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (dates == null || !mounted) return;
    final startTime = await showTimePicker(
      context: context,
      helpText: 'START TIME',
      initialTime: TimeOfDay.fromDateTime(_customStart ?? dates.start),
    );
    if (startTime == null || !mounted) return;
    final endTime = await showTimePicker(
      context: context,
      helpText: 'END TIME',
      initialTime: TimeOfDay.fromDateTime(
        _customEnd?.subtract(const Duration(minutes: 1)) ??
            DateTime(dates.end.year, dates.end.month, dates.end.day, 23, 59),
      ),
    );
    if (endTime == null || !mounted) return;
    final start = DateTime(
      dates.start.year,
      dates.start.month,
      dates.start.day,
      startTime.hour,
      startTime.minute,
    );
    final end = DateTime(
      dates.end.year,
      dates.end.month,
      dates.end.day,
      endTime.hour,
      endTime.minute,
    ).add(const Duration(minutes: 1));
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date and time must be after start.')),
      );
      return;
    }
    setState(() {
      _customStart = start;
      _customEnd = end;
    });
  }

  Future<void> _exportInventory(
    BuildContext context,
    List<Product> products,
  ) async {
    final result = await const InventoryExportService().saveExcel(products);
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Inventory export saved to $result')),
    );
  }
}

int _productSort(Product left, Product right) {
  if (left.active != right.active) return left.active ? -1 : 1;
  final category = left.category.toLowerCase().compareTo(
    right.category.toLowerCase(),
  );
  if (category != 0) return category;
  return left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

class _ProductInventoryCard extends StatelessWidget {
  const _ProductInventoryCard({
    required this.controller,
    required this.product,
    required this.range,
  });

  final AppController controller;
  final Product product;
  final ({DateTime start, DateTime end}) range;

  @override
  Widget build(BuildContext context) {
    final snapshot = _inventorySnapshot(controller, product, range);
    final color = product.currentStock < 0
        ? Colors.red
        : product.isLowStock
        ? Colors.orange
        : Colors.green;
    final status = product.currentStock < 0
        ? 'Count needs attention'
        : product.isLowStock
        ? 'Low stock'
        : 'In stock';
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(Icons.inventory_2_outlined, color: color),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_formatStock(product, product.currentStock)} • $status',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _StockLine(
            label: 'Opening stock',
            value: _formatStock(product, snapshot.opening),
          ),
          _StockLine(
            label: 'Stock received',
            value: _formatStock(product, snapshot.received),
          ),
          _StockLine(
            label: 'Quantity sold',
            value: _formatStock(product, snapshot.sold),
          ),
          if (snapshot.damaged != 0)
            _StockLine(
              label: 'Damaged or lost',
              value: _formatStock(product, snapshot.damaged),
            ),
          if (snapshot.corrections != 0)
            _StockLine(
              label: 'Corrections',
              value: _formatStock(product, snapshot.corrections),
            ),
          _StockLine(
            label: 'Current closing stock',
            value: _formatStock(product, snapshot.closing),
            strong: true,
          ),
          if (product.lowStockThreshold > 0)
            _StockLine(
              label: 'Low-stock alert',
              value: _formatStock(product, product.lowStockThreshold),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _adjustStock(context),
                icon: const Icon(Icons.sync_alt),
                label: const Text('Adjust stock'),
              ),
              OutlinedButton.icon(
                onPressed: () => _configure(context),
                icon: const Icon(Icons.tune),
                label: const Text('Stock settings'),
              ),
              OutlinedButton.icon(
                onPressed: () => _physicalCount(context),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Physical count'),
              ),
            ],
          ),
          if (snapshot.inPeriod.isNotEmpty) ...[
            const Divider(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Movement in selected period',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ...snapshot.inPeriod
                .take(4)
                .map(
                  (movement) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      movement.quantityBase >= 0
                          ? Icons.add_circle
                          : Icons.remove_circle,
                      color: movement.quantityBase >= 0
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text(_movementLabel(movement.type)),
                    subtitle: Text(
                      '${movement.actorName} • ${_shortDate(movement.createdAt)}'
                      '${movement.note == null ? '' : '\n${movement.note}'}',
                    ),
                    trailing: Text(
                      '${movement.quantityBase > 0 ? '+' : ''}'
                      '${_formatStock(product, movement.quantityBase)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Future<void> _adjustStock(BuildContext context) async {
    final quantity = TextEditingController();
    final note = TextEditingController();
    var type = 'restock';
    final activeForms = product.forms.where((form) => form.active).toList();
    SellingForm? selected = activeForms.isEmpty ? null : activeForms.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Adjust ${product.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(
                      value: 'restock',
                      child: Text('Stock received'),
                    ),
                    DropdownMenuItem(
                      value: 'return',
                      child: Text('Customer return'),
                    ),
                    DropdownMenuItem(
                      value: 'damaged',
                      child: Text('Damaged or lost'),
                    ),
                    DropdownMenuItem(
                      value: 'correction_add',
                      child: Text('Count correction - add'),
                    ),
                    DropdownMenuItem(
                      value: 'correction_remove',
                      child: Text('Count correction - remove'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
                const SizedBox(height: 12),
                if (product.forms.isNotEmpty)
                  DropdownButtonFormField<SellingForm>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'Selling form',
                    ),
                    items: product.forms
                        .where((form) => form.active)
                        .map(
                          (form) => DropdownMenuItem(
                            value: form,
                            child: Text(
                              form.unitsPerForm == 1
                                  ? form.name
                                  : '${form.name} (${form.unitsPerForm} ${_plural(product.baseUnit, form.unitsPerForm)})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selected = value),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText:
                        'Optional for deliveries; recommended for corrections',
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
              child: const Text('Save movement'),
            ),
          ],
        ),
      ),
    );
    final count = int.tryParse(quantity.text.trim());
    final form = selected;
    quantity.dispose();
    final savedNote = note.text.trim();
    note.dispose();
    if (saved != true || count == null || count <= 0 || form == null) return;
    final removesStock = type == 'damaged' || type == 'correction_remove';
    final baseQuantity = count * form.unitsPerForm * (removesStock ? -1 : 1);
    await controller.addStockMovement(
      product: product,
      type: type,
      quantityBase: baseQuantity,
      note: savedNote,
    );
  }

  Future<void> _configure(BuildContext context) async {
    final baseUnit = TextEditingController(text: product.baseUnit);
    final threshold = TextEditingController(
      text: '${product.lowStockThreshold}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${product.name} stock settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: baseUnit,
              enabled: product.currentStock == 0,
              decoration: InputDecoration(
                labelText: 'Smallest unit sold',
                helperText: product.currentStock == 0
                    ? 'Example: pack or bottle'
                    : 'Reconcile stock to zero before changing this unit.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: threshold,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Low-stock level in ${product.baseUnit}',
              ),
            ),
          ],
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
    );
    final level = int.tryParse(threshold.text.trim());
    final unit = baseUnit.text.trim();
    baseUnit.dispose();
    threshold.dispose();
    if (saved != true || level == null || level < 0 || unit.isEmpty) return;
    await controller.updateInventoryConfiguration(
      product: product,
      baseUnit: unit,
      lowStockThreshold: level,
    );
  }

  Future<void> _physicalCount(BuildContext context) async {
    final quantity = TextEditingController(text: '${product.currentStock}');
    final note = TextEditingController();
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Count ${product.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantity,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Physical count in ${product.baseUnit}',
                    helperText:
                        'Saleo will record the difference as a correction.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason or note',
                    hintText: 'Stock count correction',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Apply count'),
              ),
            ],
          ),
        ) ??
        false;
    final value = int.tryParse(quantity.text.trim());
    final savedNote = note.text.trim();
    quantity.dispose();
    note.dispose();
    if (!saved || value == null || value < 0) return;
    await controller.setPhysicalStock(product, value, savedNote);
  }
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.controller,
    required this.products,
    required this.range,
  });

  final AppController controller;
  final List<Product> products;
  final ({DateTime start, DateTime end}) range;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        columns: const [
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Opening'), numeric: true),
          DataColumn(label: Text('Received'), numeric: true),
          DataColumn(label: Text('Sold'), numeric: true),
          DataColumn(label: Text('Adjustments'), numeric: true),
          DataColumn(label: Text('Closing'), numeric: true),
          DataColumn(label: Text('Low-stock level'), numeric: true),
          DataColumn(label: Text('Selling forms')),
          DataColumn(label: Text('Status')),
        ],
        rows: products.map((product) {
          final snapshot = _inventorySnapshot(controller, product, range);
          final adjustment = snapshot.corrections - snapshot.damaged;
          final color = product.currentStock < 0
              ? Theme.of(context).colorScheme.error
              : product.isLowStock
              ? Colors.orange.shade800
              : Colors.green.shade700;
          final status = product.currentStock < 0
              ? 'Needs attention'
              : product.isLowStock
              ? 'Low stock'
              : 'In stock';
          final forms = product.forms
              .where((form) => form.active)
              .map(
                (form) => form.unitsPerForm == 1
                    ? form.name
                    : '${form.name} (${form.unitsPerForm})',
              )
              .join(', ');
          return DataRow(
            cells: [
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${product.code} • ${product.category}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(Text(_formatStock(product, snapshot.opening))),
              DataCell(Text(_formatStock(product, snapshot.received))),
              DataCell(Text(_formatStock(product, snapshot.sold))),
              DataCell(Text(_formatStock(product, adjustment))),
              DataCell(
                Text(
                  _formatStock(product, snapshot.closing),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text(_formatStock(product, product.lowStockThreshold))),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(forms.isEmpty ? 'None' : forms),
                ),
              ),
              DataCell(
                Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    ),
  );
}

({
  int opening,
  int received,
  int sold,
  int damaged,
  int corrections,
  int closing,
  List<StockMovement> inPeriod,
})
_inventorySnapshot(
  AppController controller,
  Product product,
  ({DateTime start, DateTime end}) range,
) {
  final movements = controller.stockMovements
      .where((movement) => movement.productId == product.id)
      .toList();
  final opening = movements
      .where((movement) => movement.createdAt.toLocal().isBefore(range.start))
      .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  final inPeriod = movements.where((movement) {
    final date = movement.createdAt.toLocal();
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }).toList();
  final received = inPeriod
      .where(
        (movement) => const {
          'opening',
          'restock',
          'return',
          'sale_void',
        }.contains(movement.type),
      )
      .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  final sold = -inPeriod
      .where((movement) => movement.type == 'sale')
      .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  final damaged = -inPeriod
      .where((movement) => movement.type == 'damaged')
      .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  final corrections = inPeriod
      .where((movement) => movement.type.startsWith('correction'))
      .fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  final closing =
      opening +
      inPeriod.fold<int>(0, (sum, movement) => sum + movement.quantityBase);
  return (
    opening: opening,
    received: received,
    sold: sold,
    damaged: damaged,
    corrections: corrections,
    closing: closing,
    inPeriod: inPeriod,
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 158,
    child: Card(
      color: color.withValues(alpha: .07),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StockLine extends StatelessWidget {
  const _StockLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

({DateTime start, DateTime end}) _periodRange(
  InventoryPeriod period,
  int weekStartsOn,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (period) {
    InventoryPeriod.daily => (
      start: today,
      end: today.add(const Duration(days: 1)),
    ),
    InventoryPeriod.weekly => () {
      final daysSinceStart = (today.weekday - weekStartsOn + 7) % 7;
      final start = today.subtract(Duration(days: daysSinceStart));
      return (start: start, end: start.add(const Duration(days: 7)));
    }(),
    InventoryPeriod.monthly => (
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1),
    ),
  };
}

String _periodDescription(
  InventoryPeriod period,
  ({DateTime start, DateTime end}) range,
) {
  final end = range.end.subtract(const Duration(days: 1));
  return switch (period) {
    InventoryPeriod.daily =>
      'Today, ${range.start.day}/${range.start.month}/${range.start.year}',
    InventoryPeriod.weekly =>
      '${range.start.day}/${range.start.month} - ${end.day}/${end.month}/${end.year}',
    InventoryPeriod.monthly =>
      '${_monthName(range.start.month)} ${range.start.year}',
  };
}

String _customRangeDescription(({DateTime start, DateTime end}) range) {
  final inclusiveEnd = range.end.subtract(const Duration(minutes: 1));
  String two(int number) => number.toString().padLeft(2, '0');
  String value(DateTime date) =>
      '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
  return '${value(range.start)} - ${value(inclusiveEnd)}';
}

String _formatStock(Product product, int quantity) {
  return productStockText(product, quantity);
}

String _plural(String value, int count) {
  if (count == 1) return value;
  final lower = value.toLowerCase();
  if (lower.endsWith('s')) return value;
  if (lower.endsWith('x') || lower.endsWith('ch')) return '${value}es';
  return '${value}s';
}

String _movementLabel(String type) => switch (type) {
  'opening' => 'Opening stock',
  'restock' => 'Stock received',
  'return' => 'Customer return',
  'sale' => 'Sale',
  'sale_void' => 'Voided sale restored',
  'damaged' => 'Damaged or lost',
  'correction_add' => 'Count correction added',
  'correction_remove' => 'Count correction removed',
  _ => 'Stock adjustment',
};

String _shortDate(DateTime value) {
  final date = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
}

String _monthName(int month) => const [
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
][month - 1];

bool _sameDay(DateTime left, DateTime right) {
  final a = left.toLocal();
  final b = right.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Product _fallbackProduct(int id) => Product(
  id: id,
  name: 'Product $id',
  code: '',
  category: '',
  active: false,
  forms: const [],
);

DateTime _receiptPeriodStart(ProductPerformancePeriod period) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (period) {
    ProductPerformancePeriod.today => today,
    ProductPerformancePeriod.week => today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    ),
    ProductPerformancePeriod.month => DateTime(now.year, now.month),
    ProductPerformancePeriod.year => DateTime(now.year),
  };
}

String _receiptPeriodLabel(ProductPerformancePeriod period) => switch (period) {
  ProductPerformancePeriod.today => 'Today',
  ProductPerformancePeriod.week => 'This week',
  ProductPerformancePeriod.month => 'This month',
  ProductPerformancePeriod.year => 'This year',
};
