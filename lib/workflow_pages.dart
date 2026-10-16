import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'common_widgets.dart';
import 'formatters.dart';
import 'models.dart';
import 'printer_settings.dart';

class ApprovalPage extends StatefulWidget {
  const ApprovalPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  bool busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final admin = c.currentUser?.role == UserRole.admin;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Approvals & corrections',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Text(
            'Stock enters inventory only after server approval. '
            'Corrections currently use void-and-replace; refunds and payment-only edits require separate reconciliation.',
          ),
          if (admin)
            SwitchListTile(
              title: const Text(
                'Allow receptionists to correct their own sales directly',
              ),
              subtitle: const Text(
                'Within 24 hours; otherwise request admin approval. Default: approval required.',
              ),
              value: c.directCorrections,
              onChanged: busy
                  ? null
                  : (value) => _run(() => c.saveCorrectionPolicy(value)),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _run(c.refreshWorkflows),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh / send queued submissions'),
          ),
          if (c.syncService.workflowError != null)
            Text(c.syncService.workflowError!),
          if (c.workflows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No submissions loaded.'),
            ),
          for (final row in c.workflows)
            Card(
              child: ExpansionTile(
                title: Text(
                  '${row['kind'] == 'stock' ? 'Stock delivery' : 'Sale correction'} — ${row['status']}',
                ),
                subtitle: Text('Submitted by ${row['submitted_by'] ?? ''}'),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  if (row['kind'] == 'stock') ...[
                    for (final item
                        in ((row['details'] as Map)['items'] as List))
                      ListTile(
                        dense: true,
                        title: Text('${item['product_name']}'),
                        subtitle: Text(
                          '${item['quantity_forms']} ${item['form_name']} (${item['quantity_base']} single units)',
                        ),
                      ),
                  ] else
                    Text(
                      'Receipt: ${(row['details'] as Map)['receipt_number']}\nReason: ${row['reason']}',
                    ),
                  for (final event in (row['history'] as List? ?? []))
                    ListTile(
                      dense: true,
                      title: Text('${event['action']} — ${event['actor']}'),
                      subtitle: Text(
                        '${event['at']}\n${event['reason'] ?? ''}',
                      ),
                    ),
                  if (admin && row['status'] == 'pending')
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: busy ? null : () => _decide(row, true),
                          child: const Text('Approve'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : () => _decide(row, false),
                          child: const Text('Reject with reason'),
                        ),
                      ],
                    ),
                  if (row['kind'] == 'stock' && row['status'] == 'rejected')
                    OutlinedButton(
                      onPressed: busy ? null : () => _edit(row),
                      child: const Text('Correct delivery and resubmit'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final reason = await workflowReason(
      context,
      approve ? 'Approve submission' : 'Reject submission',
    );
    if (reason != null) {
      await _run(() => widget.controller.decideWorkflow(row, approve, reason));
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final details = (jsonDecode(jsonEncode(row['details'])) as Map)
        .cast<String, dynamic>();
    final items = details['items'] as List;
    final products = widget.controller.products
        .where((p) => p.forms.isNotEmpty)
        .toList();
    final supplier = TextEditingController(
      text: details['supplier_name']?.toString() ?? '',
    );
    final invoice = TextEditingController(
      text: details['invoice_number']?.toString() ?? '',
    );
    final fields = [
      for (final item in items)
        TextEditingController(text: '${item['quantity_forms']}'),
    ];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Correct received delivery'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: supplier,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                  ),
                  TextField(
                    controller: invoice,
                    decoration: const InputDecoration(
                      labelText: 'Invoice number',
                    ),
                  ),
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'product-$i-${items[i]['product_code']}',
                            ),
                            initialValue:
                                products.any(
                                  (p) => p.code == items[i]['product_code'],
                                )
                                ? items[i]['product_code'] as String
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Product',
                            ),
                            items: products
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p.code,
                                    child: Text(
                                      p.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (code) => update(() {
                              final p = products.firstWhere(
                                (p) => p.code == code,
                              );
                              items[i].addAll({
                                'product_code': p.code,
                                'product_id': p.id,
                                'product_name': p.name,
                                'form_name': p.forms.first.name,
                                'units_per_form': p.forms.first.unitsPerForm,
                                'purchase_cost_cents': null,
                              });
                            }),
                          ),
                          Builder(
                            builder: (context) {
                              final p = products
                                  .where(
                                    (p) => p.code == items[i]['product_code'],
                                  )
                                  .firstOrNull;
                              final forms = p?.forms ?? <SellingForm>[];
                              return DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'form-$i-${items[i]['product_code']}-${items[i]['form_name']}',
                                ),
                                initialValue:
                                    forms.any(
                                      (f) => f.name == items[i]['form_name'],
                                    )
                                    ? items[i]['form_name'] as String
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Selling form',
                                ),
                                items: forms
                                    .map(
                                      (f) => DropdownMenuItem(
                                        value: f.name,
                                        child: Text(
                                          f.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (name) => update(() {
                                  final f = forms.firstWhere(
                                    (f) => f.name == name,
                                  );
                                  items[i].addAll({
                                    'form_name': f.name,
                                    'units_per_form': f.unitsPerForm,
                                    'purchase_cost_cents': null,
                                  });
                                }),
                              );
                            },
                          ),
                          TextField(
                            controller: fields[i],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity of forms',
                            ),
                          ),
                          if (items.length > 1)
                            TextButton.icon(
                              onPressed: () => update(() {
                                items.removeAt(i);
                                fields.removeAt(i).dispose();
                              }),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Remove line'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (fields.any((f) => (int.tryParse(f.text) ?? 0) <= 0)) return;
                for (final item in items) {
                  final p = products
                      .where((p) => p.code == item['product_code'])
                      .firstOrNull;
                  if (p == null ||
                      !p.forms.any(
                        (f) =>
                            f.name == item['form_name'] &&
                            f.unitsPerForm == item['units_per_form'],
                      )) {
                    return;
                  }
                }
                Navigator.pop(context, true);
              },
              child: const Text('Resubmit'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      details['supplier_name'] = supplier.text.trim();
      details['invoice_number'] = invoice.text.trim();
      for (var i = 0; i < items.length; i++) {
        items[i]['quantity_forms'] = int.parse(fields[i].text);
        items[i]['quantity_base'] =
            items[i]['quantity_forms'] * items[i]['units_per_form'];
      }
    }
    for (final field in fields) {
      field.dispose();
    }
    supplier.dispose();
    invoice.dispose();
    if (accepted == true) {
      await _run(() => widget.controller.resubmitWorkflow(row, details));
    }
  }
}

Future<String?> workflowReason(BuildContext context, String title) async {
  final field = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Required reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (field.text.trim().isNotEmpty) Navigator.pop(context, true);
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
  final reason = field.text.trim();
  field.dispose();
  return accepted == true ? reason : null;
}

class PendingPrintPage extends StatelessWidget {
  const PendingPrintPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pending receipts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (controller.pendingPrintReceipts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No pending receipts'),
            ),
          ),
        if (controller.pendingPrintReceipts.isNotEmpty &&
            !controller.printer.isReady)
          Card(
            child: ListTile(
              leading: const Icon(Icons.print_disabled_outlined),
              title: const Text('Connect a configured printer'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PrinterSettingsScreen(controller: controller),
                ),
              ),
            ),
          ),
        for (final sale in controller.pendingPrintReceipts)
          Card(
            child: ListTile(
              title: Text(sale.receiptNumber),
              subtitle: Text(
                '${saleDate(sale.createdAt)} — ${controller.printStates[sale.transactionUuid] == 'check print result' ? 'Check the printed receipt before retrying' : 'Waiting to print'}',
              ),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Review / print'),
                onPressed: () =>
                    showReceipt(context, sale, controller: controller),
              ),
            ),
          ),
      ],
    ),
  );
}
