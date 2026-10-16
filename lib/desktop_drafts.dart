import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'app_controller.dart';
import 'models.dart';
import 'receptionist_home.dart';
import 'formatters.dart';

class DesktopDraft {
  DesktopDraft({required this.id, required this.name, this.lines = const []});
  final String id;
  String name;
  List<CartLine> lines;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lines': [
      for (final l in lines)
        {
          'product_id': l.product.id,
          'code': l.product.code,
          'name': l.product.name,
          'category': l.product.category,
          'form_id': l.form.id,
          'form': l.form.name,
          'units': l.form.unitsPerForm,
          'price': l.form.priceCents,
          'quantity': l.quantity,
        },
    ],
  };
  static DesktopDraft fromJson(
    Map<String, dynamic> data,
    List<Product> products,
  ) {
    final lines = <CartLine>[];
    for (final row in data['lines'] as List) {
      final product = products.where((p) => p.code == row['code']).firstOrNull;
      final form = product?.forms
          .where((f) => f.name == row['form'] && f.unitsPerForm == row['units'])
          .firstOrNull;
      final fallback = SellingForm(
        id: row['form_id'] as int,
        productId: row['product_id'] as int,
        name: row['form'] as String,
        priceCents: row['price'] as int,
        unitsPerForm: row['units'] as int,
        active: false,
      );
      lines.add(
        CartLine(
          product:
              product ??
              Product(
                id: row['product_id'] as int,
                code: row['code'] as String,
                name: row['name'] as String,
                category: row['category'] as String,
                active: false,
                forms: [fallback],
              ),
          form: form ?? fallback,
          quantity: row['quantity'] as int,
        ),
      );
    }
    return DesktopDraft(
      id: data['id'] as String,
      name: data['name'] as String,
      lines: lines,
    );
  }
}

class DesktopSellPage extends StatefulWidget {
  const DesktopSellPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<DesktopSellPage> createState() => _DesktopSellPageState();
}

class _DesktopSellPageState extends State<DesktopSellPage> {
  final _drafts = <DesktopDraft>[];
  final _retired = <String>{};
  int _active = 0;
  int _completed = 0;
  bool _restoring = true;
  bool _switching = false;
  String? _error;
  String _signature = '';
  Timer? _timer;
  Future<void> _writes = Future.value();
  AppController get c => widget.controller;
  String get _prefix =>
      'desktop.draft.${base64Url.encode(utf8.encode(c.currentUser!.username))}.';
  String _key(DesktopDraft d) => '$_prefix${d.id}';
  @override
  void initState() {
    super.initState();
    _completed = c.completedSalesRevision;
    c.addListener(_changed);
    c.flushDesktopDraft = _flush;
    _restore();
  }

