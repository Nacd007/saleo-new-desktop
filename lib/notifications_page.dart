import 'dart:async';

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'common_widgets.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'workflow_pages.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => IconButton(
      tooltip: controller.pendingApprovalCount > 0
          ? 'Pending approvals · ${controller.pendingApprovalCount}'
          : 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => controller.pendingApprovalCount > 0
              ? Scaffold(
                  appBar: AppBar(
                    title: Text(
                      'Pending approvals · ${controller.pendingApprovalCount}',
                    ),
                  ),
                  body: ApprovalPage(controller: controller),
                )
              : NotificationsScreen(controller: controller),
        ),
      ),
      icon:
          controller.pendingApprovalCount == 0 &&
              controller.unreadNotificationCount == 0
          ? const Icon(Icons.notifications_none)
          : Badge(
              backgroundColor: Colors.red.shade700,
              label: Text(
                '${controller.pendingApprovalCount > 0 ? controller.pendingApprovalCount : controller.unreadNotificationCount}',
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
    ),
  );
}

enum _NotificationFilter { all, unread, sales, stock }

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  _NotificationFilter _filter = _NotificationFilter.all;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [
        if (controller.unreadNotificationCount > 0)
          TextButton(
            onPressed: controller.markAllNotificationsRead,
            child: const Text('Mark all read'),
          ),
        if (controller.currentUser?.role == UserRole.admin &&
            controller.notifications.isNotEmpty)
          IconButton(
            tooltip: 'Clear notification history',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
      ],
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final items = controller.notifications.where((item) {
          return switch (_filter) {
            _NotificationFilter.all => true,
            _NotificationFilter.unread => !item.isRead,
            _NotificationFilter.sales => item.type == 'sale',
            _NotificationFilter.stock => item.type != 'sale',
          };
        }).toList();
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: items.isEmpty ? 2 : items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_NotificationFilter>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _NotificationFilter.all,
                        label: Text('All'),
                      ),
                      ButtonSegment(
                        value: _NotificationFilter.unread,
                        label: Text('Unread'),
                      ),
                      ButtonSegment(
                        value: _NotificationFilter.sales,
                        label: Text('Sales'),
                      ),
                      ButtonSegment(
                        value: _NotificationFilter.stock,
                        label: Text('Stock'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (value) =>
                        setState(() => _filter = value.first),
                  ),
                ),
              );
            }
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 72),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 52),
                    SizedBox(height: 12),
                    Text(
                      'Nothing to show',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'New sale and low-stock alerts will appear here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            final item = items[index - 1];
            final color = _notificationColor(item.type);
            final group = _notificationGroup(item.createdAt);
            final previousGroup = index <= 1
                ? null
                : _notificationGroup(items[index - 2].createdAt);
            final card = Dismissible(
              key: ValueKey('notification-${item.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.only(right: 22),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) => unawaited(_delete(item)),
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: item.isRead ? null : color.withValues(alpha: .07),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: .12),
                    child: Icon(_notificationIcon(item.type), color: color),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.isRead
                          ? FontWeight.w700
                          : FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    '${item.message}\n${_notificationDate(item.createdAt)}'
                    '${item.isResolved ? '\nResolved ${_notificationDate(item.resolvedAt!)}' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Delete notification',
                    onPressed: () => _delete(item),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () => _openNotification(item),
                ),
              ),
            );
            if (group == previousGroup) return card;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    group,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                card,
              ],
            );
          },
        );
      },
    ),
  );

  Future<void> _delete(AppNotificationRecord item) async {
    await controller.deleteNotification(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Notification deleted.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.restoreNotification(item),
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear all notifications?'),
            content: const Text(
              'This removes the notification history from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.clearNotifications();
  }

  Future<void> _openNotification(AppNotificationRecord item) async {
    await controller.markNotificationRead(item);
    if (!mounted) return;
    final product = item.productId == null
        ? null
        : controller.products
              .where((value) => value.id == item.productId)
              .firstOrNull;
    final sale = item.saleId == null
        ? null
        : controller.sales
              .where((value) => value.id == item.saleId)
              .firstOrNull;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          _notificationIcon(item.type),
          color: _notificationColor(item.type),
        ),
        title: Text(item.title),
        content: Text(
          '${item.message}\n\n${_notificationDate(item.createdAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (product != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Inventory')),
                      body: InventoryPage(
                        controller: controller,
                        initialProductId: product.id,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('View inventory'),
            ),
          if (sale != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(dialogContext);
                showReceipt(context, sale, controller: controller);
              },
              child: const Text('View receipt'),
            ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alerts and inventory reports')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.inventoryPreferences;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Live sale alerts work while Saleo is open and online, after the live-sales backend is deployed. Enable every-sale alerts and Android banners below. Alerts while the app is closed require push notifications.',
              ),
            ),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.point_of_sale_outlined),
                    title: const Text('Notify me about every sale'),
                    subtitle: const Text(
                      'Add an alert whenever a receptionist completes a sale.',
                    ),
                    value: settings.notifyEverySale,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(notifyEverySale: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.warning_amber_rounded),
                    title: const Text('Notify me when stock is low'),
                    subtitle: const Text(
                      'Alert once when a product crosses its chosen stock level.',
                    ),
                    value: settings.notifyLowStock,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(notifyLowStock: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.event_busy_outlined),
                    title: const Text('Notify me before products expire'),
                    subtitle: Text(
                      'Alert when a stock batch is within ${settings.expiryReminderDays} days of expiry.',
                    ),
                    value: settings.notifyExpiry,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(notifyExpiry: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                    title: const Text('Notify me about debts due'),
                    subtitle: const Text(
                      'Alert when customer balances are due or overdue.',
                    ),
                    value: settings.notifyDebtDue,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(notifyDebtDue: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.phone_android_outlined),
                    title: const Text('Show alerts outside Saleo'),
                    subtitle: const Text(
                      'Allow Android banners, lock-screen alerts and notification-shade updates.',
                    ),
                    value: settings.showExternalNotifications,
                    onChanged: (value) async {
                      final enabled = await controller.setExternalNotifications(
                        value,
                      );
                      if (!enabled && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Allow notification permission in Android settings to use external alerts.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.contact_phone_outlined),
                    title: const Text('Collect customer details during sales'),
                    subtitle: const Text(
                      'Shows optional name and phone fields at checkout. A sale is never blocked if they are blank.',
                    ),
                    value: settings.collectCustomerDetails,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(collectCustomerDetails: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.inventory_outlined),
                    title: const Text('Allow staff to receive stock'),
                    subtitle: const Text(
                      'Staff can prepare and confirm deliveries. Administrator controls remain unchanged.',
                    ),
                    value: settings.staffCanReceiveStock,
                    onChanged: (value) => controller.saveInventoryPreferences(
                      settings.copyWith(staffCanReceiveStock: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stock discrepancies are always recorded when a receptionist sells beyond the recorded balance.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Inventory reporting',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Default period',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<InventoryPeriod>(
                      segments: InventoryPeriod.values
                          .map(
                            (period) => ButtonSegment(
                              value: period,
                              label: Text(period.label),
                            ),
                          )
                          .toList(),
                      selected: {settings.defaultPeriod},
                      onSelectionChanged: (value) =>
                          controller.saveInventoryPreferences(
                            settings.copyWith(defaultPeriod: value.first),
                          ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<int>(
                      initialValue: settings.weekStartsOn,
                      decoration: const InputDecoration(
                        labelText: 'Week starts on',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DateTime.monday,
                          child: Text('Monday'),
                        ),
                        DropdownMenuItem(
                          value: DateTime.sunday,
                          child: Text('Sunday'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          controller.saveInventoryPreferences(
                            settings.copyWith(weekStartsOn: value),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationsScreen(controller: controller),
                ),
              ),
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Open notification history'),
            ),
          ],
        );
      },
    ),
  );
}

IconData _notificationIcon(String type) => switch (type) {
  'sale' => Icons.point_of_sale_outlined,
  'low_stock' => Icons.warning_amber_rounded,
  'stock_discrepancy' => Icons.error_outline,
  _ => Icons.notifications_none,
};

Color _notificationColor(String type) => switch (type) {
  'sale' => Colors.green,
  'low_stock' => Colors.orange,
  'stock_discrepancy' => Colors.red,
  _ => Colors.indigo,
};

String _notificationDate(DateTime value) {
  final date = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _notificationGroup(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = value.toLocal();
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'TODAY';
  if (day.isAfter(today.subtract(const Duration(days: 7)))) {
    return 'EARLIER THIS WEEK';
  }
  return 'OLDER';
}
