import 'package:flutter/material.dart';

import 'admin_settings.dart';
import 'app_controller.dart';
import 'desktop_design.dart';
import 'desktop_settings.dart';
import 'models.dart';
import 'notifications_page.dart';
import 'printer_settings.dart';
import 'session_widgets.dart';
import 'workflow_pages.dart';

typedef _Section = ({String id, String label, IconData icon});

/// One settings frame; its nested navigator keeps every detail page inside it.
class DesktopSettingsWorkspace extends StatefulWidget {
  const DesktopSettingsWorkspace({
    super.key,
    required this.controller,
    required this.onClose,
  });
  final AppController controller;
  final VoidCallback onClose;
  @override
  State<DesktopSettingsWorkspace> createState() =>
      _DesktopSettingsWorkspaceState();
}

class _DesktopSettingsWorkspaceState extends State<DesktopSettingsWorkspace> {
  String _selected = 'general', _query = '';
  AppController get c => widget.controller;
  bool get admin => c.currentUser?.role == UserRole.admin;
  List<_Section> get sections => [
    (id: 'general', label: 'General', icon: Icons.tune_rounded),
    if (admin) ...[
      (id: 'company', label: 'Company details', icon: Icons.business_rounded),
      (
        id: 'account',
        label: 'Admin profile',
        icon: Icons.person_outline_rounded,
      ),
    ],
    (id: 'appearance', label: 'Appearance', icon: Icons.palette_outlined),
    (id: 'printers', label: 'Printers & sync', icon: Icons.print_outlined),
    (
      id: 'pending',
      label: 'Pending receipts',
      icon: Icons.receipt_long_outlined,
    ),
    (
      id: 'corrections',
      label: admin ? 'Corrections & approvals' : 'Corrections',
      icon: Icons.edit_note_rounded,
    ),
    (id: 'alerts', label: 'Alerts', icon: Icons.notifications_outlined),
    if (admin) ...[
      (
        id: 'template',
        label: 'Receipt template',
        icon: Icons.description_outlined,
      ),
      (
        id: 'reports',
        label: 'Inventory reports',
        icon: Icons.bar_chart_rounded,
      ),
      (
        id: 'receiving',
        label: 'Staff receiving',
        icon: Icons.inventory_2_outlined,
      ),
      (
        id: 'customers',
        label: 'Customer details',
        icon: Icons.contacts_outlined,
      ),
    ],
    (id: 'rules', label: 'Company rules', icon: Icons.lock_outline_rounded),
    (id: 'help', label: 'Help & support', icon: Icons.help_outline_rounded),
  ];

  void _select(String id) => setState(() => _selected = id);

