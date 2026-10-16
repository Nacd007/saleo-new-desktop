import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import 'models.dart';
import 'receipt_item_layout.dart';

enum SaleoPrinterState {
  disconnected,
  connecting,
  ready,
  receiptWaiting,
  printingFailed,
}

enum SaleoBluetoothState {
  unknown,
  checking,
  on,
  off,
  permissionRequired,
  unsupported,
}

class PrinterService extends ChangeNotifier {
  PrinterService({PrinterManager? manager})
    : _manager = manager ?? PrinterManager();

  static const _storage = FlutterSecureStorage();
  static const _typeKey = 'saleo.printer.type';
  static const _nameKey = 'saleo.printer.name';
  static const _addressKey = 'saleo.printer.address';
  static const _portKey = 'saleo.printer.port';
  static const _paperKey = 'saleo.printer.paper';

  final PrinterManager _manager;
  Future<CapabilityProfile>? _profile;
  StreamSubscription<PrinterConnectionState>? _stateSubscription;

  SaleoPrinterState state = SaleoPrinterState.disconnected;
  List<PrinterDevice> devices = const [];
  PrinterDevice? selectedDevice;
  String message = 'No receipt printer connected.';
  int paperWidthMm = 80;
  bool scanning = false;
  bool _checkingBluetooth = false;
  bool _autoReconnectRunning = false;
  bool _autoReconnectAllowed = true;
  bool _scanAfterBluetoothEnabled = false;
  DateTime? _lastResumeCheck;
  String? _connectingDeviceKey;
  SaleoBluetoothState bluetoothState = SaleoBluetoothState.unknown;
  int bluetoothPromptRevision = 0;
  static const _native = MethodChannel('saleo/native');
  static const _bluetooth = MethodChannel(
    'com.elriztechnology.unified_esc_pos_printer/methods',
  );

  Future<bool> _bluetoothReady({
    bool requestPermission = true,
    bool promptWhenOff = true,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      bluetoothState = SaleoBluetoothState.on;
      return true;
    }
    bluetoothState = SaleoBluetoothState.checking;
    notifyListeners();
    var status = await _native.invokeMethod<String>('bluetoothStatus');
    if (status == 'permission_required' && requestPermission) {
      message = 'Allow Nearby devices permission to find and connect printers.';
      notifyListeners();
      final granted = await _bluetooth.invokeMethod<bool>('requestPermissions');
      if (granted == true) {
        status = await _native.invokeMethod<String>('bluetoothStatus');
      }
    }
    if (status == 'ready') {
      bluetoothState = SaleoBluetoothState.on;
      notifyListeners();
      return true;
    }
    state = SaleoPrinterState.disconnected;
    devices = const [];
    bluetoothState = switch (status) {
      'off' => SaleoBluetoothState.off,
      'unsupported' => SaleoBluetoothState.unsupported,
      'permission_required' => SaleoBluetoothState.permissionRequired,
      _ => SaleoBluetoothState.unknown,
    };
    if (status == 'off' && promptWhenOff) bluetoothPromptRevision++;
    message = switch (status) {
      'off' =>
        'Bluetooth is off. Turn it on in phone settings, then scan again.',
      'unsupported' => 'This device does not support Bluetooth.',
      'permission_required' => 'Bluetooth permission is required. Allow Nearby devices (or Location on older Android) in Saleo app permissions.',
      _ => 'Could not check Bluetooth. Please try again.',
    };
    notifyListeners();
    return false;
  }

  bool get isReady => state == SaleoPrinterState.ready;
  String get selectedName => selectedDevice?.name ?? 'No printer selected';
  bool get bluetoothOff => bluetoothState == SaleoBluetoothState.off;

  bool isConnectingTo(PrinterDevice device) =>
      _connectingDeviceKey == _deviceKey(device);

