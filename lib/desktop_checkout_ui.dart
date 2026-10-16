import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'formatters.dart';

BoxConstraints checkoutDialogConstraints(BuildContext context) =>
    BoxConstraints.tightFor(
      width: (MediaQuery.sizeOf(context).width - 48).clamp(280, 620),
    );

class DesktopProductGrid extends StatefulWidget {
  const DesktopProductGrid({
    super.key,
    required this.controller,
    required this.onAdd,
  });
  final AppController controller;
  final void Function(Product, SellingForm) onAdd;
  @override
  State<DesktopProductGrid> createState() => _DesktopProductGridState();
}

class _DesktopProductGridState extends State<DesktopProductGrid> {
  String _query = '', _category = 'All';
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final categories = [
      'All',
      ...{for (final p in c.activeProducts) p.category},
    ];
    final products = c.activeProducts
        .where(
          (p) =>
              (_category == 'All' || p.category == _category) &&
              '${p.name} ${p.code}'.toLowerCase().contains(
                _query.toLowerCase(),
              ) &&
              p.forms.any((f) => f.active),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Product catalogue',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text('${products.length} products'),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search products or codes',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(categories[i]),
                selected: _category == categories[i],
                onSelected: (_) => setState(() => _category = categories[i]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No products match your search.'))
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (constraints.maxWidth / 195)
                            .floor()
                            .clamp(1, 3),
                        mainAxisExtent: ((constraints.maxHeight - 32) / 5)
                            .clamp(124, 154),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: products.length,
                      itemBuilder: (_, i) => _ProductCard(
                        key: ValueKey(products[i].code),
                        product: products[i],
                        showImages: c.inventoryPreferences.showProductImages,
                        onAdd: widget.onAdd,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    super.key,
    required this.product,
    required this.onAdd,
    required this.showImages,
  });
  final Product product;
  final void Function(Product, SellingForm) onAdd;
  final bool showImages;
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  int? _formId;
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final forms = p.forms.where((f) => f.active).toList();
    if (forms.isEmpty) return const SizedBox.shrink();
    final selected =
        forms.where((f) => f.id == _formId).firstOrNull ?? forms.first;
    final scheme = Theme.of(context).colorScheme;
    final stock = productStockText(p, p.currentStock);
    final brief = stock.replaceFirst(RegExp(r' \([^)]*\)$'), '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.showImages && p.imageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      p.imageBytes!,
                      width: 42,
                      height: 42,
                      fit: BoxFit.contain,
                      cacheWidth: 96,
                      cacheHeight: 96,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 42, height: 42),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: '${p.name} · ${p.code}',
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        'GHS ${money(selected.priceCents)}',
                        maxLines: 1,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: PopupMenuButton<int>(
                    tooltip: 'Selling form for ${p.name}',
                    initialValue: selected.id,
                    position: PopupMenuPosition.under,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 120,
                      maxWidth: 230,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (id) => setState(() => _formId = id),
                    itemBuilder: (_) => [
                      for (final f in forms)
                        PopupMenuItem(
                          value: f.id,
                          height: 32,
                          child: Text(
                            f.name,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selected.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Icon(Icons.expand_more_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Add ${p.name}',
                  onPressed: () => widget.onAdd(p, selected),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
            const Spacer(),
            Tooltip(
              message: stock,
              child: Text(
                p.currentStock <= 0
                    ? 'No recorded stock · confirm sale'
                    : 'Stock: $brief',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.currentStock <= 0
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopCartRow extends StatelessWidget {
  const DesktopCartRow({
    super.key,
    required this.line,
    required this.quantityEditor,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
  });
  final CartLine line;
  final Widget quantityEditor;
  final VoidCallback onMinus, onPlus, onRemove;
  Widget _button(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action, {
    bool danger = false,
  }) => IconButton(
    tooltip: label,
    onPressed: action,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    padding: EdgeInsets.zero,
    icon: Icon(
      icon,
      size: 16,
      color: danger ? Theme.of(context).colorScheme.error : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: line.product.name,
                child: Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'GHS ${money(line.lineTotalCents)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
        Text(
          '${line.form.name} · GHS ${money(line.form.priceCents)} each',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
        Row(
          children: [
            _button(context, Icons.remove, 'Decrease quantity', onMinus),
            SizedBox(width: 46, height: 28, child: quantityEditor),
            _button(context, Icons.add, 'Increase quantity', onPlus),
            const Spacer(),
            _button(
              context,
              Icons.delete_rounded,
              'Remove ${line.product.name}',
              onRemove,
              danger: true,
            ),
          ],
        ),
      ],
    ),
  );
}

class CheckoutCompanyPicker extends StatefulWidget {
  const CheckoutCompanyPicker({
    super.key,
    required this.customers,
    required this.onSelected,
    this.selected,
    required this.credit,
  });
  final List<CustomerRecord> customers;
  final CustomerRecord? selected;
  final bool credit;
  final ValueChanged<CustomerRecord> onSelected;
  @override
  State<CheckoutCompanyPicker> createState() => _CheckoutCompanyPickerState();
}

class _CheckoutCompanyPickerState extends State<CheckoutCompanyPicker> {
  bool _expanded = false;
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches =
        widget.customers
            .where(
              (c) => '${c.companyName} ${c.name} ${c.phone} ${c.address}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => (a.companyName.isEmpty ? a.name : a.companyName)
                .toLowerCase()
                .compareTo(
                  (b.companyName.isEmpty ? b.name : b.companyName)
                      .toLowerCase(),
                ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            _expanded = !_expanded;
            _query = '';
            _search.clear();
          }),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.credit
                  ? 'Select debtor company'
                  : 'Select existing customer (optional)',
              prefixIcon: const Icon(Icons.business_outlined),
              suffixIcon: Icon(_expanded ? Icons.expand_less : Icons.search),
            ),
            child: Text(
              widget.selected == null
                  ? 'Search customer or company'
                  : '${widget.selected!.companyName.isEmpty ? widget.selected!.name : widget.selected!.companyName} · ${widget.selected!.phone}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Card(
              key: const ValueKey('company-search-results'),
              color: scheme.surfaceContainer,
              surfaceTintColor: Colors.transparent,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      autofocus: true,
                      style: TextStyle(color: scheme.onSurface),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: scheme.surface,
                        hintText: 'Search company, phone or address',
                        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                        prefixIcon: Icon(
                          Icons.search,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                'No matching customers or companies.',
                                style: TextStyle(color: scheme.onSurface),
                              ),
                            )
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final customer = matches[i];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.business_outlined,
                                    size: 20,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    customer.companyName.isEmpty
                                        ? customer.name
                                        : customer.companyName,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      customer.phone,
                                      customer.address,
                                    ].where((v) => v.isNotEmpty).join(' · '),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() => _expanded = false);
                                    widget.onSelected(customer);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CheckoutProductsReview extends StatelessWidget {
  const CheckoutProductsReview({super.key, required this.lines});
  final List<CartLine> lines;
  @override
  Widget build(BuildContext context) => AlertDialog(
    constraints: checkoutDialogConstraints(context),
    icon: Icon(
      Icons.fact_check_outlined,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: const Text('Confirm products'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Review products, selling forms and quantities before payment.',
          ),
          const SizedBox(height: 16),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${line.form.name} · ${line.quantity} × GHS ${money(line.form.priceCents)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'GHS ${money(line.lineTotalCents)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const Divider(),
          CheckoutSummaryRow(
            label: 'Sale total',
            value:
                'GHS ${money(lines.fold<int>(0, (n, l) => n + l.lineTotalCents))}',
            emphasized: true,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Edit products'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Confirm products'),
      ),
    ],
  );
}

class CheckoutSummaryRow extends StatelessWidget {
  const CheckoutSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label, value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: emphasized ? Theme.of(context).colorScheme.primaryContainer : null,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}