  Future<void> _restore() async {
    try {
      final rows = await c.database.db.query(
        'app_meta',
        where: 'key LIKE ?',
        whereArgs: ['$_prefix%'],
        orderBy: 'key',
      );
      if (!mounted) return;
      for (final row in rows) {
        _drafts.add(
          DesktopDraft.fromJson(
            (jsonDecode(row['value'] as String) as Map).cast<String, dynamic>(),
            c.products,
          ),
        );
      }
      if (_drafts.isEmpty) {
        _drafts.add(DesktopDraft(id: const Uuid().v4(), name: 'Sale 1'));
      }
      _restoring = false;
      _activate(0);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Saved drafts could not be loaded. No drafts were deleted. $e',
        );
      }
    }
  }

  void _activate(int index) {
    _switching = true;
    _active = index;
    c.cart = List.of(_drafts[index].lines);
    c.desktopDraftKey = _key(_drafts[index]);
    _signature = jsonEncode(_drafts[index].toJson());
    _switching = false;
    setState(() {});
  }

  void _changed() {
    if (!mounted || _restoring || _switching || c.currentUser == null) return;
    if (_completed != c.completedSalesRevision) {
      _completed = c.completedSalesRevision;
      final removed = _drafts.removeAt(_active);
      _retired.add(removed.id);
      _timer?.cancel();
      if (_drafts.isEmpty) {
        _drafts.add(DesktopDraft(id: const Uuid().v4(), name: 'New sale'));
      }
      _activate(_active.clamp(0, _drafts.length - 1));
      return;
    }
    final d = _drafts[_active];
    d.lines = List.of(c.cart);
    final signature = jsonEncode(d.toJson());
    if (signature == _signature) return;
    _signature = signature;
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 300),
      () => _flush().catchError((Object e) {
        if (mounted) {
          setState(
            () => _error =
                'Draft could not be saved. Keep this window open and retry. $e',
          );
        }
      }),
    );
    setState(() {});
  }

  Future<void> _flush() async {
    _timer?.cancel();
    if (_restoring || _drafts.isEmpty) return;
    final draft = _drafts[_active];
    draft.lines = List.of(c.cart);
    final key = _key(draft);
    final value = jsonEncode(draft.toJson());
    final id = draft.id;
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!_retired.contains(id)) {
        await c.database.writeWorkflowMeta(key, value);
      }
    });
    await _writes;
    if (mounted) setState(() => _error = null);
  }

  Future<void> _select(int index) async {
    if (c.busy || index == _active) return;
    try {
      await _flush();
      if (mounted) _activate(index);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Save failed; current draft kept. $e');
      }
    }
  }

  Future<void> _add() async {
    if (c.busy || _restoring) return;
    try {
      await _flush();
      if (!mounted) return;
      _drafts.add(
        DesktopDraft(id: const Uuid().v4(), name: 'Sale ${_drafts.length + 1}'),
      );
      _activate(_drafts.length - 1);
      await _flush();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _close(int index) async {
    if (c.busy) {
      return;
    }
    final d = _drafts[index];
    if (index == _active) d.lines = List.of(c.cart);
    if (d.lines.isNotEmpty &&
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Discard ${d.name}?'),
                content: const Text(
                  'This removes this draft only. Completed sales are not affected.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep draft'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Discard draft'),
                  ),
                ],
              ),
            ) !=
            true) {
      return;
    }
    if (!mounted) return;
    try {
      await _flush();
      await c.database.db.delete(
        'app_meta',
        where: 'key = ?',
        whereArgs: [_key(d)],
      );
      if (!mounted) return;
      _retired.add(d.id);
      if (index != _active) _drafts[_active].lines = List.of(c.cart);
      _drafts.removeAt(index);
      if (_drafts.isEmpty) {
        _drafts.add(DesktopDraft(id: const Uuid().v4(), name: 'New sale'));
      }
      final next = index < _active ? _active - 1 : _active;
      _activate(next.clamp(0, _drafts.length - 1));
    } catch (e) {
      if (mounted) setState(() => _error = 'Draft was not discarded: $e');
    }
  }

  Future<void> _rename(int index) async {
    if (c.busy || _restoring) return;
    final draft = _drafts[index];
    final field = TextEditingController(text: draft.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename sale draft'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Draft name',
            hintText: 'Customer, company or order name',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(dialogContext, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (field.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, field.text.trim());
              }
            },
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    // Dispose after the route transition no longer uses its input field.
    Future<void>.delayed(const Duration(milliseconds: 300), field.dispose);
    if (name == null || !mounted || c.busy) return;
    final previous = draft.name;
    try {
      await _flush();
      draft.name = name;
      await c.database.writeWorkflowMeta(
        _key(draft),
        jsonEncode(draft.toJson()),
      );
      if (mounted) setState(() {});
    } catch (e) {
      draft.name = previous;
      if (mounted) setState(() => _error = 'Draft name could not be saved. $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_changed);
    c.flushDesktopDraft = null;
    c.desktopDraftKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!),
      );
    }
    return Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => _flush().catchError((Object _) {}),
                child: const Text('Retry'),
              ),
            ],
          ),
        SizedBox(
          height: 70,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            children: [
              for (var i = 0; i < _drafts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 245,
                    child: Card(
                      color: i == _active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: InkWell(
                        onTap: () => _select(i),
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _drafts[i].name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'GHS ${money(_drafts[i].lines.fold<int>(0, (s, l) => s + l.lineTotalCents))}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Rename ${_drafts[i].name}',
                              onPressed: c.busy ? null : () => _rename(i),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                            ),
                            IconButton(
                              tooltip: 'Close draft',
                              onPressed: () => _close(i),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('New sale'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Text('New sale', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 10),
              const Chip(label: Text('Draft')),
              const Spacer(),
              const Icon(Icons.shopping_bag_outlined, size: 16),
              const SizedBox(width: 6),
              const Text('Products'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, size: 16),
              ),
              const Text('Review'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, size: 16),
              ),
              const Text('Confirm payment'),
            ],
          ),
        ),
        Expanded(
          child: NewSaleScreen(
            key: ValueKey(_drafts[_active].id),
            controller: c,
            receiptHostContext: context,
          ),
        ),
      ],
    );
  }
}
