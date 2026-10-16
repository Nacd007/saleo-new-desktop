import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'formatters.dart';
import 'models.dart';
import 'workflow_pages.dart';

bool useSideNavigation(
  BuildContext context,
  AppNavigationPreference preference,
) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 720;
}

class PrinterStatusChip extends StatelessWidget {
  const PrinterStatusChip({
    super.key,
    required this.controller,
    this.iconOnly = false,
  });
  final AppController controller;
  final bool iconOnly;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, controller.printer]),
    builder: (context, _) {
      final count = controller.pendingPrintReceipts.length;
      final ready = controller.printer.isReady;
      final color = ready
          ? Colors.green.shade700
          : Theme.of(context).colorScheme.onSurfaceVariant;
      final symbol = Icon(
        ready ? Icons.print_outlined : Icons.print_disabled_outlined,
        color: color,
      );
      return IconButton(
        tooltip: count == 0
            ? 'No pending receipts'
            : 'Pending receipts · $count',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Pending receipts')),
              body: PendingPrintPage(controller: controller),
            ),
          ),
        ),
        icon: count == 0
            ? symbol
            : Badge(
                backgroundColor: Colors.red.shade700,
                label: Text('$count'),
                child: symbol,
              ),
      );
    },
  );
}

class SyncBadge extends StatelessWidget {
  const SyncBadge({
    super.key,
    required this.controller,
    this.compact = false,
    this.iconOnly = false,
  });

