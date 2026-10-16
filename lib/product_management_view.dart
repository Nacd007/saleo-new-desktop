import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'formatters.dart';
import 'product_export_service.dart';

class SellingFormEdit {
  const SellingFormEdit(this.name, this.priceCents, this.units, this.active);
  final String name;
  final int priceCents, units;
  final bool active;
}

class SellingFormEditor extends StatefulWidget {
  const SellingFormEditor({
    super.key,
    required this.product,
    required this.form,
  });
  final Product product;
  final SellingForm form;
  @override
  State<SellingFormEditor> createState() => _SellingFormEditorState();
}

class _SellingFormEditorState extends State<SellingFormEditor> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name, _price, _units;
  late bool _active;
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.form.name);
    _price = TextEditingController(
      text: (widget.form.priceCents / 100).toStringAsFixed(2),
    );
    _units = TextEditingController(text: widget.form.unitsPerForm.toString());
    _active = widget.form.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _units.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_confirming || !_key.currentState!.validate()) return;
    final price = (double.parse(_price.text.trim()) * 100).round();
    final units = int.parse(_units.text.trim());
    final warning = sellingPriceWarning(
      widget.product,
      widget.form.id,
      price,
      units,
    );
    if (warning != null) {
      setState(() => _confirming = true);
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Check selling price'),
          content: Text(warning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Review price'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Keep price'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (keep != true) return;
    }
    if (mounted) {
      Navigator.pop(
        context,
        SellingFormEdit(_name.text.trim(), price, units, _active),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.product.name} · ${widget.form.name}'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Selling form name',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter a selling form name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Selling price (GHS)',
                ),
                validator: (v) {
                  final price = double.tryParse(v?.trim() ?? '');
                  return price == null ||
                          !price.isFinite ||
                          price < 0.01 ||
                          !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v!.trim())
                      ? 'Enter a positive price with at most two decimal places.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _units,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${widget.product.baseUnit}s in this form',
                  helperText: 'Stock removed when one of this form is sold.',
                ),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Enter a positive whole number.'
                    : null,
              ),
              if (widget.form.id >= 0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available for new sales'),
                  subtitle: const Text(
                    'Turning this off retains historical receipts.',
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _confirming ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _confirming ? null : _save,
        child: const Text('Save changes'),
      ),
    ],
  );
}

/// Stable active-first order, including when names are equal.
List<Product> filterProductCatalogue(
  List<Product> source, {
  String query = '',
  String status = 'All',
  String? category,
}) {
  final term = query.trim().toLowerCase();
  return source.where((p) {
    if (status == 'Active' && !p.active) return false;
    if (status == 'Inactive' && p.active) return false;
    if (category != null && p.category != category) return false;
    return [
      p.name,
      p.code,
      p.category,
      ...p.forms.map((f) => f.name),
    ].join(' ').toLowerCase().contains(term);
  }).toList()..sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return name != 0 ? name : a.id.compareTo(b.id);
  });
}

/// Warn, never silently derive or replace a merchant's independent prices.
String? sellingPriceWarning(Product product, int formId, int price, int units) {
  if (units <= 1 || price <= 0) return null;
  final singles = product.forms.where(
    (f) =>
        f.id != formId && f.active && f.unitsPerForm == 1 && f.priceCents > 0,
  );
  if (singles.isEmpty) return null;
  final equivalent = singles.first.priceCents * units;
  if (price <= equivalent) return null;
  return 'This form costs GHS ${money(price)}, but $units singles cost '
      'GHS ${money(equivalent)}. Keep this independent price?';
}

class _ProductHeadingDelegate extends SliverPersistentHeaderDelegate {
  const _ProductHeadingDelegate({required this.heading, required this.surface});

  final Widget heading;
  final Color surface;

  @override
  double get minExtent => 42;
  @override
  double get maxExtent => 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: heading,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProductHeadingDelegate oldDelegate) => true;
}