  Future<void> initialize() async {
    _stateSubscription = _manager.stateStream.listen(_handleManagerState);
    paperWidthMm = int.tryParse(await _storage.read(key: _paperKey) ?? '') == 58
        ? 58
        : 80;
    final type = await _storage.read(key: _typeKey);
    final name = await _storage.read(key: _nameKey);
    final address = await _storage.read(key: _addressKey);
    final port = int.tryParse(await _storage.read(key: _portKey) ?? '');
    if (type != null && name != null && address != null) {
      selectedDevice = switch (type) {
        'network' => NetworkPrinterDevice(
          name: name,
          host: address,
          port: port ?? 9100,
        ),
        'bluetooth' => BluetoothPrinterDevice(name: name, address: address),
        'ble' => BlePrinterDevice(name: name, deviceId: address),
        'usb' => UsbPrinterDevice(
          name: name,
          identifier: address,
          usbPlatform: defaultTargetPlatform == TargetPlatform.windows
              ? UsbPlatform.desktop
              : UsbPlatform.android,
        ),
        _ => null,
      };
      if (selectedDevice != null) {
        message = type == 'bluetooth' || type == 'ble'
            ? 'Reconnecting to saved printer $name...'
            : '$name is saved. Tap Reconnect when the printer is available.';
      }
    }
    notifyListeners();
    if (selectedDevice is BluetoothPrinterDevice ||
        selectedDevice is BlePrinterDevice) {
      unawaited(autoReconnectSavedPrinter());
    }
  }

  Future<void> scanBluetooth() =>
      _scan({PrinterConnectionType.bluetooth, PrinterConnectionType.ble});

  Future<void> scanUsb() => _scan({PrinterConnectionType.usb});

  Future<void> _scan(Set<PrinterConnectionType> types) async {
    if (scanning || _checkingBluetooth) return;
    final usesBluetooth =
        types.contains(PrinterConnectionType.bluetooth) ||
        types.contains(PrinterConnectionType.ble);
    if (usesBluetooth) {
      _checkingBluetooth = true;
      try {
        if (!await _bluetoothReady()) {
          _scanAfterBluetoothEnabled = bluetoothOff;
          return;
        }
      } catch (_) {
        state = SaleoPrinterState.disconnected;
        message = 'Could not check Bluetooth permissions. Please try again.';
        notifyListeners();
        return;
      } finally {
        _checkingBluetooth = false;
      }
    }
    scanning = true;
    state = SaleoPrinterState.connecting;
    message = 'Searching for available receipt printers...';
    devices = const [];
    notifyListeners();
    try {
      devices = await _manager
          .scanPrinters(timeout: const Duration(seconds: 6), types: types)
          .timeout(const Duration(seconds: 15));
      if (usesBluetooth && !await _bluetoothReady(requestPermission: false)) {
        return;
      }
      state = _manager.isConnected
          ? SaleoPrinterState.ready
          : SaleoPrinterState.disconnected;
      message = devices.isEmpty
          ? 'No printers found. Make sure the printer is on and paired.'
          : '${devices.length} printer${devices.length == 1 ? '' : 's'} found.';
      _scanAfterBluetoothEnabled = false;
    } catch (error) {
      state = SaleoPrinterState.printingFailed;
      message = error is TimeoutException
          ? 'Printer search timed out. Check Bluetooth and try again.'
          : _friendlyError(error);
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<bool> connect(PrinterDevice device, {bool automatic = false}) async {
    if (scanning || _checkingBluetooth) return false;
    if (!automatic) _autoReconnectAllowed = true;
    if (device is BluetoothPrinterDevice || device is BlePrinterDevice) {
      try {
        if (!await _bluetoothReady()) return false;
      } catch (_) {
        state = SaleoPrinterState.disconnected;
        message = 'Could not check Bluetooth. Please try again.';
        notifyListeners();
        return false;
      }
    }
    selectedDevice = device;
    _connectingDeviceKey = _deviceKey(device);
    state = SaleoPrinterState.connecting;
    message = 'Connecting to ${device.name}...';
    notifyListeners();
    try {
      await _manager.connect(device).timeout(const Duration(seconds: 12));
      if (!_manager.isConnected) {
        throw StateError('The printer did not confirm a connection.');
      }
      await _saveDevice(device);
      state = SaleoPrinterState.ready;
      devices = const [];
      message = '${device.name} is ready.';
      notifyListeners();
      return true;
    } catch (error) {
      try {
        await _manager.disconnect().timeout(const Duration(seconds: 2));
      } catch (_) {
        // The failed connection may already be closed by the platform.
      }
      state = SaleoPrinterState.disconnected;
      message = automatic
          ? '${device.name} was not reached. Keep it on and in range, or tap Find.'
          : _friendlyError(error);
      notifyListeners();
      return false;
    } finally {
      _connectingDeviceKey = null;
      notifyListeners();
    }
  }

  Future<bool> connectNetwork(String host, {int port = 9100}) async {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty || port < 1 || port > 65535) {
      state = SaleoPrinterState.printingFailed;
      message = 'Enter a valid printer IP address and port.';
      notifyListeners();
      return false;
    }
    return connect(
      NetworkPrinterDevice(
        name: 'Network printer ($cleanHost)',
        host: cleanHost,
        port: port,
      ),
    );
  }

  Future<bool> reconnect() async {
    final device = selectedDevice;
    if (device == null) {
      message = 'Select a printer first.';
      state = SaleoPrinterState.disconnected;
      notifyListeners();
      return false;
    }
    _autoReconnectAllowed = true;
    return connect(device);
  }

  Future<bool> autoReconnectSavedPrinter() async {
    final device = selectedDevice;
    if (!_autoReconnectAllowed ||
        _autoReconnectRunning ||
        isReady ||
        scanning ||
        device == null ||
        (device is! BluetoothPrinterDevice && device is! BlePrinterDevice)) {
      return false;
    }
    _autoReconnectRunning = true;
    try {
      return await connect(device, automatic: true);
    } finally {
      _autoReconnectRunning = false;
    }
  }

  Future<void> handleAppResumed() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final now = DateTime.now();
    if (_lastResumeCheck != null &&
        now.difference(_lastResumeCheck!) < const Duration(seconds: 1)) {
      return;
    }
    _lastResumeCheck = now;
    if (selectedDevice is BluetoothPrinterDevice ||
        selectedDevice is BlePrinterDevice) {
      await autoReconnectSavedPrinter();
      return;
    }
    if (bluetoothOff || _scanAfterBluetoothEnabled) {
      final ready = await _bluetoothReady(promptWhenOff: false);
      if (ready && _scanAfterBluetoothEnabled) {
        _scanAfterBluetoothEnabled = false;
        await scanBluetooth();
      }
    }
  }