  final AppController controller;
  final bool compact;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (controller.syncState) {
      AppSyncState.syncing => (
        'Syncing',
        Icons.sync,
        Theme.of(context).colorScheme.primary,
      ),
      AppSyncState.synced => (
        'Synced',
        Icons.cloud_done_outlined,
        Colors.green,
      ),
      AppSyncState.offline => (
        'Offline',
        Icons.cloud_off_outlined,
        Colors.orange,
      ),
      AppSyncState.failed => (
        'Pending',
        Icons.cloud_upload_outlined,
        Colors.orange,
      ),
      AppSyncState.notConfigured => (
        'Setup needed',
        Icons.settings_ethernet,
        Colors.blueGrey,
      ),
      AppSyncState.idle => (
        'Checking',
        Icons.cloud_queue_outlined,
        Colors.blueGrey,
      ),
    };
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(icon, size: 21, color: color),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.supportingText,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? supportingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: .11),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (supportingText != null) ...[
                      const Spacer(),
                      Text(
                        supportingText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showReceipt(
  BuildContext context,
  Sale sale, {
  bool reprint = false,
  AppController? controller,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.storefront_rounded, size: 38),
            const SizedBox(height: 8),
            Text(
              controller?.receiptTemplate.shopName ?? 'Saleo Shop',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (controller?.receiptTemplate.location.isNotEmpty ?? false)
              Text(
                controller!.receiptTemplate.location,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            if (controller?.receiptTemplate.phoneNumber.isNotEmpty ?? false)
              Text(
                'Tel: ${controller!.receiptTemplate.phoneNumber}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            const Text('Sales receipt', textAlign: TextAlign.center),
            if (reprint)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'REPRINT',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            const Divider(height: 32),
            if (controller?.receiptTemplate.showReceiptId ?? true)
              _receiptRow(context, 'Receipt', sale.receiptNumber),
            _receiptRow(context, 'Date', saleDate(sale.createdAt)),
            if (sale.debtCents <= 0 &&
                (controller?.receiptTemplate.showCustomerName ?? true) &&
                (sale.customerName?.isNotEmpty ?? false))
              _receiptRow(context, 'Customer', sale.customerName!),
            if (sale.debtCents <= 0 &&
                (controller?.receiptTemplate.showCustomerPhone ?? false) &&
                (sale.customerPhone?.isNotEmpty ?? false))
              _receiptRow(context, 'Phone', sale.customerPhone!),
            if (sale.customerCompany?.isNotEmpty ?? false)
              _receiptRow(context, 'Company', sale.customerCompany!),
            if (sale.collectedBy?.isNotEmpty ?? false)
              _receiptRow(context, 'Received by', sale.collectedBy!),
            _receiptRow(context, sale.operatorLabel, sale.receptionistName),
            const Divider(height: 28),
            _receiptItemHeader(),
            const Divider(height: 12),
            ...sale.items.map(_receiptItemRow),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  'GHS ${money(sale.totalCents)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (sale.mobileMoneyCents > 0)
              _receiptRow(
                context,
                sale.paymentMethod == 'mobile_money_part'
                    ? 'MOMO (part)'
                    : 'MOMO',
                'GHS ${money(sale.mobileMoneyCents)}',
                emphasize: true,
              ),
            if (sale.cashTenderedCents > 0)
              _receiptRow(
                context,
                'Cash received',
                'GHS ${money(sale.cashTenderedCents)}',
                emphasize: true,
              ),
            if (sale.changeGivenCents > 0)
              _receiptRow(
                context,
                'Change',
                'GHS ${money(sale.changeGivenCents)}',
                emphasize: true,
              ),
            if (sale.debtCents > 0) ...[
              if (sale.previousDebtCents > 0)
                _receiptRow(
                  context,
                  'Previous balance',
                  'GHS ${money(sale.previousDebtCents)}',
                ),
              _receiptRow(
                context,
                'Paid today',
                'GHS ${money(sale.cashCents + sale.mobileMoneyCents)}',
              ),
              _receiptRow(
                context,
                'Debt from this sale',
                'GHS ${money(sale.outstandingDebtCents)}',
              ),
              _receiptRow(
                context,
                'TOTAL BALANCE DUE',
                'GHS ${money(sale.previousDebtCents + sale.outstandingDebtCents)}',
                emphasize: true,
              ),
            ],
            const SizedBox(height: 22),
            Text(
              controller?.receiptTemplate.footerMessage ??
                  'Thank you for your business.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by NAPROJEKTS.XYZ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Simple Sales, Smarter Business',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Text(
              '########',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: controller == null
                  ? null
                  : () async {
                      final status =
                          controller.printStates[sale.transactionUuid];
                      if (status == 'check print result' || status == 'sent') {
                        final retry = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Check the previous print'),
                            content: const Text(
                              'The receipt may already have printed. Print another copy?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Print copy'),
                              ),
                            ],
                          ),
                        );
                        if (retry != true) return;
                      }
                      final printed = await controller.printReceipt(sale);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(controller.printer.message),
                          backgroundColor: printed
                              ? const Color(0xFF067647)
                              : Colors.orange.shade800,
                        ),
                      );
                    },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print receipt'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _receiptRow(
  BuildContext context,
  String label,
  String value, {
  bool emphasize = false,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: emphasize ? FontWeight.w600 : null,
        ),
      ),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);

Widget _receiptItemHeader() => const Row(
  children: [
    Expanded(flex: 1, child: Text('Qty', style: _receiptHeaderStyle)),
    SizedBox(width: 6),
    Expanded(flex: 5, child: Text('Description', style: _receiptHeaderStyle)),
    SizedBox(width: 6),
    Expanded(
      flex: 2,
      child: Text(
        'Unit',
        textAlign: TextAlign.right,
        style: _receiptHeaderStyle,
      ),
    ),
    SizedBox(width: 6),
    Expanded(
      flex: 2,
      child: Text(
        'Amount',
        textAlign: TextAlign.right,
        style: _receiptHeaderStyle,
      ),
    ),
  ],
);