class ProductManagementView extends StatefulWidget {
  const ProductManagementView({
    super.key,
    required this.controller,
    required this.initialStatus,
    required this.onAdd,
    required this.onImport,
    required this.onCategory,
    required this.onSample,
    required this.onTemplate,
    required this.onEdit,
    required this.onAddForm,
    required this.onEditForm,
  });
  final AppController controller;
  final String initialStatus;
  final Future<void> Function() onAdd, onImport, onCategory, onSample;
  final Future<void> Function(String) onTemplate;
  final Future<void> Function(Product) onEdit, onAddForm;
  final Future<void> Function(Product, SellingForm) onEditForm;
  @override
  State<ProductManagementView> createState() => _ProductManagementViewState();
}

class _ProductManagementViewState extends State<ProductManagementView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _status = 'All';
  String? _category;
  final int _size = 75;
  int _page = 0;
  bool _busy = false, _interacted = false;
  AppController get c => widget.controller;
  String get _scope => 'product.view.${c.currentUser?.id ?? 0}';
  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _restore();
  }

  Future<void> _restore() async {
    try {
      final raw = await c.database.readWorkflowMeta(_scope);
      if (!mounted || _interacted || raw == null) return;
      final data = jsonDecode(raw) as Map;
      setState(() {
        if (widget.initialStatus == 'All' &&
            ['All', 'Active', 'Inactive'].contains(data['status'])) {
          _status = data['status'] as String;
        }
        final category = data['category'];
        if (category is String && c.productCategories.contains(category)) {
          _category = category;
        }
      });
    } catch (_) {
      /* A missing preference must not prevent catalogue access. */
    }
  }

  Future<void> _remember() async {
    try {
      await c.saveProductViewPreferences({
        'size': _size,
        'status': _status,
        'category': _category,
      });
    } catch (_) {
      if (mounted) {
        _message('View changed, but its preference could not be saved.');
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProductManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) {
      _status = widget.initialStatus;
      _page = 0;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    setState(() {
      _interacted = true;
      change();
      _page = 0;
    });
    _remember();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _run(
    Future<void> Function() action, {
    bool saved = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && saved) _message('Saved on this device. Waiting to sync.');
    } catch (_) {
      if (mounted) _message('Could not complete the change. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final products = filterProductCatalogue(
        c.products,
        query: _search.text,
        status: _status,
        category: _category,
      );
      final pages = (products.length / _size).ceil();
      final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
      final start = page * _size;
      final visible = products.skip(start).take(_size).toList();
      final pending = c.syncService.pendingProductCodes(c.products);
      final cs = Theme.of(context).colorScheme;
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: c.refresh,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: _productControls(context),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProductHeadingDelegate(
                      heading: _catalogueHeading(context, products.length),
                      surface: cs.surface,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverList.builder(
                      itemCount: visible.length + 1,
                      itemBuilder: (context, index) {
                        if (index == visible.length) {
                          return products.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No matching products. Change the filters or add a product.',
                                  ),
                                )
                              : const SizedBox(height: 12);
                        }
                        final product = visible[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: .55),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            key: PageStorageKey('product-${product.id}'),
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            minTileHeight: 48,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                size: 17,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            title: LayoutBuilder(
                              builder: (context, width) {
                                final wide = width.maxWidth >= 560;
                                final stock = product.currentStock <= 0
                                    ? 'Out of stock'
                                    : productStockText(
                                        product,
                                        product.currentStock,
                                      );
                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        product.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (wide) ...[
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          product.code,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          product.category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          stock,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: product.currentStock <= 0
                                                ? cs.error
                                                : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '${product.forms.length} forms',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ] else
                                      Text(
                                        stock,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    if (pending.contains(product.code))
                                      Tooltip(
                                        message: 'Saved on this device; waiting to sync',
                                        child: Icon(
                                          Icons.cloud_upload_outlined,
                                          size: 15,
                                          color: cs.tertiary,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Available for new sales',
                                  child: Switch(
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    value: product.active,
                                    onChanged: _busy
                                        ? null
                                        : (value) async {
                                            if (!await _confirm(
                                              value
                                                  ? 'Activate product?'
                                                  : 'Deactivate product?',
                                              'Change availability for ${product.name}? Existing records will be retained.',
                                            )) {
                                              return;
                                            }
                                            if (mounted) {
                                              await _run(
                                                () => c.bulkUpdateProducts({
                                                  product.id,
                                                }, active: value),
                                                saved: true,
                                              );
                                            }
                                          },
                                  ),
                                ),
                                const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 19,
                                ),
                              ],
                            ),
                            childrenPadding: const EdgeInsets.all(12),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Selling forms (${product.forms.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth < 700) {
                                    return Column(
                                      children: [
                                        for (final form in product.forms)
                                          ListTile(
                                            title: Text(form.name),
                                            subtitle: Text(
                                              'Contains ${form.unitsPerForm} ${product.baseUnit}\n${form.active ? "Active" : "Inactive"}',
                                            ),
                                            trailing: Text(
                                              money(form.priceCents),
                                            ),
                                            onTap: _busy
                                                ? null
                                                : () => _run(
                                                    () => widget.onEditForm(
                                                      product,
                                                      form,
                                                    ),
                                                  ),
                                          ),
                                      ],
                                    );
                                  }
                                  return SizedBox(
                                    width: double.infinity,
                                    child: DataTable(
                                      headingRowHeight: 36,
                                      dataRowMinHeight: 44,
                                      dataRowMaxHeight: 52,
                                      columnSpacing: 18,
                                      horizontalMargin: 8,
                                      columns: const [
                                        DataColumn(label: Text('Form')),
                                        DataColumn(label: Text('Contains')),
                                        DataColumn(
                                          label: Text('Price (GHS)'),
                                          numeric: true,
                                        ),
                                        DataColumn(label: Text('Status')),
                                        DataColumn(label: Text('Actions')),
                                      ],
                                      rows: product.forms
                                          .map(
                                            (form) => DataRow(
                                              cells: [
                                                DataCell(Text(form.name)),
                                                DataCell(
                                                  Text(
                                                    '${form.unitsPerForm} ${product.baseUnit}',
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    (form.priceCents / 100)
                                                        .toStringAsFixed(2),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    form.active
                                                        ? 'Active'
                                                        : 'Inactive',
                                                  ),
                                                ),
                                                DataCell(
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        tooltip:
                                                            'Edit ${form.name}',
                                                        onPressed: _busy
                                                            ? null
                                                            : () => _run(
                                                                () => widget
                                                                    .onEditForm(
                                                                      product,
                                                                      form,
                                                                    ),
                                                              ),
                                                        icon: const Icon(
                                                          Icons.edit_outlined,
                                                          size: 18,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        tooltip: form.active
                                                            ? 'Deactivate form (retain history)'
                                                            : 'Reactivate form',
                                                        onPressed: _busy
                                                            ? null
                                                            : () async {
                                                                if (!await _confirm(
                                                                  'Change selling form availability?',
                                                                  'Existing sales are retained. This only affects new sales.',
                                                                )) {
                                                                  return;
                                                                }
                                                                if (mounted) {
                                                                  await _run(
                                                                    () => c.updateSellingForm(
                                                                      form,
                                                                      form.name,
                                                                      form.priceCents,
                                                                      !form
                                                                          .active,
                                                                      form.unitsPerForm,
                                                                    ),
                                                                    saved: true,
                                                                  );
                                                                }
                                                              },
                                                        icon: Icon(
                                                          form.active
                                                              ? Icons
                                                                    .archive_outlined
                                                              : Icons
                                                                    .unarchive_outlined,
                                                          size: 18,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  );
                                },
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => widget.onEdit(product),
                                          ),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Edit product'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            () => widget.onAddForm(product),
                                          ),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add selling form'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _history(product),
                                    icon: const Icon(Icons.history),
                                    label: const Text('Price history'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  'Showing ${products.isEmpty ? 0 : start + 1}–${start + visible.length} of ${products.length} products',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: page == 0 ? null : () => _go(page - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${pages == 0 ? 0 : page + 1} / $pages'),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: page + 1 >= pages ? null : () => _go(page + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
  Widget _productControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Products',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Manage products, stock and selling forms',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onCategory),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Create category'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onAdd),
                  icon: const Icon(Icons.add),
                  label: const Text('New product'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Import products'),
                subtitle: const Text(
                  'Excel or CSV with categories, stock and selling forms',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _run(widget.onImport),
              ),
              const Divider(height: 1),
              Wrap(
                spacing: 8,
                runSpacing: 0,
                children: [
                  TextButton(
                    onPressed: () => _run(widget.onSample),
                    child: const Text('View sample'),
                  ),
                  TextButton(
                    onPressed: () => _run(() => widget.onTemplate('xlsx')),
                    child: const Text('Excel template'),
                  ),
                  TextButton(
                    onPressed: () => _run(() => widget.onTemplate('csv')),
                    child: const Text('CSV template'),
                  ),
                  TextButton.icon(
                    onPressed: c.products.isEmpty
                        ? null
                        : () => _run(() async {
                            final uri = await const ProductExportService()
                                .saveExcel(c.products);
                            if (mounted && uri != null) {
                              _message('Products exported.');
                            }
                          }),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export all products'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final status = SegmentedButton<String>(
              segments: [
                'All',
                'Active',
                'Inactive',
              ].map((v) => ButtonSegment(value: v, label: Text(v))).toList(),
              selected: {_status},
              onSelectionChanged: (v) => _change(() => _status = v.first),
            );
            final search = TextField(
              controller: _search,
              onChanged: (_) => setState(() {
                _interacted = true;
                _page = 0;
              }),
              decoration: InputDecoration(
                labelText: 'Search products',
                hintText: 'Name, code, category or selling form',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear product search',
                        icon: const Icon(Icons.close),
                        onPressed: () => _change(_search.clear),
                      ),
              ),
            );
            final category = DropdownButtonFormField<String>(
              key: ValueKey(_category),
              initialValue: _category ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ['', ...c.productCategories]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                        v.isEmpty ? 'All categories' : v,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => _change(() => _category = v == '' ? null : v),
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  status,
                  const SizedBox(height: 12),
                  search,
                  const SizedBox(height: 12),
                  category,
                ],
              );
            }
            return Row(
              children: [
                status,
                const SizedBox(width: 12),
                Expanded(flex: 2, child: search),
                const SizedBox(width: 12),
                Expanded(child: category),
              ],
            );
          },
        ),
      ],
    );
  }

  void _go(int page) {
    setState(() {
      _page = page;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _catalogueHeading(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          final labelStyle = TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          );
          if (!wide) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text('PRODUCTS  ·  $count', style: labelStyle),
            );
          }
          return Row(
            children: [
              const SizedBox(width: 48),
              Expanded(flex: 3, child: Text('PRODUCT', style: labelStyle)),
              Expanded(flex: 2, child: Text('CODE', style: labelStyle)),
              Expanded(flex: 3, child: Text('CATEGORY', style: labelStyle)),
              Expanded(flex: 2, child: Text('STOCK', style: labelStyle)),
              Expanded(
                flex: 2,
                child: Text('SELLING FORMS', style: labelStyle),
              ),
              const SizedBox(
                width: 82,
                child: Text(
                  'ACTIVE',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _history(Product product) async {
    try {
      final history = await c.loadProductPriceHistory(product);
      final entries = (history['entries'] as List).cast<Map>();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${product.name} · Price history'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(history['source'] as String),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const Text('No price changes recorded yet.'),
                  for (final entry in entries)
                    ListTile(
                      title: Text(
                        '${entry["form"]}: ${money(entry["old"] as int)} → ${money(entry["new"] as int)}',
                      ),
                      subtitle: Text('${entry["actor"]} · ${entry["at"]}'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) _message('Price history could not be loaded.');
    }
  }
}
