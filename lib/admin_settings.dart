import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'appearance_settings.dart';
import 'auth_service.dart';
import 'company_id_image_service.dart';
import 'formatters.dart';
import 'models.dart';
import 'notifications_page.dart';
import 'printer_settings.dart';
import 'product_performance.dart';
import 'stock_movement_report.dart';
import 'session_widgets.dart';
import 'sync_service.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({
    super.key,
    required this.controller,
    required this.staffPageBuilder,
  });
  final AppController controller;
  final WidgetBuilder staffPageBuilder;

  @override
  Widget build(BuildContext context) {
    void open(String title, Widget page) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: page,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.titleMedium),
        if (controller.currentCompany != null)
          _SettingsTile(
            icon: Icons.badge_outlined,
            title: 'Company details',
            subtitle: 'Company ID and company information',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CompanyDetailsScreen(controller: controller),
              ),
            ),
          ),
        _SettingsTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin profile',
          subtitle: 'Manage the username used for sign in',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AdminAccountScreen(controller: controller),
            ),
          ),
        ),
        const Divider(),
        _SettingsTile(
          icon: Icons.palette_outlined,
          title: 'Appearance & navigation',
          subtitle: 'Light or dark mode; fixed side navigation on tablets',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AppearanceSettingsScreen(controller: controller),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.notifications_active_outlined,
          title: 'Alerts & notifications',
          subtitle: 'Sales, low stock, expiry and device alerts',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  NotificationSettingsScreen(controller: controller),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.inventory_outlined,
          title: 'Inventory reports',
          subtitle: 'Stock movement and product performance',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InventoryReportsScreen(controller: controller),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.people_outline,
          title: 'Staff management',
          subtitle: 'Staff access and receiving permissions',
          onTap: () => open(
            'Staff management',
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Column(
                children: [
                  SwitchListTile(
                    title: const Text('Allow staff to receive stock'),
                    subtitle: const Text(
                      'Received stock still requires administrator approval.',
                    ),
                    value: controller.inventoryPreferences.staffCanReceiveStock,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      controller.inventoryPreferences.copyWith(
                        staffCanReceiveStock: value,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Use Staff in the navigation to add staff, edit profiles and manage PINs.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.receipt_long_outlined,
          title: 'Receipt template',
          subtitle: 'Company details and receipt formatting',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReceiptTemplateScreen(controller: controller),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.print_outlined,
          title: 'Printer & synchronization',
          subtitle: 'Connect and test this device’s receipt printer',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PrinterSettingsScreen(controller: controller),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(controller.signingOut ? 'Signing out…' : 'Log out'),
          onTap: controller.signingOut
              ? null
              : () => confirmSignOut(context, controller),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class DebtorsScreen extends StatefulWidget {
  const DebtorsScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  final _search = TextEditingController();
  bool _overdueOnly = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onDebtorsChanged);
  }

  @override
  void didUpdateWidget(covariant DebtorsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDebtorsChanged);
      widget.controller.addListener(_onDebtorsChanged);
    }
  }

  void _onDebtorsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDebtorsChanged);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final totalOutstanding = controller.debtors.fold<int>(
      0,
      (sum, item) => sum + item.outstandingCents,
    );
    final overdue = controller.debtors.where((item) => item.isOverdue).length;
    final query = _search.text.trim().toLowerCase();
    final filtered =
        controller.debtors.where((debtor) {
            if (_overdueOnly && !debtor.isOverdue) return false;
            if (query.isEmpty) return true;
            return debtor.customerName.toLowerCase().contains(query) ||
                debtor.customerPhone.toLowerCase().contains(query) ||
                debtor.companyName.toLowerCase().contains(query);
          }).toList()
          ..sort((a, b) => b.outstandingCents.compareTo(a.outstandingCents));
    final outstandingAccounts = filtered
        .where((d) => d.outstandingCents > 0)
        .toList();
    final settledAccounts = filtered
        .where((d) => d.outstandingCents == 0)
        .toList();

    final content = RefreshIndicator(
      onRefresh: controller.refresh,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
            children: [
              Text(
                'Credit control',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Search debtors, review outstanding balances and record payments.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ReportPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Outstanding',
                    value: 'GHS ${money(totalOutstanding)}',
                  ),
                  _ReportPill(
                    icon: Icons.people_outline,
                    label: 'Debtors',
                    value:
                        '${controller.debtors.where((d) => d.outstandingCents > 0).length}',
                  ),
                  _ReportPill(
                    icon: Icons.warning_amber_outlined,
                    label: 'Overdue',
                    value: '$overdue',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Search debtors',
                            hintText: 'Company, receiver or phone number',
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
                      ),
                      const SizedBox(width: 12),
                      FilterChip(
                        selected: _overdueOnly,
                        avatar: const Icon(Icons.warning_amber_outlined),
                        label: const Text('Overdue only'),
                        onSelected: (value) =>
                            setState(() => _overdueOnly = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.debtors.isEmpty
                          ? 'No debt sales recorded yet.'
                          : 'No debtors match this search.',
                    ),
                  ),
                )
              else ...[
                if (outstandingAccounts.isNotEmpty)
                  Text(
                    'Outstanding accounts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ...outstandingAccounts.map(
                  (debtor) => _debtorCard(context, debtor),
                ),
                if (settledAccounts.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Divider(),
                  Text(
                    'Settled accounts',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Fully paid accounts remain here with their complete transaction history.',
                  ),
                  const SizedBox(height: 8),
                  ...settledAccounts.map(
                    (debtor) => _debtorCard(context, debtor),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Debtors')),
      body: content,
    );
  }

  Widget _debtorCard(BuildContext context, DebtorSummary debtor) {
    final displayName = debtor.companyName.trim().isNotEmpty
        ? debtor.companyName.trim()
        : debtor.customerName.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          child: Text(displayName.isEmpty ? '?' : displayName[0].toUpperCase()),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (debtor.customerName.trim() != displayName)
              'Received by ${debtor.customerName}',
            debtor.customerPhone,
            '${debtor.saleCount} credit sale(s)',
            if (debtor.isOverdue) 'Overdue',
          ].where((item) => item.trim().isNotEmpty).join('  •  '),
        ),
        trailing: SizedBox(
          width: 190,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'GHS ${money(debtor.outstandingCents)}',
                style: TextStyle(
                  color: debtor.isOverdue
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                debtor.outstandingCents == 0
                    ? 'Settled • Paid GHS ${money(debtor.paidCents)}'
                    : 'Paid GHS ${money(debtor.paidCents)}',
              ),
            ],
          ),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _DebtorDetailScreen(
              controller: widget.controller,
              debtor: debtor,
            ),
          ),
        ),
      ),
    );
  }
}

