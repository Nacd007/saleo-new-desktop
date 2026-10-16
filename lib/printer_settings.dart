import 'package:flutter/material.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import 'app_controller.dart';
import 'common_widgets.dart';
import 'printer_service.dart';

class PrinterSettingsScreen extends StatelessWidget {
  const PrinterSettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Printer & synchronization',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    body: PrinterSettingsPage(controller: controller),
  );
}

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  final _networkAddress = TextEditingController();
  final _networkPort = TextEditingController(text: '9100');

  @override
  void initState() {
    super.initState();
    final selected = widget.controller.printer.selectedDevice;
    if (selected is NetworkPrinterDevice) {
      _networkAddress.text = selected.host;
      _networkPort.text = '${selected.port}';
    }
  }

  @override
  void dispose() {
    _networkAddress.dispose();
    _networkPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final printer = widget.controller.printer;
    return AnimatedBuilder(
      animation: Listenable.merge([printer, widget.controller]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _PrinterStatusCard(printer: printer),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Connect a receipt printer',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Choose the connection available on your printer.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (printer.bluetoothOff) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: .35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bluetooth_disabled_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Bluetooth is off. Turn it on to find receipt printers.',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          TextButton(
                            onPressed: printer.openBluetoothSettings,
                            child: const Text('Settings'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _ConnectionTile(
                    icon: Icons.bluetooth,
                    title: 'Bluetooth',
                    subtitle: 'Classic and Bluetooth Low Energy printers',
                    actionLabel: printer.scanning ? 'Searching…' : 'Search',
                    onPressed: printer.scanning ? null : printer.scanBluetooth,
                  ),
                  const Divider(),
                  _ConnectionTile(
                    icon: Icons.usb,
                    title: 'USB cable',
                    subtitle: 'Receipt printers connected to this computer',
                    actionLabel: printer.scanning ? 'Searching…' : 'Search',
                    onPressed: printer.scanning ? null : printer.scanUsb,
                  ),
                  if (printer.devices.isNotEmpty) ...[
                    const Divider(),
                    const Text(
                      'Printers found',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    ...printer.devices.map((device) {
                      final connecting = printer.isConnectingTo(device);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_deviceIcon(device.connectionType)),
                        title: Text(device.name),
                        subtitle: Text(_deviceDescription(device)),
                        trailing: connecting
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Connecting…',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : FilledButton.tonal(
                                onPressed:
                                    printer.state ==
                                        SaleoPrinterState.connecting
                                    ? null
                                    : () => _connect(device),
                                child: const Text('Connect'),
                              ),
                      );
                    }),
                  ],
                  const Divider(height: 28),
                  Row(
                    children: [
                      const Icon(Icons.wifi),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Network / LAN',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'For printers on the same Wi-Fi or local network',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _networkAddress,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Printer IP address',
                            hintText: '192.168.1.50',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _networkPort,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: printer.state == SaleoPrinterState.connecting
                        ? null
                        : _connectNetwork,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect network printer'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Receipt setup',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 58, label: Text('58 mm')),
                      ButtonSegment(value: 80, label: Text('80 mm')),
                    ],
                    selected: {printer.paperWidthMm},
                    onSelectionChanged: (value) =>
                        printer.setPaperWidth(value.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: printer.isReady ? _testPrint : null,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print test receipt'),
                  ),
                  if (printer.selectedDevice != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: printer.isReady
                          ? printer.disconnect
                          : printer.reconnect,
                      icon: Icon(
                        printer.isReady ? Icons.link_off : Icons.refresh,
                      ),
                      label: Text(
                        printer.isReady
                            ? 'Disconnect'
                            : 'Reconnect saved printer',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SyncSettingsCard(controller: widget.controller),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.shield_outlined),
              title: const Text(
                'Sales are saved first',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'A printer or internet problem never removes a completed sale.',
              ),
              trailing: Text(
                '${widget.controller.summary.pendingSync} pending',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(PrinterDevice device) async {
    final ok = await widget.controller.printer.connect(device);
    if (mounted) _showResult(ok);
  }

  Future<void> _connectNetwork() async {
    final port = int.tryParse(_networkPort.text.trim()) ?? 9100;
    final ok = await widget.controller.printer.connectNetwork(
      _networkAddress.text,
      port: port,
    );
    if (mounted) _showResult(ok);
  }

  Future<void> _testPrint() async {
    final ok = await widget.controller.printer.printTest(
      companyName: widget.controller.currentCompany?.name ?? 'Saleo Shop',
    );
    if (mounted) _showResult(ok);
  }

  void _showResult(bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.controller.printer.message),
        backgroundColor: success
            ? const Color(0xFF067647)
            : Colors.red.shade700,
      ),
    );
  }
}

class _PrinterStatusCard extends StatelessWidget {
  const _PrinterStatusCard({required this.printer});

  final PrinterService printer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final (label, color, icon) = switch (printer.state) {
      SaleoPrinterState.ready => (
        'Ready',
        dark ? const Color(0xFF80D5AC) : const Color(0xFF067647),
        Icons.check_circle,
      ),
      SaleoPrinterState.disconnected => (
        'Disconnected',
        scheme.onSurfaceVariant,
        Icons.link_off,
      ),
      SaleoPrinterState.connecting => (
        'Connecting',
        Theme.of(context).colorScheme.primary,
        Icons.sync,
      ),
      SaleoPrinterState.receiptWaiting => (
        'Receipt waiting',
        dark ? const Color(0xFFFFCC80) : const Color(0xFF915000),
        Icons.schedule,
      ),
      SaleoPrinterState.printingFailed => (
        'Printing failed',
        scheme.error,
        Icons.error,
      ),
    };
    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        printer.selectedName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(printer.message),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      TextButton(onPressed: onPressed, child: Text(actionLabel)),
    ],
  );
}

class _SyncSettingsCard extends StatelessWidget {
  const _SyncSettingsCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SyncBadge(controller: controller),
          const SizedBox(height: 12),
          Text(
            controller.syncMessage ??
                'Sales synchronize automatically when internet is available.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: controller.syncState == AppSyncState.syncing
                ? null
                : controller.syncPending,
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
        ],
      ),
    ),
  );
}

IconData _deviceIcon(PrinterConnectionType type) => switch (type) {
  PrinterConnectionType.bluetooth ||
  PrinterConnectionType.ble => Icons.bluetooth,
  PrinterConnectionType.usb => Icons.usb,
  PrinterConnectionType.network => Icons.wifi,
};

String _deviceDescription(PrinterDevice device) => switch (device) {
  NetworkPrinterDevice value => '${value.host}:${value.port}',
  BluetoothPrinterDevice value => 'Bluetooth • ${value.address}',
  BlePrinterDevice value => 'Bluetooth LE • ${value.deviceId}',
  UsbPrinterDevice value => 'USB • ${value.identifier}',
  _ => device.connectionType.name,
};