Widget _receiptItemRow(SaleItem item) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: 1, child: Text('${item.quantity}')),
      const SizedBox(width: 6),
      Expanded(
        flex: 5,
        child: Text(
          '${item.productName}\n${item.formName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        flex: 2,
        child: Text(money(item.unitPriceCents), textAlign: TextAlign.right),
      ),
      const SizedBox(width: 6),
      Expanded(
        flex: 2,
        child: Text(
          money(item.lineTotalCents),
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  ),
);

const _receiptHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

class SalesList extends StatelessWidget {
  const SalesList({
    super.key,
    required this.sales,
    this.canVoid = false,
    this.onVoid,
    this.controller,
    this.footer,
  });

  final List<Sale> sales;
  final bool canVoid;
  final Future<void> Function(Sale sale)? onVoid;
  final AppController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const Center(child: Text('No completed sales yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: sales.length + (footer == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == sales.length) return footer!;
        final sale = sales[index];
        if (controller != null) {
          return _ExpandableSale(
            sale: sale,
            controller: controller!,
            key: ValueKey(sale.transactionUuid),
          );
        }
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            onTap: () => showReceipt(
              context,
              sale,
              reprint: true,
              controller: controller,
            ),
            leading: CircleAvatar(
              backgroundColor: sale.voided
                  ? Colors.red.shade50
                  : Colors.green.shade50,
              child: Icon(
                sale.voided ? Icons.block : Icons.receipt_long_outlined,
                color: sale.voided ? Colors.red : Colors.green,
              ),
            ),
            title: Text(
              sale.receiptNumber,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${saleDate(sale.createdAt)}\n${sale.receptionistName}${sale.voided ? ' - VOID' : ''}',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(sale.totalCents),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Icon(
                      sale.isSynced
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      size: 16,
                      color: sale.isSynced ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
                if (canVoid && !sale.voided)
                  PopupMenuButton<String>(
                    tooltip: 'Sale actions',
                    onSelected: (value) {
                      if (value == 'void') onVoid?.call(sale);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'void', child: Text('Void sale')),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExpandableSale extends StatefulWidget {
  const _ExpandableSale({
    super.key,
    required this.sale,
    required this.controller,
  });
  final Sale sale;
  final AppController controller;
  @override
  State<_ExpandableSale> createState() => _ExpandableSaleState();
}

class _ExpandableSaleState extends State<_ExpandableSale> {
  bool open = false;
  bool busy = false;
  Future<void> _correct() async {
    final field = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct sale: void and replace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The original receipt stays in the audit trail. Approval restores its stock; create the corrected sale afterwards. Do not use this for refunds or collected debt.',
            ),
            TextField(
              controller: field,
              decoration: const InputDecoration(labelText: 'Required reason'),
              maxLines: 3,
            ),
          ],
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
            child: const Text('Submit correction'),
          ),
        ],
      ),
    );
    field.dispose();
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.controller.requestSaleCorrection(widget.sale, reason);
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
    final s = widget.sale;
    final user = widget.controller.currentUser;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text('${s.receiptNumber}${s.voided ? ' — VOID' : ''}'),
            subtitle: Text('${saleDate(s.createdAt)} · ${s.receptionistName}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('GHS ${money(s.totalCents)}'),
                IconButton(
                  tooltip: open ? 'Close transaction' : 'Expand transaction',
                  onPressed: () => setState(() => open = !open),
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Company: ${s.customerCompany ?? '—'}\nCustomer: ${s.customerName ?? 'Walk-in'}\nReceived by: ${s.collectedBy ?? '—'}\nReceiver phone: ${s.collectorPhone ?? '—'}\nRecorded by: ${s.receptionistName}\nPayment: ${s.paymentMethod}',
                  ),
                  for (final item in s.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${item.quantity} ${item.formName} · ${item.productName}',
                      ),
                      trailing: Text('GHS ${money(item.lineTotalCents)}'),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => showReceipt(
                          context,
                          s,
                          reprint: true,
                          controller: widget.controller,
                        ),
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Receipt / print'),
                      ),
                      if (!s.voided &&
                          (user?.role == UserRole.admin ||
                              user?.username == s.receptionistUsername))
                        OutlinedButton.icon(
                          onPressed: busy ? null : _correct,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Request correction'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