class _DebtorDetailScreen extends StatefulWidget {
  const _DebtorDetailScreen({required this.controller, required this.debtor});

  final AppController controller;
  final DebtorSummary debtor;

  @override
  State<_DebtorDetailScreen> createState() => _DebtorDetailScreenState();
}

class _DebtorDetailScreenState extends State<_DebtorDetailScreen> {
  late Future<List<DebtLedgerEntry>> _ledger;
  bool _recordingPayment = false;
  DebtorSummary get _currentDebtor => widget.controller.debtors.firstWhere(
    (d) => d.customerPhone == widget.debtor.customerPhone,
    orElse: () => widget.debtor,
  );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _ledger = widget.controller.debtLedger(widget.debtor);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.debtor.companyName.isNotEmpty
            ? widget.debtor.companyName
            : widget.debtor.customerName,
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: !_recordingPayment && _currentDebtor.outstandingCents > 0
          ? _recordPayment
          : null,
      icon: const Icon(Icons.payments_outlined),
      label: const Text('Record payment'),
    ),
    body: FutureBuilder<List<DebtLedgerEntry>>(
      future: _ledger,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load the debt ledger. Please try again.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outstanding: GHS ${money(_currentDebtor.outstandingCents)}',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w500, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.debtor.customerName),
                    Text(widget.debtor.customerPhone),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No debt activity recorded.'),
                ),
              )
            else
              ...entries.map(_ledgerCard),
          ],
        );
      },
    ),
  );

  Widget _ledgerCard(DebtLedgerEntry entry) => Card(
    child: ExpansionTile(
      leading: CircleAvatar(
        child: Icon(entry.isPayment ? Icons.south_west : Icons.receipt_long),
      ),
      title: Text(
        entry.isPayment
            ? 'Payment: GHS ${money(entry.amountCents)}'
            : 'Purchase: GHS ${money(entry.amountCents)} debt',
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      subtitle: Text(
        '${_debtDate(entry.createdAt)} • Balance GHS ${money(entry.balanceAfterCents)}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (entry.receiptNumber != null)
          _detailLine('Receipt', entry.receiptNumber!),
        _detailLine('Date', _debtDate(entry.createdAt)),
        _detailLine(
          'Company / customer',
          entry.companyName.isNotEmpty ? entry.companyName : entry.customerName,
        ),
        if (entry.customerPhone.isNotEmpty)
          _detailLine('Company contact', entry.customerPhone),
        if (entry.isPayment) ...[
          _detailLine('Paid by', entry.payerName ?? 'Not recorded'),
          _detailLine('Payer phone', entry.payerPhone ?? 'Not recorded'),
          OutlinedButton.icon(
            onPressed: () => _printPayment(entry),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print payment receipt'),
          ),
        ],
        if (entry.collectedBy?.isNotEmpty ?? false)
          _detailLine('Received by', entry.collectedBy!),
        if (entry.collectorPhone?.isNotEmpty ?? false)
          _detailLine('Receiver phone', entry.collectorPhone!),
        if (entry.recordedBy?.isNotEmpty ?? false)
          _detailLine(
            entry.isPayment ? 'Payment recorded by' : 'Recorded by',
            entry.recordedBy!,
          ),
        const Divider(),
        _detailLine(
          'Previous outstanding balance',
          'GHS ${money(entry.balanceBeforeCents)}',
        ),
        if (!entry.isPayment) ...[
          if (entry.purchaseTotalCents != null)
            _detailLine(
              'New purchase total',
              'GHS ${money(entry.purchaseTotalCents!)}',
            ),
          _detailLine(
            'Paid at checkout',
            'GHS ${money(entry.paidAtPurchaseCents)}',
          ),
          _detailLine('New credit added', 'GHS ${money(entry.amountCents)}'),
        ] else
          _detailLine('Payment received', 'GHS ${money(entry.amountCents)}'),
        _detailLine(
          'Balance after this transaction',
          'GHS ${money(entry.balanceAfterCents)}',
        ),
        const Padding(
          padding: EdgeInsets.only(top: 5, bottom: 8),
          child: Text(
            'Historical balance at this transaction, not today’s balance.',
            style: TextStyle(fontSize: 11),
          ),
        ),
        if (entry.paymentMethod?.isNotEmpty ?? false)
          _detailLine('Payment method', entry.paymentMethod!),
        if (entry.items.isNotEmpty) ...[
          const Divider(),
          ...entry.items.map(
            (item) => _detailLine(
              '${item.quantity} × ${item.productName} (${item.formName})',
              'GHS ${money(item.lineTotalCents)}',
            ),
          ),
        ],
        if (entry.note?.isNotEmpty ?? false) _detailLine('Note', entry.note!),
      ],
    ),
  );

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Future<void> _recordPayment() async {
    if (_recordingPayment) return;
    setState(() => _recordingPayment = true);
    try {
      await _recordPaymentDialog();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment could not be recorded: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _recordingPayment = false);
    }
  }

  Future<void> _recordPaymentDialog() async {
    final amount = TextEditingController();
    final momo = TextEditingController();
    final note = TextEditingController();
    final payerName = TextEditingController();
    final payerPhone = TextEditingController();
    var method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final amountCents = _moneyCents(amount.text);
          final momoCents = _moneyCents(momo.text);
          final valid =
              payerName.text.trim().isNotEmpty &&
              payerPhone.text.trim().length >= 3 &&
              amountCents > 0 &&
              amountCents <= _currentDebtor.outstandingCents &&
              (method != 'cash_momo' ||
                  (momoCents > 0 && momoCents < amountCents));
          return AlertDialog(
            title: const Text('Record debt payment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: payerName,
                    decoration: const InputDecoration(
                      labelText: 'Person making payment (required)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: payerPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Payer phone number (required)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount paid',
                      prefixText: 'GHS ',
                      helperText:
                          'Outstanding: GHS ${money(_currentDebtor.outstandingCents)}',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: 'Paid through',
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
                      method = value ?? 'cash';
                    }),
                  ),
                  if (method == 'cash_momo') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: momo,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'MOMO amount',
                        prefixText: 'GHS ',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Reference or note (optional)',
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
                onPressed: valid ? () => Navigator.pop(context, true) : null,
                child: const Text('Save payment'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;
    final amountCents = _moneyCents(amount.text);
    final momoCents = method == 'momo'
        ? amountCents
        : method == 'cash_momo'
        ? _moneyCents(momo.text)
        : 0;
    final payment = await widget.controller.recordDebtPayment(
      debtor: _currentDebtor,
      amountCents: amountCents,
      cashCents: amountCents - momoCents,
      mobileMoneyCents: momoCents,
      payerName: payerName.text,
      payerPhone: payerPhone.text,
      note: note.text,
    );
    if (!mounted) return;
    setState(_reload);
    final printNow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment recorded'),
        content: Text(
          'GHS ${money(payment.amountCents)} received from ${payment.payerName}.\nRemaining balance: GHS ${money(payment.balanceAfterCents)}.\nPrint a receipt for this payment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Print receipt'),
          ),
        ],
      ),
    );
    if (printNow == true && mounted) await _printPayment(payment);
  }

  Future<void> _printPayment(DebtLedgerEntry payment) async {
    await widget.controller.printDebtPaymentReceipt(payment);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.controller.printer.message)));
  }

  int _moneyCents(String value) =>
      ((double.tryParse(value.trim().replaceAll(',', '')) ?? 0) * 100).round();

  String _debtDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class InventoryReportsScreen extends StatelessWidget {
  const InventoryReportsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final nearExpiry = controller.stockReceipts
        .expand((receipt) => receipt.items)
        .where((item) {
          final expiry = item.expiryDate;
          if (expiry == null) return false;
          final days = expiry.difference(DateTime.now()).inDays;
          return days >= 0 && days <= 30;
        })
        .length;
    final expired = controller.stockReceipts
        .expand((receipt) => receipt.items)
        .where((item) {
          final expiry = item.expiryDate;
          return expiry != null && expiry.isBefore(DateTime.now());
        })
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ReportPill(
                icon: Icons.inventory_2_outlined,
                label: 'Products',
                value: '${controller.products.length}',
              ),
              _ReportPill(
                icon: Icons.warning_amber_outlined,
                label: 'Low stock',
                value: '${controller.lowStockProducts.length}',
              ),
              _ReportPill(
                icon: Icons.event_busy_outlined,
                label: 'Near expiry',
                value: '$nearExpiry',
              ),
              _ReportPill(
                icon: Icons.dangerous_outlined,
                label: 'Expired',
                value: '$expired',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsTile(
            icon: Icons.swap_vert_outlined,
            title: 'Stock movement report',
            subtitle: 'Review received, sold and adjusted stock',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    StockMovementReportScreen(controller: controller),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.trending_up_outlined,
            title: 'Product performance',
            subtitle: 'High movers, low movers, quantities and categories',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Product performance')),
                  body: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ProductPerformanceCard(controller: controller),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportPill extends StatelessWidget {
  const _ReportPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    ),
  );
}

class AdminAccountScreen extends StatefulWidget {
  const AdminAccountScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AdminAccountScreen> createState() => _AdminAccountScreenState();
}

class _AdminAccountScreenState extends State<AdminAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(
      text: widget.controller.currentUser?.username ?? '',
    );
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updateAdminUsername(_username.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin username updated.')));
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update the username. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin account')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'This changes the username the admin uses with the company ID and 4-digit PIN.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _username,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Admin username',
              helperText:
                  'Letters, numbers, dots, dashes and underscores only.',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              final username = value?.trim() ?? '';
              if (username.length < 2) return 'Enter a username';
              if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
                return 'Use only letters, numbers, dots, dashes and underscores';
              }
              return null;
            },
            onFieldSubmitted: (_) => _save(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save username'),
        ),
      ],
    ),
  );
}