  Widget _screen(String title, Widget body) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: body,
  );

  Widget _content() => switch (_selected) {
    'appearance' => DesktopThemesPage(
      controller: c,
      onDone: () => _select('general'),
    ),
    'printers' => PrinterSettingsScreen(controller: c),
    'pending' => _screen('Pending receipts', PendingPrintPage(controller: c)),
    'corrections' => _screen(
      'Corrections & approvals',
      ApprovalPage(controller: c),
    ),
    'alerts' => _screen('Alerts', _alerts()),
    'company' when admin => CompanyDetailsScreen(controller: c),
    'account' when admin => AdminAccountScreen(controller: c),
    'template' when admin => ReceiptTemplateScreen(controller: c),
    'reports' when admin => InventoryReportsScreen(controller: c),
    'receiving' when admin => _screen('Staff receiving', _policy('receiving')),
    'customers' when admin => _screen('Customer details', _policy('customers')),
    'rules' => _screen(
      'Company rules',
      ListView(padding: const EdgeInsets.all(24), children: _rules()),
    ),
    'help' => _screen(
      'Help & support',
      ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _info(
            'Printing',
            'Search for a printer, connect it, then print a test receipt. Your saved printer is reused when available.',
          ),
          _info(
            'Synchronization',
            'Completed sales are saved on this device first. Open Printers & sync to retry an upload or check its status.',
          ),
          _info(
            'Corrections',
            'Open a sale from Sales to request a correction. Track requests in Corrections; administrator approval may be required.',
          ),
          _info(
            'Appearance',
            'Light, dark and accent colours apply across Saleo immediately. Personal preferences are saved for your account and sync when online.',
          ),
          _info(
            'Company permissions',
            'Contact your company administrator to change access or company rules.',
          ),
        ],
      ),
    ),
    _ => _general(),
  };

  Widget _info(String title, String message) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SettingsRow(
      icon: Icons.info_outline,
      title: title,
      subtitle: message,
    ),
  );

  Future<void> _save(InventoryPreferences value) async {
    try {
      await c.saveInventoryPreferences(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save this setting. Please retry.'),
          ),
        );
      }
    }
  }

  Widget _policy(String kind) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: SwitchListTile(
          title: Text(
            kind == 'receiving'
                ? 'Allow staff to receive stock'
                : 'Collect customer details',
          ),
          subtitle: Text(
            kind == 'receiving'
                ? 'Staff deliveries require administrator approval before stock changes.'
                : 'Offer optional name, phone and company details at checkout. Credit purchases still require customer details.',
          ),
          value: kind == 'receiving'
              ? c.inventoryPreferences.staffCanReceiveStock
              : c.inventoryPreferences.collectCustomerDetails,
          onChanged: (value) => _save(
            kind == 'receiving'
                ? c.inventoryPreferences.copyWith(staffCanReceiveStock: value)
                : c.inventoryPreferences.copyWith(
                    collectCustomerDetails: value,
                  ),
          ),
        ),
      ),
    ],
  );

  Widget _alerts() {
    final p = c.inventoryPreferences;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Personal alerts',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Every sale'),
                subtitle: const Text('Show an alert when a sale is recorded.'),
                value: p.notifyEverySale,
                onChanged: (v) =>
                    _save(c.inventoryPreferences.copyWith(notifyEverySale: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Low stock'),
                subtitle: const Text(
                  'Use the stock threshold set for each product.',
                ),
                value: p.notifyLowStock,
                onChanged: (v) =>
                    _save(c.inventoryPreferences.copyWith(notifyLowStock: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Products nearing expiry'),
                subtitle: Text(
                  'Alert ${p.expiryReminderDays} days before expiry.',
                ),
                value: p.notifyExpiry,
                onChanged: (v) =>
                    _save(c.inventoryPreferences.copyWith(notifyExpiry: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Debts due'),
                value: p.notifyDebtDue,
                onChanged: (v) =>
                    _save(c.inventoryPreferences.copyWith(notifyDebtDue: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Live updates need an internet connection. Saleo must be open to receive live sale updates on this device.',
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) => OutlinedButton.icon(
            icon: const Icon(Icons.notifications_outlined, size: 18),
            label: const Text('View notifications'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotificationsScreen(controller: c),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _rules() => [
    const SettingsRow(
      icon: Icons.lock_outline,
      title: 'Credit purchases',
      subtitle: 'Company and receiver name/phone required',
      trailing: Text('Required'),
    ),
    const SizedBox(height: 10),
    SettingsRow(
      icon: Icons.lock_outline,
      title: 'Stock received',
      subtitle: c.inventoryPreferences.staffCanReceiveStock
          ? 'Staff submissions require administrator approval.'
          : 'Stock receiving is limited to administrators.',
      trailing: Text(
        c.inventoryPreferences.staffCanReceiveStock
            ? 'Approval required'
            : 'Admin only',
      ),
    ),
    const SizedBox(height: 10),
    SettingsRow(
      icon: Icons.lock_outline,
      title: 'Corrections',
      subtitle: c.directCorrections
          ? 'Staff can correct their own sales within 24 hours. Other corrections require approval.'
          : 'Request administrator approval.',
    ),
    const SizedBox(height: 10),
    const Text(
      'Managed by your company administrator.',
      style: TextStyle(fontSize: 12),
    ),
  ];

  Widget _general() => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text(
          'Your workspace',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        const Text('Printing, appearance and account tools.'),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: CircleAvatar(
              child: Text(
                (c.currentUser?.displayName ?? 'S').characters.firstOrNull ??
                    'S',
              ),
            ),
            title: Text(c.currentUser?.displayName ?? 'Saleo'),
            subtitle: Text(
              '${c.currentCompany?.name ?? 'Company'} · ${admin ? 'Administrator' : 'Receptionist'}',
            ),
            trailing: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        SettingsRow(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Light, dark and accent colour',
          onTap: () => _select('appearance'),
        ),
        const SizedBox(height: 8),
        SettingsRow(
          icon: Icons.print_outlined,
          title: 'Printer & synchronization',
          subtitle: 'Connect a printer, test printing and sync',
          onTap: () => _select('printers'),
        ),
        const SizedBox(height: 8),
        SettingsRow(
          icon: Icons.receipt_long_outlined,
          title: 'Pending receipts',
          subtitle: c.pendingPrintReceipts.isEmpty
              ? 'No receipts waiting to print'
              : '${c.pendingPrintReceipts.length} receipts waiting to print',
          onTap: () => _select('pending'),
        ),
        const SizedBox(height: 22),
        Text('Company rules', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ..._rules(),
      ],
    ),
  );

  Widget _sidebar() {
    final scheme = Theme.of(context).colorScheme;
    final entries = sections
        .where((s) => s.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 22, 20, 12),
          child: SaleoBrand(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            'Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Find a setting',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final section in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    key: ValueKey('settings-nav-${section.id}'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    selected: _selected == section.id,
                    selectedTileColor: scheme.surfaceContainer,
                    selectedColor: scheme.onSurface,
                    leading: Icon(
                      section.icon,
                      size: 19,
                      color: _selected == section.id
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      section.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _selected == section.id
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    trailing:
                        section.id == 'pending' &&
                            c.pendingPrintReceipts.isNotEmpty
                        ? Text(
                            '${c.pendingPrintReceipts.length}',
                            style: TextStyle(color: scheme.primary),
                          )
                        : null,
                    onTap: () => _select(section.id),
                  ),
                ),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No matching settings.'),
                ),
            ],
          ),
        ),
        const Divider(indent: 20, endIndent: 20),
        ListTile(
          leading: const Icon(Icons.arrow_back, size: 18),
          title: const Text('Back to Saleo'),
          onTap: widget.onClose,
        ),
        ListTile(
          leading: const Icon(Icons.logout, size: 18),
          title: Text(c.signingOut ? 'Signing out…' : 'Sign out'),
          onTap: c.signingOut ? null : () => confirmSignOut(context, c),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 16, 18),
          child: Text(
            '${c.currentUser?.displayName ?? ''} · ${admin ? 'Administrator' : 'Receptionist'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      // Surface treatment is shared by ALL sections; mode/accent still come from the app theme.
      final detailTheme = theme.copyWith(
        scaffoldBackgroundColor: scheme.surface,
        cardTheme: theme.cardTheme.copyWith(
          color: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320, maxHeight: 900),
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, size) => Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (size.maxWidth >= 760) ...[
                              SizedBox(width: 240, child: _sidebar()),
                              const VerticalDivider(width: 1),
                            ],
                            Expanded(
                              child: Column(
                                children: [
                                  if (size.maxWidth < 760)
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Back to Saleo',
                                            onPressed: widget.onClose,
                                            icon: const Icon(Icons.arrow_back),
                                          ),
                                          Expanded(
                                            child:
                                                DropdownButtonFormField<String>(
                                                  initialValue: _selected,
                                                  isExpanded: true,
                                                  items: [
                                                    for (final s in sections)
                                                      DropdownMenuItem(
                                                        value: s.id,
                                                        child: Text(s.label),
                                                      ),
                                                  ],
                                                  onChanged: (v) {
                                                    if (v != null) _select(v);
                                                  },
                                                ),
                                          ),
                                          IconButton(
                                            tooltip: 'Sign out',
                                            onPressed: () =>
                                                confirmSignOut(context, c),
                                            icon: const Icon(Icons.logout),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      tooltip: 'Close settings',
                                      onPressed: widget.onClose,
                                      icon: const Icon(Icons.close, size: 19),
                                    ),
                                  ),
                                  Expanded(
                                    child: Theme(
                                      data: detailTheme,
                                      child: Navigator(
                                        key: ValueKey(
                                          'settings-content-$_selected',
                                        ),
                                        onGenerateRoute: (_) =>
                                            MaterialPageRoute<void>(
                                              builder: (_) => AnimatedBuilder(
                                                animation: c,
                                                builder: (_, _) => _content(),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
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
                                '${c.summary.pendingSync} sales awaiting upload · ${c.syncState.name}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
