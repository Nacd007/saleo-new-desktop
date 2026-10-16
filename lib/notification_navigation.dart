import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'common_widgets.dart';
import 'inventory_page.dart';
import 'models.dart';
import 'notifications_page.dart';

/// Notification IDs resolve only inside the currently authenticated company.
class NotificationNavigation extends StatefulWidget {
  const NotificationNavigation({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
  });
  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<NotificationNavigation> createState() => _NotificationNavigationState();
}

class _NotificationNavigationState extends State<NotificationNavigation> {
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
    _check();
  }

  void _check() {
    final controller = widget.controller;
    if (_scheduled ||
        controller.initializing ||
        controller.currentUser == null ||
        controller.pendingNotificationTap == null) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || controller.currentUser == null) return;
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return;
      final id = controller.pendingNotificationTap;
      controller.consumeNotificationTap();
      final matches = controller.notifications.where((item) => item.id == id);
      if (matches.isNotEmpty) {
        final item = matches.first;
        controller.markNotificationRead(item);
        final sales = controller.sales.where((sale) => sale.id == item.saleId);
        if (item.type == 'sale' && sales.isNotEmpty) {
          showReceipt(navigator.context, sales.first, controller: controller);
          return;
        }
        if (item.productId != null &&
            controller.currentUser?.role == UserRole.admin) {
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Inventory')),
                body: InventoryPage(
                  controller: controller,
                  initialProductId: item.productId,
                ),
              ),
            ),
          );
          return;
        }
      }
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsScreen(controller: controller),
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