const _operatorPresets = [
  'Operator',
  'Receptionist',
  'Cashier',
  'Salesperson',
  'Served by',
  'Custom',
];

class ReceiptTemplateScreen extends StatefulWidget {
  const ReceiptTemplateScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ReceiptTemplateScreen> createState() => _ReceiptTemplateScreenState();
}

class _ReceiptTemplateScreenState extends State<ReceiptTemplateScreen> {
  late final TextEditingController _shopName;
  late final TextEditingController _location;
  late final TextEditingController _phone;
  late final TextEditingController _footer;
  late final TextEditingController _operatorLabel;
  late bool _showCustomer;
  late bool _showReceiptId;
  late bool _showCustomerPhone;
  late bool _useStaffRole;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.receiptTemplateSettings;
    _apply(settings.customTemplate ?? settings.defaultTemplate);
  }

  void _apply(ReceiptTemplate template) {
    _shopName = TextEditingController(text: template.shopName);
    _location = TextEditingController(text: template.location);
    _phone = TextEditingController(text: template.phoneNumber);
    _footer = TextEditingController(text: template.footerMessage);
    _operatorLabel = TextEditingController(text: template.operatorLabel);
    _showCustomer = template.showCustomerName;
    _showReceiptId = template.showReceiptId;
    _showCustomerPhone = template.showCustomerPhone;
    _useStaffRole = template.useStaffRole;
  }

  ReceiptTemplate get _value => ReceiptTemplate(
    shopName: _shopName.text.trim(),
    location: _location.text.trim(),
    phoneNumber: _phone.text.trim(),
    showCustomerName: _showCustomer,
    showReceiptId: _showReceiptId,
    showCustomerPhone: _showCustomerPhone,
    operatorLabel: _operatorLabel.text.trim(),
    useStaffRole: _useStaffRole,
    footerMessage: _footer.text.trim(),
  );

  @override
  void dispose() {
    _shopName.dispose();
    _location.dispose();
    _phone.dispose();
    _footer.dispose();
    _operatorLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.receiptTemplateSettings;
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt templates')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            'Every company has the Saleo default and can create one custom template.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: const Text('Saleo default'),
                  subtitle: const Text(
                    'Always available and cannot be changed',
                  ),
                  trailing:
                      settings.active == ReceiptTemplateKind.defaultTemplate
                      ? const Chip(label: Text('Active'))
                      : TextButton(
                          onPressed: () => _selectTemplate(
                            ReceiptTemplateKind.defaultTemplate,
                          ),
                          child: const Text('Use'),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('Custom template'),
                  subtitle: Text(
                    settings.customTemplate == null
                        ? 'Not created yet — one custom template is allowed'
                        : 'Stored for this company and editable at any time',
                  ),
                  trailing: settings.active == ReceiptTemplateKind.custom
                      ? const Chip(label: Text('Active'))
                      : settings.customTemplate == null
                      ? null
                      : TextButton(
                          onPressed: () =>
                              _selectTemplate(ReceiptTemplateKind.custom),
                          child: const Text('Use'),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    settings.customTemplate == null
                        ? 'Create custom template'
                        : 'Edit custom template',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saving updates the company’s single custom template and makes it active.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _shopName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Shop name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _location,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Shop location',
                      hintText: 'Optional',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Shop phone number',
                      hintText: 'Optional',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _footer,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Closing message',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _operatorPresets.contains(_operatorLabel.text.trim())
                        ? _operatorLabel.text.trim()
                        : 'Custom',
                    decoration: const InputDecoration(
                      labelText: 'Staff title on receipt',
                    ),
                    items: _operatorPresets
                        .map(
                          (label) => DropdownMenuItem(
                            value: label,
                            child: Text(label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      if (value != null && value != 'Custom') {
                        _operatorLabel.text = value;
                      } else if (value == 'Custom' &&
                          _operatorPresets.contains(_operatorLabel.text)) {
                        _operatorLabel.clear();
                      }
                    }),
                  ),
                  if (!_operatorPresets.contains(
                    _operatorLabel.text.trim(),
                  )) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _operatorLabel,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Custom staff title',
                        hintText: 'For example: Served by',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Use each staff member's job role"),
                    subtitle: const Text(
                      'Uses Cashier, Storekeeper or their saved role. This changes wording only.',
                    ),
                    value: _useStaffRole,
                    onChanged: (value) => setState(() => _useStaffRole = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show customer name when entered'),
                    value: _showCustomer,
                    onChanged: (value) => setState(() => _showCustomer = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show customer phone when entered'),
                    value: _showCustomerPhone,
                    onChanged: (value) =>
                        setState(() => _showCustomerPhone = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show receipt ID'),
                    value: _showReceiptId,
                    onChanged: (value) =>
                        setState(() => _showReceiptId = value),
                  ),
                  const SizedBox(height: 12),
                  _ReceiptPreview(template: _value),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        widget.controller.busy || _shopName.text.trim().isEmpty
                        ? null
                        : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      settings.customTemplate == null
                          ? 'Create custom template'
                          : 'Save custom template',
                    ),
                  ),
                  TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : _copyDefaultIntoEditor,
                    child: const Text('Copy fields from Saleo default'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    try {
      await widget.controller.saveReceiptTemplate(_value);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt template saved for the company.'),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _selectTemplate(ReceiptTemplateKind selection) async {
    await widget.controller.selectReceiptTemplate(selection);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selection.label} receipt template selected.')),
    );
  }

  void _copyDefaultIntoEditor() {
    final defaults = widget.controller.receiptTemplateSettings.defaultTemplate;
    _shopName.text = defaults.shopName;
    _location.text = defaults.location;
    _phone.text = defaults.phoneNumber;
    _footer.text = defaults.footerMessage;
    setState(() {
      _showCustomer = defaults.showCustomerName;
      _showReceiptId = defaults.showReceiptId;
      _showCustomerPhone = defaults.showCustomerPhone;
      _useStaffRole = defaults.useStaffRole;
      _operatorLabel.text = defaults.operatorLabel;
    });
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.template});

  final ReceiptTemplate template;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          'PREVIEW',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          template.shopName.isEmpty ? 'Shop name' : template.shopName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (template.location.isNotEmpty) Text(template.location),
        if (template.phoneNumber.isNotEmpty)
          Text('Tel: ${template.phoneNumber}'),
        const Text('Date: 09/09/2026 11:31'),
        if (template.showCustomerName) const Text('Customer: Customer name'),
        if (template.showCustomerPhone) const Text('Phone: 024 000 0000'),
        if (template.showReceiptId) const Text('Receipt: RCP-EXAMPLE'),
        Text(
          '${template.useStaffRole ? 'Cashier' : template.operatorLabel}: Ama',
        ),
        const Divider(height: 24),
        const Row(
          children: [
            Expanded(flex: 1, child: Text('Qty', style: _previewHeaderStyle)),
            Expanded(
              flex: 5,
              child: Text('Description', style: _previewHeaderStyle),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Unit',
                textAlign: TextAlign.right,
                style: _previewHeaderStyle,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                'Amount',
                textAlign: TextAlign.right,
                style: _previewHeaderStyle,
              ),
            ),
          ],
        ),
        const Divider(height: 12),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: Text('2')),
            Expanded(flex: 5, child: Text('Mineral Water\nCarton')),
            Expanded(flex: 2, child: Text('48.00', textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('96.00', textAlign: TextAlign.right)),
          ],
        ),
        const Divider(height: 24),
        if (template.footerMessage.isNotEmpty) Text(template.footerMessage),
        const SizedBox(height: 6),
        const Text(
          'Powered by NAPROJEKTS.XYZ',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        ),
        const Text(
          'Simple Sales, Smarter Business',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        ),
        const Text(
          '########',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 10),
      ],
    ),
  );
}

