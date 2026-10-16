import 'package:flutter/material.dart';

import 'admin_settings.dart';
import 'app_controller.dart';
import 'desktop_design.dart';
import 'models.dart';
import 'notifications_page.dart';
import 'printer_settings.dart';
import 'session_widgets.dart';
import 'workflow_pages.dart';

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  String _search = '';
  AppController get c => widget.controller;
  bool get admin => c.currentUser?.role == UserRole.admin;
  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  void _body(String title, Widget body) => _open(
    Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final entries =
        <({IconData icon, String title, String subtitle, VoidCallback action})>[
          if (admin)
            (
              icon: Icons.business_outlined,
              title: 'Company details',
              subtitle: 'Company identity, logo and contact details',
              action: () => _open(CompanyDetailsScreen(controller: c)),
            ),
          if (admin)
            (
              icon: Icons.person_outline,
              title: 'Admin profile',
              subtitle: 'Sign-in username and administrator details',
              action: () => _open(AdminAccountScreen(controller: c)),
            ),
          (
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Soft grey theme · Light or Dark',
            action: () => _open(DesktopThemesPage(controller: c)),
          ),
          if (admin)
            (
              icon: Icons.notifications_outlined,
              title: 'Alerts & notifications',
              subtitle: 'Sales, low stock, expiry and notification preferences',
              action: () => _open(NotificationSettingsScreen(controller: c)),
            ),
          if (admin)
            (
              icon: Icons.fact_check_outlined,
              title: 'Sales & stock approvals',
              subtitle: 'Correction permissions and approval requests',
              action: () =>
                  _body('Sales & stock approvals', ApprovalPage(controller: c)),
            ),
          if (admin)
            (
              icon: Icons.receipt_long_outlined,
              title: 'Receipt template',
              subtitle: 'Company details, receiver details and footer',
              action: () => _open(ReceiptTemplateScreen(controller: c)),
            ),
          (
            icon: Icons.print_outlined,
            title: 'Printer & synchronization',
            subtitle:
                'Connect a receipt printer, test printing and synchronize',
            action: () => _open(PrinterSettingsScreen(controller: c)),
          ),
          (
            icon: Icons.pending_actions_outlined,
            title: 'Pending receipts',
            subtitle: c.pendingPrintReceipts.isEmpty
                ? 'No receipts'
                : '${c.pendingPrintReceipts.length} receipts waiting to print',
            action: () =>
                _body('Pending receipts', PendingPrintPage(controller: c)),
          ),
          if (admin)
            (
              icon: Icons.analytics_outlined,
              title: 'Inventory reports',
              subtitle: 'Product performance and stock movement',
              action: () => _open(InventoryReportsScreen(controller: c)),
            ),
          if (admin)
            (
              icon: Icons.manage_accounts_outlined,
              title: 'Staff receiving permissions',
              subtitle: 'Allow staff to submit stock for approval',
              action: () => _body(
                'Staff receiving permissions',
                AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => ListView(
                    children: [
                      SwitchListTile(
                        title: const Text('Allow staff to receive stock'),
                        subtitle: const Text(
                          'Submissions still require administrator approval.',
                        ),
                        value: c.inventoryPreferences.staffCanReceiveStock,
                        onChanged: (value) => c.saveInventoryPreferences(
                          c.inventoryPreferences.copyWith(
                            staffCanReceiveStock: value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (admin)
            (
              icon: Icons.contacts_outlined,
              title: 'Customer details at checkout',
              subtitle: 'Required information when recording sales',
              action: () => _body(
                'Customer details at checkout',
                AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => ListView(
                    children: [
                      SwitchListTile(
                        title: const Text('Collect customer details'),
                        value: c.inventoryPreferences.collectCustomerDetails,
                        onChanged: (value) => c.saveInventoryPreferences(
                          c.inventoryPreferences.copyWith(
                            collectCustomerDetails: value,
                          ),
                        ),
                      ),
                      const ListTile(
                        title: Text('Credit purchases'),
                        subtitle: Text(
                          'Company and receiver name and phone are required.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ];
    final filtered = entries.where(
      (e) => '${e.title} ${e.subtitle}'.toLowerCase().contains(
        _search.toLowerCase(),
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 26, 32, 32),
          children: [
            Text(
              admin ? 'Company settings' : 'Your workspace',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              admin
                  ? 'Company controls and personal preferences, organized in one place.'
                  : 'Printing, appearance and account tools. Company policies are managed by your admin.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      child: Text(
                        (c.currentUser?.displayName ?? 'S').characters.first,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.currentUser?.displayName ?? '',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${c.currentCompany?.name ?? 'Saleo'} • ${admin ? 'Administrator' : 'Receptionist'}',
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      admin
                          ? Icons.admin_panel_settings_outlined
                          : Icons.badge_outlined,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: (value) => setState(() => _search = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Find a setting',
              ),
            ),
            const SizedBox(height: 18),
            for (final e in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: SettingsRow(
                  icon: e.icon,
                  title: e.title,
                  subtitle: e.subtitle,
                  onTap: e.action,
                ),
              ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No matching settings. Try another search.'),
              ),
            if (!admin && _search.isEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Company rules',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const SettingsRow(
                icon: Icons.lock_outline,
                title: 'Credit purchases',
                subtitle: 'Company and receiver name/phone required',
                trailing: Text('Required'),
              ),
              const SizedBox(height: 7),
              const SettingsRow(
                icon: Icons.lock_outline,
                title: 'Stock received',
                subtitle: 'Submitted stock requires administrator approval',
                trailing: Text('Approval required'),
              ),
              const SizedBox(height: 7),
              SettingsRow(
                icon: Icons.lock_outline,
                title: 'Corrections',
                subtitle: c.directCorrections
                    ? 'Your own sales within 24 hours; other corrections require approval'
                    : 'Request administrator approval',
                trailing: const Icon(Icons.lock_outline, size: 18),
              ),
            ],
            if (admin && _search.isEmpty) ...[
              const SizedBox(height: 14),
              const SettingsRow(
                icon: Icons.info_outline,
                title: 'Reset company',
                subtitle: 'Not available in this build. Server-side backup and six-month retention must be implemented before enabling this action.',
                trailing: Icon(Icons.lock_outline, size: 18),
              ),
            ],
            const SizedBox(height: 26),
            const Divider(),
            SettingsRow(
              icon: Icons.logout,
              title: c.signingOut ? 'Signing out…' : 'Sign out',
              subtitle: 'Checks unsynced records and asks for confirmation',
              onTap: c.signingOut ? null : () => confirmSignOut(context, c),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing ??
                (onTap == null
                    ? const SizedBox.shrink()
                    : const Icon(Icons.chevron_right, size: 20)),
          ],
        ),
      ),
    ),
  );
}

class DesktopThemesPage extends StatefulWidget {
  const DesktopThemesPage({super.key, required this.controller, this.onDone});
  final AppController controller;
  final VoidCallback? onDone;
  @override
  State<DesktopThemesPage> createState() => _DesktopThemesPageState();
}

class _DesktopThemesPageState extends State<DesktopThemesPage> {
  bool _saving = false;
  String? _error;
  InventoryPreferences get preferences =>
      widget.controller.inventoryPreferences;

  Future<void> _apply(InventoryPreferences next) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The controller publishes the same preference to the whole app immediately,
      // and serializes its local snapshot and per-user synchronization outbox.
      await widget.controller.saveInventoryPreferences(
        next.copyWith(textScale: 1),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save appearance. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _customColour() async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => DesktopColourPicker(initial: desktopAccent(preferences)),
    );
    if (result != null && mounted) {
      await _apply(
        preferences.copyWith(
          accent: AppAccentPreference.custom,
          customAccentArgb: result.toARGB32(),
        ),
      );
    }
  }

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _row(String title, Widget control) => LayoutBuilder(
    builder: (_, size) => size.maxWidth < 430
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title), const SizedBox(height: 10), control],
          )
        : Row(
            children: [
              Expanded(child: Text(title)),
              const SizedBox(width: 12),
              control,
            ],
          ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Appearance')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Personalize your workspace. Changes apply across Saleo immediately.',
            ),
            const SizedBox(height: 20),
            _panel('Mode', [
              _row(
                'Applies throughout the app',
                SegmentedButton<AppThemePreference>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: AppThemePreference.light,
                      icon: Icon(Icons.light_mode_outlined, size: 17),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: AppThemePreference.dark,
                      icon: Icon(Icons.dark_mode_outlined, size: 17),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {
                    preferences.theme == AppThemePreference.dark
                        ? AppThemePreference.dark
                        : AppThemePreference.light,
                  },
                  onSelectionChanged: _saving
                      ? null
                      : (v) => _apply(preferences.copyWith(theme: v.first)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _panel('Accent colour', [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in const <String, int>{
                    'Blue': 0xFF0869FA,
                    'Red': 0xFFC63545,
                    'Green': 0xFF187A51,
                    'Teal': 0xFF087F8C,
                    'Purple': 0xFF6750A4,
                    'Orange': 0xFFB65B00,
                    'Pink': 0xFFAB3470,
                    'Grey': 0xFF555555,
                  }.entries)
                    Tooltip(
                      message: entry.key,
                      child: Semantics(
                        label: '${entry.key} accent',
                        button: true,
                        selected:
                            desktopAccent(preferences).toARGB32() ==
                            entry.value,
                        child: InkWell(
                          key: ValueKey('accent-${entry.key}'),
                          onTap: _saving
                              ? null
                              : () => _apply(
                                  preferences.copyWith(
                                    accent: AppAccentPreference.custom,
                                    customAccentArgb: entry.value,
                                  ),
                                ),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(entry.value),
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child:
                                desktopAccent(preferences).toARGB32() ==
                                    entry.value
                                ? const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _customColour,
                    icon: const Icon(Icons.colorize_outlined, size: 16),
                    label: const Text('Custom colour'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Changes icons, prices and selected controls. Shades adapt for readability.',
                style: TextStyle(fontSize: 12),
              ),
            ]),
            const SizedBox(height: 12),
            _panel('Display', [
              _row(
                'Product images',
                Switch(
                  value: preferences.showProductImages,
                  onChanged: _saving
                      ? null
                      : (v) =>
                            _apply(preferences.copyWith(showProductImages: v)),
                ),
              ),
              const Divider(height: 24),
              _row('Catalogue layout', const Text('3 products per row')),
            ]),
            const SizedBox(height: 18),
            Text(
              _saving ? 'Saving appearance…' : 'Preferences are saved for your account and sync when online.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
              TextButton(
                onPressed: _saving ? null : () => _apply(preferences),
                child: const Text('Retry saving'),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (widget.onDone != null) {
                          widget.onDone!();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class DesktopColourPicker extends StatefulWidget {
  const DesktopColourPicker({super.key, required this.initial});
  final Color initial;
  @override
  State<DesktopColourPicker> createState() => _DesktopColourPickerState();
}

class _DesktopColourPickerState extends State<DesktopColourPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: widget.initial
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase(),
  );
  String? _error;
  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _change(HSVColor value) => setState(() {
    _hsv = value;
    _error = null;
    _hex.text = _hsv
        .toColor()
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase();
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom accent'),
    content: SizedBox(
      width: 330,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: _hsv.toColor(),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hex,
            maxLength: 7,
            decoration: InputDecoration(
              labelText: 'HEX colour',
              prefixText: '#',
              errorText: _error,
            ),
          ),
          const Text('Hue'),
          Slider(
            value: _hsv.hue,
            min: 0,
            max: 360,
            onChanged: (v) => _change(_hsv.withHue(v)),
          ),
          const Text('Saturation'),
          Slider(
            value: _hsv.saturation,
            onChanged: (v) => _change(_hsv.withSaturation(v)),
          ),
          const Text('Brightness'),
          Slider(
            value: _hsv.value,
            onChanged: (v) => _change(_hsv.withValue(v)),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final input = _hex.text.trim().replaceFirst('#', '');
          if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(input)) {
            setState(() => _error = 'Enter six HEX digits.');
            return;
          }
          Navigator.pop(
            context,
            Color(0xFF000000 | int.parse(input, radix: 16)),
          );
        },
        child: const Text('Use colour'),
      ),
    ],
  );
}

class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.mode});
  final DesktopMode mode;
  @override
  Widget build(BuildContext context) {
    final theme = desktopTheme(mode);
    return Container(
      height: 110,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 42,
            color: mode.sidebar,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Icon(Icons.receipt_long, size: 18, color: mode.sidebarText),
                const SizedBox(height: 12),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Container(
                      width: 25,
                      height: 4,
                      color: i == 0
                          ? mode.accent
                          : mode == DesktopMode.dark
                          ? Colors.white24
                          : Colors.black26,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Container(
                              height: 24,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 8; i++)
                            Expanded(
                              child: Container(
                                height: 10 + (i * 9 % 40).toDouble(),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                color: mode.accent,
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
        ],
      ),
    );
  }
}