  Future<void> openBluetoothSettings() async {
    try {
      await _native.invokeMethod<void>('openBluetoothSettings');
    } catch (_) {
      message = 'Open Android settings and turn Bluetooth on.';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _autoReconnectAllowed = false;
    await _manager.disconnect();
    state = SaleoPrinterState.disconnected;
    message = selectedDevice == null
        ? 'No receipt printer connected.'
        : '${selectedDevice!.name} is disconnected.';
    notifyListeners();
  }

  Future<void> setPaperWidth(int widthMm) async {
    paperWidthMm = widthMm == 58 ? 58 : 80;
    await _storage.write(key: _paperKey, value: '$paperWidthMm');
    notifyListeners();
  }

  void markReceiptWaiting() {
    if (!isReady) {
      state = SaleoPrinterState.receiptWaiting;
      message = 'Receipt saved and waiting for a printer connection.';
      notifyListeners();
    }
  }

  Future<bool> printTest({required String companyName}) async {
    if (!_manager.isConnected) {
      state = SaleoPrinterState.receiptWaiting;
      message = 'Connect a printer before printing a test receipt.';
      notifyListeners();
      return false;
    }
    try {
      final ticket = await _createTicket();
      ticket.text(
        companyName,
        align: PrintAlign.center,
        style: const PrintTextStyle(
          bold: true,
          height: TextSize.size2,
          width: TextSize.size2,
        ),
      );
      ticket.text('SALEO PRINTER TEST', align: PrintAlign.center);
      ticket.separator();
      ticket.text('Connection successful', align: PrintAlign.center);
      _finishAndCut(ticket);
      await _manager.printTicket(ticket);
      state = SaleoPrinterState.ready;
      message = 'Test receipt printed successfully.';
      notifyListeners();
      return true;
    } catch (error) {
      state = SaleoPrinterState.printingFailed;
      message = _friendlyError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> printSale(Sale sale, {required ReceiptTemplate template}) async {
    if (!_manager.isConnected) {
      markReceiptWaiting();
      return false;
    }
    try {
      final ticket = await _createTicket();
      ticket.text(
        template.shopName,
        align: PrintAlign.center,
        style: const PrintTextStyle(
          bold: true,
          height: TextSize.size2,
          width: TextSize.size2,
        ),
      );
      if (template.location.isNotEmpty) {
        ticket.text(
          template.location,
          align: PrintAlign.center,
          style: const PrintTextStyle(bold: true, fontType: FontType.fontA),
        );
      }
      if (template.phoneNumber.isNotEmpty) {
        ticket.text(
          'Tel: ${template.phoneNumber}',
          align: PrintAlign.center,
          style: const PrintTextStyle(bold: true, fontType: FontType.fontA),
        );
      }
      ticket.feed();
      ticket.text(
        'SALES RECEIPT',
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      );
      ticket.separator();
      if (template.showReceiptId) {
        ticket.text('Receipt: ${sale.receiptNumber}');
      }
      ticket.text('Date: ${_receiptDate(sale.createdAt)}');
      final creditSale = sale.debtCents > 0;
      if (!creditSale &&
          template.showCustomerName &&
          (sale.customerName?.isNotEmpty ?? false)) {
        ticket.text('Customer: ${sale.customerName}');
      }
      if (!creditSale &&
          template.showCustomerPhone &&
          (sale.customerPhone?.isNotEmpty ?? false)) {
        ticket.text('Phone: ${sale.customerPhone}');
      }
      if (sale.customerCompany?.isNotEmpty ?? false) {
        ticket.text('Company: ${sale.customerCompany}');
      }
      if (sale.collectedBy?.isNotEmpty ?? false) {
        ticket.text('Received by: ${sale.collectedBy}');
      }
      ticket.text('${sale.operatorLabel}: ${sale.receptionistName}');
      ticket.feed();
      ticket.separator();
      // Print the headings as one line. Some generic ESC/POS printers render
      // the library's per-column bold overstrike as duplicated words. This
      // Keep the compact Font B headings and 1:6:3:3 column proportions.
      ticket.text(_tableHeaderLine(), style: _tableHeaderStyle);
      ticket.separator();
      final itemLayout = ReceiptItemLayout(
        _paperSize.charsPerLine(FontType.fontA),
      );
      for (final item in sale.items) {
        final quantity = '${item.quantity}';
        final unit = _money(item.unitPriceCents);
        final amount = _money(item.lineTotalCents);
        // Narrow paper or unusually large values must not split money figures.
        final useLargeFont = itemLayout.numbersFit(quantity, unit, amount);
        final layout = useLargeFont
            ? itemLayout
            : ReceiptItemLayout(_paperSize.charsPerLine(FontType.fontB));
        for (final line in layout.lines(
          quantity: quantity,
          description: '${item.productName} - ${item.formName}',
          unit: unit,
          amount: amount,
        )) {
          ticket.text(
            line,
            style: useLargeFont
                ? _tableTextStyle
                : const PrintTextStyle(fontType: FontType.fontB),
          );
        }
      }
      ticket.separator();
      ticket.text(
        _amountLine('TOTAL', 'GHS ${_money(sale.totalCents)}'),
        style: const PrintTextStyle(bold: true),
      );
      if (sale.mobileMoneyCents > 0) {
        ticket.text(
          _amountLine('MOMO', 'GHS ${_money(sale.mobileMoneyCents)}'),
        );
      }
      if (sale.cashTenderedCents > 0) {
        ticket.text(
          _amountLine('CASH RECEIVED', 'GHS ${_money(sale.cashTenderedCents)}'),
          style: const PrintTextStyle(bold: true),
        );
      }
      if (sale.changeGivenCents > 0) {
        ticket.text(
          _amountLine('CHANGE', 'GHS ${_money(sale.changeGivenCents)}'),
          style: const PrintTextStyle(bold: true),
        );
      }
      if (sale.debtCents > 0) {
        if (sale.previousDebtCents > 0) {
          ticket.text(
            _amountLine(
              'PREVIOUS BALANCE',
              'GHS ${_money(sale.previousDebtCents)}',
            ),
          );
        }
        final paidToday = sale.cashCents + sale.mobileMoneyCents;
        ticket.text(_amountLine('PAID TODAY', 'GHS ${_money(paidToday)}'));
        ticket.text(
          _amountLine(
            'DEBT FROM THIS SALE',
            'GHS ${_money(sale.outstandingDebtCents)}',
          ),
        );
        ticket.text(
          _amountLine(
            'TOTAL BALANCE DUE',
            'GHS ${_money(sale.previousDebtCents + sale.outstandingDebtCents)}',
          ),
          style: const PrintTextStyle(bold: true),
        );
      }
      ticket.feed();
      if (template.footerMessage.isNotEmpty) {
        ticket.text(template.footerMessage, align: PrintAlign.center);
      }
      ticket.text(
        'Powered by NAPROJEKTS.XYZ',
        align: PrintAlign.center,
        style: const PrintTextStyle(fontType: FontType.fontA),
      );
      ticket.text(
        'Simple Sales, Smarter Business',
        align: PrintAlign.center,
        style: const PrintTextStyle(fontType: FontType.fontA),
      );
      _finishAndCut(ticket);
      await _manager.printTicket(ticket);
      state = SaleoPrinterState.ready;
      message = 'Receipt ${sale.receiptNumber} printed.';
      notifyListeners();
      return true;
    } catch (error) {
      state = SaleoPrinterState.printingFailed;
      message = _friendlyError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> printDebtPayment(
    DebtLedgerEntry payment, {
    required ReceiptTemplate template,
  }) async {
    if (!payment.isPayment || !_manager.isConnected) {
      message = 'Connect a configured printer to print the payment receipt.';
      notifyListeners();
      return false;
    }
    try {
      final ticket = await _createTicket();
      ticket.text(
        template.shopName,
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      );
      if (template.location.isNotEmpty) {
        ticket.text(template.location, align: PrintAlign.center);
      }
      if (template.phoneNumber.isNotEmpty) {
        ticket.text('Tel: ${template.phoneNumber}', align: PrintAlign.center);
      }
      ticket.feed();
      ticket.text(
        'DEBT PAYMENT RECEIPT',
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      );
      ticket.text('Payment: ${payment.id}');
      ticket.text('Date: ${_receiptDate(payment.createdAt)}');
      ticket.text(
        'Company: ${payment.companyName.isEmpty ? payment.customerName : payment.companyName}',
      );
      ticket.text('Account phone: ${payment.customerPhone}');
      ticket.text('Paid by: ${payment.payerName ?? 'Not recorded'}');
      ticket.text('Payer phone: ${payment.payerPhone ?? 'Not recorded'}');
      ticket.text('Recorded by: ${payment.recordedBy ?? 'Administrator'}');
      ticket.text('Method: ${payment.paymentMethod ?? 'Not recorded'}');
      ticket.separator();
      ticket.text(
        _amountLine(
          'PREVIOUS BALANCE',
          'GHS ${_money(payment.balanceBeforeCents)}',
        ),
      );
      ticket.text(
        _amountLine('PAYMENT RECEIVED', 'GHS ${_money(payment.amountCents)}'),
        style: const PrintTextStyle(bold: true),
      );
      ticket.text(
        _amountLine(
          'REMAINING BALANCE',
          'GHS ${_money(payment.balanceAfterCents)}',
        ),
      );
      if (payment.note?.isNotEmpty ?? false) {
        ticket.text('Reference: ${payment.note}');
      }
      ticket.feed();
      if (template.footerMessage.isNotEmpty) {
        ticket.text(template.footerMessage, align: PrintAlign.center);
      }
      ticket.text('Powered by NAPROJEKTS.XYZ', align: PrintAlign.center);
      _finishAndCut(ticket);
      await _manager.printTicket(ticket);
      state = SaleoPrinterState.ready;
      message = 'Payment receipt sent to printer.';
      notifyListeners();
      return true;
    } catch (error) {
      state = SaleoPrinterState.printingFailed;
      message = _friendlyError(error);
      notifyListeners();
      return false;
    }
  }

  PaperSize get _paperSize =>
      paperWidthMm == 58 ? PaperSize.mm58 : PaperSize.mm80;

  // Font A is larger than Font B without double-width text or bold items.
  static const _tableTextStyle = PrintTextStyle(fontType: FontType.fontA);
  static const _tableHeaderStyle = PrintTextStyle(
    bold: true,
    fontType: FontType.fontB,
  );

  Future<Ticket> _createTicket() async {
    // Reuse immutable capabilities, never the mutable ticket/receipt buffer.
    final loading = _profile ??= CapabilityProfile.load();
    try {
      return Ticket(_paperSize, await loading);
    } catch (_) {
      if (identical(_profile, loading)) _profile = null;
      rethrow;
    }
  }

  String _amountLine(String label, String amount) {
    final width = _paperSize.charsPerLine(null);
    final gap = width - label.length - amount.length;
    if (gap < 1) return '$label $amount';
    return '$label${' ' * gap}$amount';
  }

  String _tableHeaderLine() {
    final width = _paperSize.charsPerLine(FontType.fontB);
    final characters = List<String>.filled(width, ' ');
    final descriptionStart = (width * 1 / 13).round();
    final unitRightEdge = (width * 10 / 13).round();

    void writeAt(String text, int start) {
      for (
        var index = 0;
        index < text.length && start + index < characters.length;
        index++
      ) {
        characters[start + index] = text[index];
      }
    }

    writeAt('Qty', 0);
    writeAt('Description', descriptionStart);
    writeAt('Unit', unitRightEdge - 'Unit'.length);
    writeAt('Amount', width - 'Amount'.length);
    return characters.join().trimRight();
  }

  void _finishAndCut(Ticket ticket) {
    ticket.text(
      '########',
      align: PrintAlign.center,
      style: const PrintTextStyle(fontType: FontType.fontA),
    );
    // ESC/POS printers print above the cutter. These lines move the completed
    // footer to the blade before the cut command, so no footer remains in the
    // buffer and appears at the top of the next receipt.
    // Feed the full footer past the cutter before issuing the cut command.
    // Several 80 mm printers need these four lines to avoid cutting through
    // the footer and carrying its last lines into the following receipt.
    ticket.cut(linesBefore: 4);
  }

  void _handleManagerState(PrinterConnectionState managerState) {
    state = switch (managerState) {
      PrinterConnectionState.connected => SaleoPrinterState.ready,
      PrinterConnectionState.connecting ||
      PrinterConnectionState.scanning ||
      PrinterConnectionState.disconnecting => SaleoPrinterState.connecting,
      PrinterConnectionState.printing => SaleoPrinterState.ready,
      PrinterConnectionState.error => SaleoPrinterState.printingFailed,
      PrinterConnectionState.disconnected => SaleoPrinterState.disconnected,
    };
    notifyListeners();
  }

  String _deviceKey(PrinterDevice device) => switch (device) {
    BluetoothPrinterDevice value => 'bluetooth:${value.address}',
    BlePrinterDevice value => 'ble:${value.deviceId}',
    UsbPrinterDevice value => 'usb:${value.identifier}',
    NetworkPrinterDevice value => 'network:${value.host}:${value.port}',
    _ => '${device.connectionType.name}:${device.name}',
  };

  Future<void> _saveDevice(PrinterDevice device) async {
    final (type, address, port) = switch (device) {
      NetworkPrinterDevice value => ('network', value.host, value.port),
      BluetoothPrinterDevice value => ('bluetooth', value.address, null),
      BlePrinterDevice value => ('ble', value.deviceId, null),
      UsbPrinterDevice value => ('usb', value.identifier, null),
      _ => ('', '', null),
    };
    if (type.isEmpty) return;
    await _storage.write(key: _typeKey, value: type);
    await _storage.write(key: _nameKey, value: device.name);
    await _storage.write(key: _addressKey, value: address);
    if (port != null) {
      await _storage.write(key: _portKey, value: '$port');
    } else {
      await _storage.delete(key: _portKey);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst(RegExp(r'^.*Exception:\s*'), '');
    return text.isEmpty
        ? 'The printer connection failed. Check the printer and try again.'
        : text;
  }

  static String _money(int cents) {
    final negative = cents < 0;
    final absolute = cents.abs();
    final whole = absolute ~/ 100;
    final decimal = (absolute % 100).toString().padLeft(2, '0');
    final grouped = whole.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '${negative ? '-' : ''}$grouped.$decimal';
  }

  static String _receiptDate(DateTime date) {
    final value = date.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    unawaited(_manager.dispose());
    super.dispose();
  }
}