const _previewHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

class CompanyDetailsScreen extends StatelessWidget {
  const CompanyDetailsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final company = controller.currentCompany;
    return Scaffold(
      appBar: AppBar(title: const Text('Company details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 52),
                  const SizedBox(height: 14),
                  Text(
                    company?.name ?? 'Saleo company',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  const Text('YOUR COMPANY ID'),
                  const SizedBox(height: 6),
                  SelectableText(
                    company?.companyId ?? 'Not available',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use this ID when signing in. Your PIN is still required.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: company == null
                        ? null
                        : () => _saveCompanyId(context, company),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Save company ID as picture'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCompanyId(
    BuildContext context,
    CompanyPreview company,
  ) async {
    try {
      final location = await const CompanyIdImageService().save(
        companyName: company.name,
        companyId: company.companyId,
      );
      if (!context.mounted || location == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Company ID picture saved to $location')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the picture: $error')),
      );
    }
  }
}

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer contacts')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final customers = controller.customers;
        if (customers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No customers saved yet. Customer details are saved when they are entered during checkout.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${customers.length} saved customer${customers.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Names and phone numbers collected during sales are saved here for this company.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: customers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          customer.name.isEmpty
                              ? '?'
                              : customer.name.substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Text(
                        customer.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${customer.phone}\n${customer.purchaseCount} purchase${customer.purchaseCount == 1 ? '' : 's'} • GHS ${money(customer.totalSpentCents)}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _edit(context, customer);
                          if (value == 'delete') _delete(context, customer);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _edit(BuildContext context, CustomerRecord customer) async {
    final name = TextEditingController(text: customer.name);
    final phone = TextEditingController(text: customer.phone);
    final company = TextEditingController(text: customer.companyName);
    final address = TextEditingController(text: customer.address);
    String? validationError;
    final save =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Edit customer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (validationError != null)
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: company,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Company name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: address,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Business address or location',
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
                  onPressed: () {
                    final issues = customerSyncIssues({
                      ...customer.toSyncJson(),
                      'name': name.text.trim().isEmpty
                          ? phone.text.trim()
                          : name.text.trim(),
                      'phone': phone.text.trim(),
                      'company_name': company.text.trim(),
                      'address': address.text.trim(),
                    });
                    if (issues.isNotEmpty) {
                      setDialogState(
                        () => validationError =
                            'Correct ${issues.join(', ')} before saving. Phone needs 3–40 characters.',
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!save || phone.text.trim().isEmpty) return;
    await controller.updateCustomer(
      customer,
      name: name.text,
      phone: phone.text,
      companyName: company.text,
      address: address.text,
    );
  }

  Future<void> _delete(BuildContext context, CustomerRecord customer) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${customer.name}?'),
            content: const Text(
              'This removes the saved customer contact. Existing sales and receipt snapshots remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.deleteCustomer(customer);
  }
}

enum _CustomerPeriod { today, week, month, year, all }

extension _CustomerPeriodLabel on _CustomerPeriod {
  String get label => switch (this) {
    _CustomerPeriod.today => 'Today',
    _CustomerPeriod.week => 'This week',
    _CustomerPeriod.month => 'This month',
    _CustomerPeriod.year => 'This year',
    _CustomerPeriod.all => 'All',
  };

  DateTime? get start {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _CustomerPeriod.today => today,
      _CustomerPeriod.week => today.subtract(Duration(days: now.weekday - 1)),
      _CustomerPeriod.month => DateTime(now.year, now.month),
      _CustomerPeriod.year => DateTime(now.year),
      _CustomerPeriod.all => null,
    };
  }
}

class EnhancedCustomersScreen extends StatefulWidget {
  const EnhancedCustomersScreen({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  State<EnhancedCustomersScreen> createState() =>
      _EnhancedCustomersScreenState();
}

class _EnhancedCustomersScreenState extends State<EnhancedCustomersScreen> {
  final _search = TextEditingController();
  _CustomerPeriod _period = _CustomerPeriod.all;
  String _query = '';
  bool _needsCorrectionOnly = false;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(title: const Text('Customer contacts')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final start = _period.start;
        final query = _query.trim().toLowerCase();
        final invalidCount = controller.customers
            .where(
              (customer) =>
                  customerSyncIssues(customer.toSyncJson()).isNotEmpty ||
                  controller.syncService.rejectedCustomerPhones.contains(
                    customer.phone,
                  ),
            )
            .length;
        final customers =
            controller.customers.where((customer) {
              if (_needsCorrectionOnly &&
                  customerSyncIssues(customer.toSyncJson()).isEmpty &&
                  !controller.syncService.rejectedCustomerPhones.contains(
                    customer.phone,
                  )) {
                return false;
              }
              final purchaseDate = customer.lastPurchaseAt?.toLocal();
              final inPeriod =
                  _needsCorrectionOnly ||
                  start == null ||
                  (purchaseDate != null && !purchaseDate.isBefore(start));
              final searchable =
                  '${customer.name} ${customer.phone} ${customer.companyName} ${customer.address}'
                      .toLowerCase();
              return inPeriod && (query.isEmpty || searchable.contains(query));
            }).toList()..sort((a, b) {
              final aInvalid =
                  customerSyncIssues(a.toSyncJson()).isNotEmpty ||
                  controller.syncService.rejectedCustomerPhones.contains(
                    a.phone,
                  );
              final bInvalid =
                  customerSyncIssues(b.toSyncJson()).isNotEmpty ||
                  controller.syncService.rejectedCustomerPhones.contains(
                    b.phone,
                  );
              return aInvalid == bInvalid ? 0 : (aInvalid ? -1 : 1);
            });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_CustomerPeriod>(
                      segments: _CustomerPeriod.values
                          .map(
                            (period) => ButtonSegment(
                              value: period,
                              label: Text(period.label),
                            ),
                          )
                          .toList(),
                      selected: {_period},
                      onSelectionChanged: (value) =>
                          setState(() => _period = value.first),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search name, phone or company',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      helperText:
                          '${customers.length} customer${customers.length == 1 ? '' : 's'} shown',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (invalidCount > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: Text('Needs correction ($invalidCount)'),
                        selected: _needsCorrectionOnly,
                        onSelected: (selected) =>
                            setState(() => _needsCorrectionOnly = selected),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: customers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No customers match this search or period.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: customers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        final issues = customerSyncIssues(
                          customer.toSyncJson(),
                        );
                        final serverRejected = controller
                            .syncService
                            .rejectedCustomerPhones
                            .contains(customer.phone);
                        final canEdit =
                            controller.currentUser?.role == UserRole.admin;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                customer.name.isEmpty
                                    ? '?'
                                    : customer.name
                                          .substring(0, 1)
                                          .toUpperCase(),
                              ),
                            ),
                            title: Text(
                              customer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (issues.isNotEmpty || serverRejected)
                                  'Needs correction: ${issues.isEmpty ? 'server rejected this contact' : issues.join(', ')}. ${canEdit ? 'Tap to edit.' : 'Ask an administrator to edit it on this device.'}',
                                customer.phone,
                                if (customer.companyName.isNotEmpty)
                                  customer.companyName,
                                if (customer.address.isNotEmpty)
                                  customer.address,
                                '${customer.purchaseCount} purchase${customer.purchaseCount == 1 ? '' : 's'} • GHS ${money(customer.totalSpentCents)}',
                              ].join('\n'),
                            ),
                            isThreeLine: true,
                            onTap:
                                canEdit && (issues.isNotEmpty || serverRejected)
                                ? () => _edit(context, customer)
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _CustomerDetailsScreen(
                                        controller: controller,
                                        customer: customer,
                                      ),
                                    ),
                                  ),
                            trailing: !canEdit
                                ? null
                                : PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _edit(context, customer);
                                      }
                                      if (value == 'delete') {
                                        _delete(context, customer);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
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
      },
    ),
  );

  Future<void> _edit(BuildContext context, CustomerRecord customer) async {
    final name = TextEditingController(text: customer.name);
    final phone = TextEditingController(text: customer.phone);
    final company = TextEditingController(text: customer.companyName);
    final address = TextEditingController(text: customer.address);
    String? validationError;
    final save =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Edit customer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (validationError != null)
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: company,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Company name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: address,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Business address or location',
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
                  onPressed: () {
                    final issues = customerSyncIssues({
                      ...customer.toSyncJson(),
                      'name': name.text.trim().isEmpty
                          ? phone.text.trim()
                          : name.text.trim(),
                      'phone': phone.text.trim(),
                      'company_name': company.text.trim(),
                      'address': address.text.trim(),
                    });
                    if (issues.isNotEmpty) {
                      setDialogState(
                        () => validationError =
                            'Correct ${issues.join(', ')} before saving. Phone needs 3–40 characters.',
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!save || phone.text.trim().isEmpty) return;
    await controller.updateCustomer(
      customer,
      name: name.text,
      phone: phone.text,
      companyName: company.text,
      address: address.text,
    );
  }

  Future<void> _delete(BuildContext context, CustomerRecord customer) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${customer.name}?'),
            content: const Text(
              'This removes the saved customer contact. Existing sales and receipt snapshots remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.deleteCustomer(customer);
  }
}

class _CustomerDetailsScreen extends StatelessWidget {
  const _CustomerDetailsScreen({
    required this.controller,
    required this.customer,
  });

  final AppController controller;
  final CustomerRecord customer;

  @override
  Widget build(BuildContext context) {
    final phoneKey = customer.phone.replaceAll(RegExp(r'\D'), '');
    final sales = controller.sales.where((sale) {
      final salePhone = sale.customerPhone?.replaceAll(RegExp(r'\D'), '') ?? '';
      return phoneKey.isNotEmpty && salePhone == phoneKey;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(customer.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                customer.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  customer.phone,
                  if (customer.companyName.isNotEmpty) customer.companyName,
                  if (customer.address.isNotEmpty) customer.address,
                  '${customer.purchaseCount} purchase${customer.purchaseCount == 1 ? '' : 's'} • GHS ${money(customer.totalSpentCents)}',
                ].join('\n'),
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Purchase history',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (sales.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No matching sales found on this device yet.'),
              ),
            )
          else
            ...sales.map(
              (sale) => Card(
                child: ExpansionTile(
                  title: Text(
                    '${sale.receiptNumber} • GHS ${money(sale.totalCents)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(saleDate(sale.createdAt)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    ...sale.items.map(
                      (item) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity} × ${item.productName} (${item.formName})',
                            ),
                          ),
                          Text(money(item.lineTotalCents)),
                        ],
                      ),
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
