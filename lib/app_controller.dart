import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'database_service.dart';
import 'device_notification_service.dart';
import 'auth_service.dart';
import 'models.dart';
import 'printer_service.dart';
import 'product_import_service.dart';
import 'sync_service.dart';

enum AppSyncState { idle, syncing, synced, offline, notConfigured, failed }

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  List<Map<String, dynamic>> workflows = [];
  Map<String, String> printStates = {};
  bool directCorrections = false;
  bool _workflowBusy = false;
  bool _printBusy = false;
  Completer<void>? _printCompletion;
  final Set<Future<void>> _liveImports = {};
  Completer<void>? _workflowCompletion;
  Completer<void>? _checkoutCompletion;
  Completer<void>? _logoutCompletion;
  bool signingOut = false;
  bool signOutPromptOpen = false;
  bool loadingCompanyData = false;
  bool checkoutReady = false;
  String? checkoutLoadError;
  bool _preferencesBusy = false;
  Future<void> _preferenceWrites = Future<void>.value();
  final Set<Future<void>> _immediateUploads = {};
  List<Sale> get pendingPrintReceipts => sales
      .where(
        (sale) =>
            !sale.voided &&
            printStates.containsKey(sale.transactionUuid) &&
            printStates[sale.transactionUuid] != 'sent',
      )
      .toList();
  int get pendingApprovalCount =>
      workflows.where((w) => w['status'] == 'pending').length;
  List<String> savedCategories = [];
  List<String> get productCategories =>
      ({
          ...savedCategories,
          ...products.map((p) => p.category),
        }.where((name) => name.trim().isNotEmpty).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));

  Future<void> createCategory(String name) async {
    _requireAdministrator();
    if (currentUser?.role != UserRole.admin) {
      throw StateError('Administrator required.');
    }
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 100) {
      throw StateError('Enter a category name of 1–100 characters.');
    }
    if (productCategories.any(
      (n) => n.toLowerCase() == normalized.toLowerCase(),
    )) {
      return;
    }
    final result = await syncService.workflowRequest(
      '/categories',
      body: {'name': normalized},
    );
    if (result == null) {
      throw StateError(
        syncService.workflowError ?? 'Category could not be saved to server.',
      );
    }
    savedCategories.add(result['name'] as String);
    await database.writeWorkflowMeta(
      'product.categories',
      jsonEncode(savedCategories),
    );
    notifyListeners();
  }

  DateTime? _workflowNextAttempt;
  Future<void> refreshWorkflows({bool force = true}) async {
    if (_workflowBusy || currentUser == null || signingOut) return;
    if (!force &&
        _workflowNextAttempt != null &&
        DateTime.now().isBefore(_workflowNextAttempt!)) {
      return;
    }
    _workflowBusy = true;
    _workflowCompletion = Completer<void>();
    final identity = currentUser;
    try {
      var outbox = (jsonDecode(
        await database.readWorkflowMeta('workflow.outbox') ?? '[]',
      ) as List).map((v) => (v as Map).cast<String, dynamic>()).toList();
      final remote = await syncService.workflowRequest('');
      _workflowNextAttempt = DateTime.now().add(
        Duration(seconds: remote == null ? 300 : 30),
      );
      if (!identical(identity, currentUser) || signingOut) return;
      final rows = remote == null
          ? <Map<String, dynamic>>[]
          : (remote['workflows'] as List)
                .map((v) => (v as Map).cast<String, dynamic>())
                .toList();
      for (final submission in List<Map<String, dynamic>>.from(outbox)) {
        final existing = rows
            .where((r) => r['uuid'] == submission['uuid'])
            .firstOrNull;
        // Recover a lost successful response without resubmitting a decided event.
        if (existing != null && existing['revision'] > submission['revision']) {
          final history = existing['history'] as List? ?? [];
          if (history.any(
            (v) =>
                v['action'] == 'submitted' &&
                jsonEncode(v['details']) == jsonEncode(submission['details']) &&
                v['reason'] == submission['reason'],
          )) {
            await database.acknowledgeWorkflow(submission);
          }
          continue;
        }
        if (await syncService.workflowRequest('', body: submission) != null) {
          await database.acknowledgeWorkflow(submission);
        }
        if (!identical(identity, currentUser) || signingOut) return;
      }
      final hadUploads = outbox.isNotEmpty;
      outbox = (jsonDecode(
        await database.readWorkflowMeta('workflow.outbox') ?? '[]',
      ) as List).map((v) => (v as Map).cast<String, dynamic>()).toList();
      final updated = hadUploads && remote != null
          ? await syncService.workflowRequest('')
          : remote;
      if (!identical(identity, currentUser) || signingOut) return;
      if (updated != null) {
        workflows = (updated['workflows'] as List)
            .map((v) => (v as Map).cast<String, dynamic>())
            .toList();
        await database.writeWorkflowMeta(
          'workflow.cache',
          jsonEncode(workflows),
        );
        for (final item in workflows) {
          await database.notifyWorkflow(item);
          if (item['status'] == 'approved') {
            if (item['kind'] == 'stock') {
              await database.recordApprovedReceipt(item);
            }
            if (item['result_sale'] != null) {
              await database.upsertRemoteSales([
                (item['result_sale'] as Map).cast<String, dynamic>(),
              ], applyStockChanges: false);
            }
          }
        }
        await _reloadAll();
      }
      final value = await syncService.workflowRequest('/policy');
      if (!identical(identity, currentUser) || signingOut) return;
      if (value != null) {
        directCorrections = value['direct_corrections'] == true;
      }
      final categories = await syncService.workflowRequest('/categories');
      if (!identical(identity, currentUser) || signingOut) return;
      if (categories != null) {
        savedCategories = (categories['categories'] as List).cast<String>();
        await database.writeWorkflowMeta(
          'product.categories',
          jsonEncode(savedCategories),
        );
      }
      workflows = [
        ...workflows,
        for (final item in outbox)
          {
            ...item,
            'status': 'queued',
            'submitted_by': identity?.displayName,
            'history': <dynamic>[],
          },
      ];
      notifyListeners();
    } catch (error) {
      syncService.workflowError =
          'Approval sync failed; submissions remain queued. $error';
    } finally {
      _workflowBusy = false;
      _workflowCompletion?.complete();
      _workflowCompletion = null;
    }
  }

  Future<void> _queueWorkflow(Map<String, dynamic> submission) async {
    await database.queueWorkflow(submission);
    await refreshWorkflows();
  }

  Future<void> requestSaleCorrection(Sale sale, String reason) async {
    if (sale.voided || reason.trim().isEmpty) {
      throw StateError('A valid sale and reason are required.');
    }
    if (currentUser?.role != UserRole.admin &&
        sale.receptionistUsername != currentUser?.username) {
      throw StateError('You may request corrections only for your own sales.');
    }
    await _queueWorkflow({
      'uuid': const Uuid().v4(),
      'kind': 'correction',
      'revision': 0,
      'reason': reason.trim(),
      'details': {
        'transaction_uuid': sale.transactionUuid,
        'receipt_number': sale.receiptNumber,
      },
    });
    unawaited(syncPending());
  }

  Future<void> saveCorrectionPolicy(bool allow) async {
    if (currentUser?.role != UserRole.admin) {
      throw StateError('Administrator required.');
    }
    final result = await syncService.workflowRequest(
      '/policy',
      put: true,
      body: {'direct_corrections': allow},
    );
    if (result == null) throw StateError(syncService.workflowError!);
    directCorrections = allow;
    notifyListeners();
  }

  Future<void> decideWorkflow(
    Map<String, dynamic> row,
    bool approve,
    String reason,
  ) async {
    if (currentUser?.role != UserRole.admin) {
      throw StateError('Administrator required.');
    }
    final result = await syncService.workflowRequest(
      '/${Uri.encodeComponent(row['uuid'])}/decision',
      body: {'approve': approve, 'reason': reason, 'revision': row['revision']},
    );
    if (result == null) throw StateError(syncService.workflowError!);
    await refreshWorkflows();
    await syncPending();
  }

  Future<void> resubmitWorkflow(
    Map<String, dynamic> row,
    Map<String, dynamic> details,
  ) => _queueWorkflow({
    'uuid': row['uuid'],
    'kind': row['kind'],
    'revision': row['revision'],
    'reason': 'Corrected and resubmitted',
    'details': details,
  });

  Future<bool> printReceipt(Sale sale) async {
    if (_printBusy || sale.voided || signingOut) return false;
    _printBusy = true;
    _printCompletion = Completer<void>();
    final identity = currentUser;
    try {
      printStates[sale.transactionUuid] = printer.isReady
          ? 'sending'
          : 'pending';
      await database.writeWorkflowMeta('print.states', jsonEncode(printStates));
      notifyListeners();
      if (!printer.isReady) {
        printer.markReceiptWaiting();
        return false;
      }
      final sent = await printer.printSale(sale, template: receiptTemplate);
      if (!identical(identity, currentUser)) return sent;
      printStates[sale.transactionUuid] = sent ? 'sent' : 'check print result';
      await database.writeWorkflowMeta('print.states', jsonEncode(printStates));
      notifyListeners();
      return sent;
    } finally {
      _printBusy = false;
      _printCompletion?.complete();
      _printCompletion = null;
    }
  }

  Future<bool> printDebtPaymentReceipt(DebtLedgerEntry payment) async {
    if (_printBusy || signingOut || currentUser?.role != UserRole.admin) {
      return false;
    }
    _printBusy = true;
    _printCompletion = Completer<void>();
    try {
      return await printer.printDebtPayment(payment, template: receiptTemplate);
    } finally {
      _printBusy = false;
      _printCompletion?.complete();
      _printCompletion = null;
    }
  }

  AppController(
    this.database,
    this.syncService,
    this.authService, {
    PrinterService? printerService,
    DeviceNotificationService? deviceNotificationService,
  }) : printer = printerService ?? PrinterService(),
       deviceNotifications =
           deviceNotificationService ?? const DeviceNotificationService();

  final DatabaseService database;
  final SyncService syncService;
  final AuthService authService;
  final PrinterService printer;
  final DeviceNotificationService deviceNotifications;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Set<int> _seenNotificationIds = <int>{};
  bool _notificationSnapshotReady = false;
  Timer? _foregroundRetry;
  bool _foreground = true;
  bool _syncInFlight = false;
  Completer<void>? _syncCompletion;
  bool _syncRequested = false;
  bool _retryInFlight = false;
  int _sessionGeneration = 0;
  DateTime? _lastSyncAttempt;
  StreamSubscription<int>? _notificationTapSubscription;
  int? pendingNotificationTap;

  void consumeNotificationTap() => pendingNotificationTap = null;

  void _startForegroundUpdates() {
    _stopForegroundUpdates();
    if (!_foreground ||
        currentUser == null ||
        signingOut ||
        !checkoutReady ||
        !syncService.isConfigured) {
      return;
    }
    final generation = _sessionGeneration;
    if (currentUser?.role == UserRole.admin) {
      syncService.startLiveSales(
        onSales: (rows, replay) async {
          if (generation != _sessionGeneration || !_foreground) return;
          final job = () async {
            await database.upsertRemoteSales(
              rows,
              applyStockChanges: false,
              notifySales: !replay,
            );
            if (generation != _sessionGeneration) return;
            await _reloadAll(alertNew: !replay);
            notifyListeners();
          }();
          _liveImports.add(job);
          try {
            await job;
          } finally {
            _liveImports.remove(job);
          }
        },
        onError: (message) {
          if (generation != _sessionGeneration || !_foreground) return;
          syncMessage = message;
          notifyListeners();
        },
      );
    }
    _foregroundRetry = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_retryInFlight ||
          _syncInFlight ||
          generation != _sessionGeneration ||
          !_foreground) {
        return;
      }
      _retryInFlight = true;
      try {
        if ((await database.getPendingSales()).isNotEmpty ||
            _lastSyncAttempt == null ||
            DateTime.now().difference(_lastSyncAttempt!) >=
                const Duration(seconds: 30)) {
          await syncPending();
        }
      } catch (_) {
        // Offline records remain queued; the next foreground tick retries.
      } finally {
        _retryInFlight = false;
      }
    });
  }

  void _stopForegroundUpdates() {
    _foregroundRetry?.cancel();
    _foregroundRetry = null;
    syncService.stopLiveSales();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final desktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    _foreground =
        state == AppLifecycleState.resumed ||
        (desktop &&
            (state == AppLifecycleState.inactive ||
                state == AppLifecycleState.hidden));
    if (_foreground) {
      _startForegroundUpdates();
      if (currentUser != null) unawaited(syncPending());
    } else {
      _stopForegroundUpdates();
    }
  }

  bool initializing = true;
  bool busy = false;
  String? errorMessage;
  String? syncMessage;
  AppUser? currentUser;
  List<Product> products = [];
  List<Sale> sales = [];
  List<AppUser> users = [];
  List<StaffMember> staff = [];
  List<StockMovement> stockMovements = [];
  List<CustomerRecord> customers = [];
  List<DebtorSummary> debtors = [];
  List<CreditPaymentRecord> creditPayments = [];
  List<StockDiscrepancy> stockDiscrepancies = [];
  List<StockReceipt> stockReceipts = [];
  List<AppNotificationRecord> notifications = [];
  InventoryPreferences inventoryPreferences = const InventoryPreferences();
  String? staffMessage;
  List<CartLine> cart = [];
  String? desktopDraftKey;
  Future<void> Function()? flushDesktopDraft;
  int completedSalesRevision = 0;
  DashboardSummary summary = const DashboardSummary(
    todayCents: 0,
    todayTransactions: 0,
    pendingSync: 0,
    activeReceptionists: 0,
  );
  AppSyncState syncState = AppSyncState.idle;
  DateTime? lastSuccessfulSync;
  CompanyPreview? currentCompany;
  ReceiptTemplateSettings receiptTemplateSettings =
      ReceiptTemplateSettings.forCompany('Saleo Shop');
  ReceiptTemplate get receiptTemplate => receiptTemplateSettings.activeTemplate;

  int get cartTotalCents =>
      cart.fold(0, (sum, line) => sum + line.lineTotalCents);
  int get cartItemCount => cart.fold(0, (sum, line) => sum + line.quantity);
  List<Product> get activeProducts =>
      products.where((product) => product.active).toList();
  int get unreadNotificationCount =>
      notifications.where((item) => !item.isRead).length;
  List<Product> get lowStockProducts => products
      .where((product) => product.active && product.isLowStock)
      .toList();

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _notificationTapSubscription = deviceNotifications.taps.listen((id) {
        pendingNotificationTap = id;
        notifyListeners();
      });
      pendingNotificationTap = await deviceNotifications.initialize();
      // Printer discovery must not delay access to the business records.
      unawaited(
        printer.initialize().catchError((Object error) {
          syncMessage = 'Printer setup unavailable. Sales remain accessible.';
        }),
      );
      final savedMember = await authService.loadSession();
      await database.initialize(companyId: savedMember?.company.companyId);
      if (savedMember != null) {
        syncService.useSession(savedMember.token);
        currentUser = await database.upsertAuthenticatedUser(
          username: savedMember.username,
          displayName: savedMember.displayName,
          role: savedMember.role,
          jobTitle: savedMember.jobTitle,
        );
        currentCompany = savedMember.company;
        receiptTemplateSettings = savedMember.company.receiptTemplates;
      }
      await _reloadAll();
      if (savedMember != null) await loadCheckoutData();
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        if (!results.contains(ConnectivityResult.none)) {
          unawaited(syncPending());
        } else {
          syncState = AppSyncState.offline;
          syncMessage = 'Offline - completed sales will sync later.';
          notifyListeners();
        }
      });
    } catch (error) {
      errorMessage = 'The local database could not be opened: $error';
    } finally {
      initializing = false;
      _startForegroundUpdates();
      notifyListeners();
      if (currentUser != null) unawaited(syncPending());
    }
  }

  // Legacy entry point fails closed; all sign-ins require company-scoped server authentication.
  Future<bool> login(String username, String password) async {
    throw const AuthException(
      'Use company sign-in with your username and PIN.',
    );
  }

  Future<void> acceptAuthenticatedMember(AuthenticatedMember member) async {
    if (member.token.trim().isEmpty ||
        member.username.trim().isEmpty ||
        !RegExp(r'^[A-Z0-9-]{4,24}$')
            .hasMatch(member.company.companyId.trim().toUpperCase())) {
      throw const AuthException(
        'The server returned an invalid company session.',
      );
    }
    await _logoutCompletion?.future;
    _stopForegroundUpdates();
    _sessionGeneration++;
    await _syncCompletion?.future;
    _seenNotificationIds.clear();
    _notificationSnapshotReady = false;
    syncService.useSession(member.token);
    await database.switchCompany(member.company.companyId);
    currentUser = await database.upsertAuthenticatedUser(
      username: member.username,
      displayName: member.displayName,
      role: member.role,
      jobTitle: member.jobTitle,
    );
    currentCompany = member.company;
    receiptTemplateSettings = member.company.receiptTemplates;
    errorMessage = null;
    await _reloadAll();
    await loadCheckoutData();
    _startForegroundUpdates();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> updateAdminUsername(String username) async {
    if (currentUser?.role != UserRole.admin || currentCompany == null) {
      throw const AuthException('Sign in as an administrator first.');
    }
    final member = await authService.updateAdminUsername(username);
    _stopForegroundUpdates();
    _sessionGeneration++;
    await _syncCompletion?.future;
    syncService.useSession(member.token);
    currentUser = await database.upsertAuthenticatedUser(
      username: member.username,
      displayName: member.displayName,
      role: member.role,
      jobTitle: member.jobTitle,
    );
    currentCompany = member.company;
    receiptTemplateSettings = member.company.receiptTemplates;
    await _reloadAll();
    _startForegroundUpdates();
    notifyListeners();
  }

  Future<void> logout() async {
    if (signingOut) return _logoutCompletion?.future;
    signingOut = true;
    _logoutCompletion = Completer<void>();
    notifyListeners();
    try {
      pendingNotificationTap = null;
      await flushDesktopDraft?.call();
      _stopForegroundUpdates();
      _sessionGeneration++;
      _syncRequested = false;
      await _syncCompletion?.future;
      await _checkoutCompletion?.future;
      await _workflowCompletion?.future;
      await _printCompletion?.future;
      await Future.wait(_liveImports.toList());
      await Future.wait(_immediateUploads.toList());
      await _preferenceWrites;
      await _persistCatalogSnapshot();
      _seenNotificationIds.clear();
      _notificationSnapshotReady = false;
      await authService.revokeCurrentSession();
      await authService.clearSession();
      syncService.useSession(null);
      currentUser = null;
      currentCompany = null;
      receiptTemplateSettings = ReceiptTemplateSettings.forCompany(
        'Saleo Shop',
      );
      cart = [];
      products = [];
      sales = [];
      users = [];
      staff = [];
      stockMovements = [];
      customers = [];
      debtors = [];
      creditPayments = [];
      stockDiscrepancies = [];
      stockReceipts = [];
      workflows = [];
      savedCategories = [];
      _workflowNextAttempt = null;
      printStates = {};
      directCorrections = false;
      notifications = [];
      staffMessage = null;
      errorMessage = null;
      checkoutReady = false;
      checkoutLoadError = null;
      await database.lock();
    } finally {
      signingOut = false;
      // If revocation failed, the user is still signed in. Restore foreground
      // updates stopped above, without discarding any queued work.
      if (currentUser != null) _startForegroundUpdates();
      _logoutCompletion?.complete();
      _logoutCompletion = null;
      notifyListeners();
    }
  }

  String get _preferenceScope =>
      'preferences.${currentUser!.username.toLowerCase()}';

  Future<int> unsyncedRecordCount() async {
    final pending = await database.getPendingSales();
    final payments = await database.getPendingDebtPayments();
    final workflows = jsonDecode(
      await database.readWorkflowMeta('workflow.outbox') ?? '[]',
    ) as List;
    final preferences = jsonDecode(
      await database.readWorkflowMeta('$_preferenceScope.outbox') ?? '{}',
    ) as Map;
    return pending.length +
        payments.length +
        workflows.length +
        (preferences.isEmpty ? 0 : 1) +
        syncService.pendingCatalogCount(
          products,
          customers,
          stockReceipts,
          stockMovements,
          admin: currentUser?.role == UserRole.admin,
        );
  }

  Future<void> loadCheckoutData() async {
    if (loadingCompanyData || currentUser == null || signingOut) return;
    loadingCompanyData = true;
    checkoutLoadError = null;
    _checkoutCompletion = Completer<void>();
    final generation = _sessionGeneration;
    notifyListeners();
    try {
      final cached = await database.readWorkflowMeta('checkout.ready');
      checkoutReady = cached == '1';
      final catalogSnapshot = await database.readWorkflowMeta(
        'sync.catalog.snapshot',
      );
      if (catalogSnapshot != null) {
        syncService.restoreCatalogSnapshot(
          (jsonDecode(catalogSnapshot) as Map).cast<String, dynamic>(),
        );
      }
      final snapshot = await database.readWorkflowMeta(
        '$_preferenceScope.snapshot',
      );
      final firstMigration =
          snapshot == null &&
          await database.readWorkflowMeta('preferences.migrated') == null;
      final previousPreferences = inventoryPreferences;
      inventoryPreferences =
          (firstMigration ? previousPreferences : const InventoryPreferences())
              .applySharedJson(
                snapshot == null
                    ? {}
                    : (jsonDecode(snapshot) as Map).cast<String, dynamic>(),
              );
      await database.saveInventoryPreferences(inventoryPreferences);
      // Preserve unuploaded local catalogue edits before importing cloud records.
      // Empty/new devices make no upload request here.
      await Future.wait<bool>([
        syncService.pushCustomers(customers),
        if (currentUser?.role == UserRole.admin)
          syncService.pushProducts(products),
      ]);
      if (generation != _sessionGeneration || signingOut) return;
      await _persistCatalogSnapshot();
      final preserveProducts = currentUser?.role == UserRole.admin
          ? syncService.pendingProductCodes(products)
          : <String>{};
      final preserveCustomers = syncService.pendingCustomerPhones(customers);
      final values = await Future.wait<Object?>([
        syncService.pullProducts(),
        syncService.pullCustomers(),
        syncService.pullReceiptTemplateSettings(
          companyName: currentCompany?.name ?? 'Saleo Shop',
        ),
        syncService.workflowRequest('/preferences'),
        syncService.pullStockMovements(),
      ]);
      if (generation != _sessionGeneration || signingOut) return;
      if (values[0] == null ||
          values[1] == null ||
          values[2] == null ||
          values[3] == null ||
          values[4] == null) {
        throw StateError(
          'Company data could not be downloaded. Check your connection and retry.',
        );
      }
      await database.upsertRemoteProducts(
        values[0] as List<Map<String, dynamic>>,
        preserveCodes: preserveProducts,
      );
      await database.upsertRemoteCustomers(
        values[1] as List<Map<String, dynamic>>,
        preservePhones: preserveCustomers,
      );
      await database.upsertRemoteStockMovements(
        values[4] as List<Map<String, dynamic>>,
      );
      receiptTemplateSettings = values[2] as ReceiptTemplateSettings;
      await database.saveReceiptTemplateSettings(
        _receiptTemplateScope,
        receiptTemplateSettings,
      );
      await _applySharedPreferences(values[3] as Map<String, dynamic>);
      if (firstMigration) {
        final existing = (values[3] as Map)['values'] as Map;
        final defaults = const InventoryPreferences().toSharedJson();
        final legacy = previousPreferences.toSharedJson();
        final changes = {
          for (final key in legacy.keys)
            if (legacy[key] != defaults[key] &&
                !existing.containsKey(key) &&
                (currentUser?.role == UserRole.admin ||
                    (key != 'collect_customer_details' &&
                        key != 'staff_can_receive_stock')))
              key: legacy[key],
        };
        final queued = (jsonDecode(
          await database.readWorkflowMeta('$_preferenceScope.outbox') ?? '{}',
        ) as Map).cast<String, dynamic>();
        await database.writeWorkflowMeta(
          '$_preferenceScope.outbox',
          jsonEncode({...changes, ...queued}),
        );
        await database.writeWorkflowMeta('preferences.migrated', '1');
      }
      await database.writeWorkflowMeta('checkout.ready', '1');
      checkoutReady = true;
      await _reloadAll(alertNew: false);
      syncService.rememberDownloadedMovements(
        stockMovements,
        products,
        values[4] as List<Map<String, dynamic>>,
      );
      _rememberDownloadedCatalog(
        values[0] as List<Map<String, dynamic>>,
        values[1] as List<Map<String, dynamic>>,
        preserveProducts,
        preserveCustomers,
      );
      await _persistCatalogSnapshot();
    } catch (_) {
      checkoutLoadError = checkoutReady
          ? 'Using saved company data. Online updates failed; retry sync.'
          : 'Products, customers and checkout settings are not ready. Check your connection and retry.';
    } finally {
      loadingCompanyData = false;
      _checkoutCompletion?.complete();
      _checkoutCompletion = null;
      notifyListeners();
    }
    if (checkoutReady && !signingOut) {
      _startForegroundUpdates();
      unawaited(syncPending());
    }
  }

  Future<void> _persistCatalogSnapshot() => database.writeWorkflowMeta(
    'sync.catalog.snapshot',
    jsonEncode(syncService.catalogSnapshot),
  );

  void _rememberDownloadedCatalog(
    List<Map<String, dynamic>> remoteProducts,
    List<Map<String, dynamic>> remoteCustomers,
    Set<String> preserveProducts,
    Set<String> preserveCustomers,
  ) {
    final codes = remoteProducts
        .map((p) => p['code'].toString().trim().toUpperCase())
        .toSet();
    final phones = remoteCustomers
        .map((c) => c['phone'].toString().trim())
        .toSet();
    syncService.rememberDownloadedProducts(
      products
          .where(
            (p) => codes.contains(p.code) && !preserveProducts.contains(p.code),
          )
          .toList(),
    );
    syncService.rememberDownloadedCustomers(
      customers
          .where(
            (c) =>
                phones.contains(c.phone) &&
                !preserveCustomers.contains(c.phone),
          )
          .toList(),
    );
  }

  void addToCart(Product product, SellingForm form, int quantity) {
    if (quantity < 1) return;
    final index = cart.indexWhere((line) => line.form.id == form.id);
    if (index >= 0) {
      final current = cart[index];
      cart[index] = current.copyWith(quantity: current.quantity + quantity);
    } else {
      cart = [
        ...cart,
        CartLine(product: product, form: form, quantity: quantity),
      ];
    }
    notifyListeners();
  }

  void setCartQuantity(int index, int quantity) {
    if (quantity <= 0) {
      cart = [...cart]..removeAt(index);
    } else {
      cart = [...cart]..[index] = cart[index].copyWith(quantity: quantity);
    }
    notifyListeners();
  }

  Future<Sale?> completeSale({
    required String paymentMethod,
    required int cashCents,
    required int mobileMoneyCents,
    required int cashTenderedCents,
    required int changeGivenCents,
    int debtCents = 0,
    int debtPaidCents = 0,
    DateTime? debtDueAt,
    String? debtNote,
    String? customerName,
    String? customerPhone,
    String? customerCompany,
    String? customerAddress,
    String? collectedBy,
    String? collectorPhone,
    bool allowStockOverride = false,
  }) async {
    final user = currentUser;
    if (user == null || cart.isEmpty) return null;
    if (!user.active ||
        currentCompany == null ||
        signingOut ||
        loadingCompanyData ||
        !checkoutReady) {
      throw StateError(
        'An active, ready company session is required to save sales.',
      );
    }
    if (busy) throw StateError('A sale is already being recorded.');
    if (cart.any((line) => !line.product.active || !line.form.active)) {
      throw StateError(
        'This draft contains a removed product or selling form. Review it before checkout.',
      );
    }
    busy = true;
    notifyListeners();
    try {
      await flushDesktopDraft?.call();
      final sale = await database.createSale(
        user,
        List.unmodifiable(cart),
        paymentMethod: paymentMethod,
        cashCents: cashCents,
        mobileMoneyCents: mobileMoneyCents,
        cashTenderedCents: cashTenderedCents,
        changeGivenCents: changeGivenCents,
        desktopDraftKey: desktopDraftKey,
        debtCents: debtCents,
        debtPaidCents: debtPaidCents,
        debtDueAt: debtDueAt,
        debtNote: debtNote,
        customerName: customerName,
        customerPhone: customerPhone,
        customerCompany: customerCompany,
        customerAddress: customerAddress,
        collectedBy: collectedBy,
        collectorPhone: collectorPhone,
        operatorLabel: receiptTemplate.useStaffRole
            ? user.jobTitle
            : receiptTemplate.operatorLabel,
        allowStockOverride: allowStockOverride,
      );
      completedSalesRevision++;
      cart = [];
      if (!printer.isReady) printer.markReceiptWaiting();
      printStates[sale.transactionUuid] = 'pending';
      await database.writeWorkflowMeta('print.states', jsonEncode(printStates));
      await _reloadAll();
      final upload = _uploadSaleImmediately(sale);
      _immediateUploads.add(upload);
      unawaited(upload.whenComplete(() => _immediateUploads.remove(upload)));
      return sale;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<StockShortage>> getCartStockShortages() =>
      database.getStockShortages(cart);

  Future<void> _uploadSaleImmediately(Sale sale) async {
    final generation = _sessionGeneration;
    try {
      // Upload new sales without waiting for unrelated catalogue requests.
      // The server deduplicates retry attempts using the transaction UUID.
      final result = await syncService.pushSales([sale]);
      if (generation != _sessionGeneration || currentUser == null) return;
      if (result.type == SyncResultType.success &&
          result.acceptedIds.contains(sale.transactionUuid)) {
        await database.markSalesSynced([sale.transactionUuid]);
        await _reloadAll();
        notifyListeners();
      }
      await syncPending();
    } catch (_) {
      // The committed local receipt remains pending for foreground retry.
    }
  }

  Future<void> saveReceiptTemplate(ReceiptTemplate template) async {
    _requireAdministrator();
    errorMessage = null;
    final scope = _receiptTemplateScope;
    receiptTemplateSettings = receiptTemplateSettings.withCustom(template);
    await database.saveReceiptTemplateSettings(scope, receiptTemplateSettings);
    notifyListeners();
    if (currentCompany != null) {
      unawaited(_pushReceiptTemplate(template, scope));
    }
  }

  Future<void> selectReceiptTemplate(ReceiptTemplateKind selection) async {
    _requireAdministrator();
    if (selection == ReceiptTemplateKind.custom &&
        receiptTemplateSettings.customTemplate == null) {
      return;
    }
    final scope = _receiptTemplateScope;
    receiptTemplateSettings = receiptTemplateSettings.withActive(selection);
    await database.saveReceiptTemplateSettings(scope, receiptTemplateSettings);
    notifyListeners();
    if (currentCompany != null) {
      unawaited(_pushReceiptTemplateSelection(selection, scope));
    }
  }

  Future<void> _pushReceiptTemplate(
    ReceiptTemplate template,
    String scope,
  ) async {
    try {
      final saved = await authService.updateReceiptTemplate(template);
      await database.saveReceiptTemplateSettings(scope, saved);
      if (_receiptTemplateScope == scope) receiptTemplateSettings = saved;
    } on AuthException {
      if (_receiptTemplateScope == scope) {
        syncMessage = 'Receipt template is saved on this device. Online template sync is not available yet.';
      }
    }
    notifyListeners();
  }

  Future<void> _pushReceiptTemplateSelection(
    ReceiptTemplateKind selection,
    String scope,
  ) async {
    try {
      final saved = await authService.selectReceiptTemplate(
        selection,
        companyName: currentCompany?.name ?? 'Saleo Shop',
      );
      await database.saveReceiptTemplateSettings(scope, saved);
      if (_receiptTemplateScope == scope) receiptTemplateSettings = saved;
    } on AuthException {
      if (_receiptTemplateScope == scope) {
        syncMessage = 'Receipt choice is cached on this device and will sync when the server is updated.';
      }
    }
    notifyListeners();
  }

  Future<void> syncPending() async {
    if (currentUser == null ||
        signingOut ||
        loadingCompanyData ||
        !checkoutReady) {
      return;
    }
    if (_syncInFlight) {
      _syncRequested = true;
      await _syncCompletion?.future;
      return;
    }
    _syncInFlight = true;
    _lastSyncAttempt = DateTime.now();
    _syncCompletion = Completer<void>();
    try {
      do {
        _syncRequested = false;
        await _performSync();
      } while (_syncRequested && currentUser != null && !signingOut);
    } catch (_) {
      if (currentUser != null) {
        syncState = AppSyncState.failed;
        syncMessage = 'Synchronization was interrupted. Saved records remain queued for retry.';
        notifyListeners();
      }
    } finally {
      _syncInFlight = false;
      _syncCompletion?.complete();
      _syncCompletion = null;
    }
  }

  Future<void> _performSync() async {
    if (syncState == AppSyncState.syncing) return;
    // Settings are small and should reach the server before larger history batches.
    final preferencesSynced = await _syncSharedPreferences();
    if (signingOut) return;
    final pending = await database.getPendingSales();
    if (pending.isEmpty) {
      if (!syncService.isConfigured) {
        syncState = AppSyncState.notConfigured;
        syncMessage =
            'Online sync will activate after the hosting API is connected.';
        notifyListeners();
        return;
      }
      syncState = AppSyncState.syncing;
      notifyListeners();
      final catalogSynced = await _syncCatalogSafely();
      if (signingOut) return;
      final salesError = await _downloadCompanySales();
      if (signingOut) return;
      await _reloadAll();
      final complete = preferencesSynced && catalogSynced && salesError == null;
      syncState = complete ? AppSyncState.synced : AppSyncState.failed;
      if (complete) lastSuccessfulSync = DateTime.now();
      syncMessage =
          salesError ??
          (catalogSynced && preferencesSynced
              ? 'All records synchronized.'
              : syncService.lastCustomerUploadError ??
                    'Sales downloaded; other company records failed to sync. Retry sync.');
      notifyListeners();
      return;
    }
    syncState = AppSyncState.syncing;
    syncMessage =
        'Synchronizing ${pending.length} sale${pending.length == 1 ? '' : 's'}...';
    notifyListeners();
    final result = await syncService.pushSales(pending);
    if (signingOut) return;
    switch (result.type) {
      case SyncResultType.success:
        await database.markSalesSynced(result.acceptedIds);
        final catalogSynced = await _syncCatalogSafely();
        if (signingOut) return;
        final salesError = await _downloadCompanySales();
        if (signingOut) return;
        final complete =
            preferencesSynced &&
            result.acceptedIds.length == pending.length &&
            catalogSynced &&
            salesError == null;
        syncState = complete ? AppSyncState.synced : AppSyncState.failed;
        if (syncState == AppSyncState.synced) {
          lastSuccessfulSync = DateTime.now();
        }
        syncMessage =
            salesError ??
            (complete
                ? 'Synchronization complete.'
                : result.acceptedIds.length != pending.length
                ? 'Some sales remain queued for retry.'
                : syncService.lastCustomerUploadError ??
                      'Sales downloaded; other company records failed to sync. Retry sync.');
      case SyncResultType.notConfigured:
        syncState = AppSyncState.notConfigured;
        syncMessage = result.message;
      case SyncResultType.failed:
        syncState = AppSyncState.failed;
        syncMessage = result.message;
    }
    if (result.type == SyncResultType.failed &&
        currentUser?.role == UserRole.admin) {
      final salesError = await _downloadCompanySales();
      if (salesError != null) {
        syncMessage = '${syncMessage ?? 'Sale upload failed.'} $salesError';
      }
    }
    await _reloadAll();
    notifyListeners();
  }

  Future<String?> _downloadCompanySales() async {
    if (currentUser?.role != UserRole.admin) return null;
    final companyId = currentCompany?.companyId;
    final username = currentUser?.username;
    final remote = await syncService.pullSales();
    if (companyId != currentCompany?.companyId ||
        username != currentUser?.username) {
      return 'Sales sync stopped because the signed-in account changed. Retry sync.';
    }
    if (remote == null) {
      return syncService.lastSalesDownloadError ??
          'Sales could not be downloaded. Retry sync.';
    }
    try {
      // Historical receipt imports must never deduct the current stock balance.
      await database.upsertRemoteSales(
        remote,
        applyStockChanges: false,
        notifySales: false,
      );
      await _reloadAll();
      notifyListeners();
      return null;
    } catch (_) {
      // Receipts are imported in individual transactions. Refresh any that
      // succeeded before a later malformed receipt prevented completion.
      await _reloadAll();
      notifyListeners();
      return 'Sales downloaded, but could not all be imported on this device. Existing records were retained; retry or contact support.';
    }
  }

  Future<bool> _syncCatalogSafely() async {
    try {
      return await _syncCatalog();
    } catch (_) {
      // A catalogue error must not prevent downloaded sales from being shown.
      return false;
    }
  }

  Future<bool> _syncCatalog() async {
    if (!syncService.isConfigured || signingOut) return false;
    await refreshWorkflows(force: false);
    final isAdmin = currentUser?.role == UserRole.admin;
    // Independent uploads share a network round trip; stock history still waits
    // for product reconciliation, preserving its product-code mapping.
    final uploaded = await Future.wait<bool>([
      _syncDebtPayments(),
      syncService.pushCustomers(customers),
      syncService.pushStockReceipts(stockReceipts),
      if (isAdmin) syncService.pushProducts(products),
    ]);
    if (signingOut) return false;
    var ok = uploaded.every((result) => result);
    final preserveProducts = isAdmin
        ? syncService.pendingProductCodes(products)
        : <String>{};
    final preserveCustomers = syncService.pendingCustomerPhones(customers);
    final downloads = await Future.wait<Object?>([
      syncService.pullProducts(),
      syncService.pullCustomers(),
      syncService.pullReceiptTemplateSettings(
        companyName: currentCompany?.name ?? 'Saleo Shop',
      ),
    ]);
    if (signingOut) return false;
    final remoteProducts = downloads[0] as List<Map<String, dynamic>>?;
    final remoteCustomers = downloads[1] as List<Map<String, dynamic>>?;
    final remoteSettings = downloads[2] as ReceiptTemplateSettings?;
    if (remoteProducts != null) {
      await database.upsertRemoteProducts(
        remoteProducts,
        preserveCodes: preserveProducts,
      );
    } else {
      ok = false;
    }
    if (remoteCustomers != null) {
      await database.upsertRemoteCustomers(
        remoteCustomers,
        preservePhones: preserveCustomers,
      );
    } else {
      ok = false;
    }
    // Read only the catalogue required here, not every ledger and receipt again.
    products = await database.getProducts(includeInactive: true);
    customers = await database.getCustomers();
    _rememberDownloadedCatalog(
      remoteProducts ?? [],
      remoteCustomers ?? [],
      preserveProducts,
      preserveCustomers,
    );
    final productsById = {for (final product in products) product.id: product};
    ok =
        await syncService.pushStockMovements(stockMovements, productsById) &&
        ok;
    final remoteMovements = await syncService.pullStockMovements();
    if (signingOut) return false;
    if (remoteMovements != null) {
      await database.upsertRemoteStockMovements(remoteMovements);
      stockMovements = await database.getStockMovements();
      syncService.rememberDownloadedMovements(
        stockMovements,
        products,
        remoteMovements,
      );
    } else {
      ok = false;
    }
    if (remoteSettings != null) {
      receiptTemplateSettings = remoteSettings;
      await database.saveReceiptTemplateSettings(
        _receiptTemplateScope,
        remoteSettings,
      );
    } else {
      ok = false;
    }
    ok = await _syncSharedPreferences() && ok;
    final queuedWorkflows = jsonDecode(
      await database.readWorkflowMeta('workflow.outbox') ?? '[]',
    ) as List;
    ok = queuedWorkflows.isEmpty && ok;
    await _persistCatalogSnapshot();
    return ok;
  }

  Future<bool> _syncDebtPayments() async {
    var ok = true;
    final pendingPayments = await database.getPendingDebtPayments();
    if (pendingPayments.isNotEmpty) {
      final result = await syncService.pushDebtPayments(pendingPayments);
      if (result.type == SyncResultType.success) {
        await database.markDebtPaymentsSynced(result.acceptedIds);
        ok = result.acceptedIds.length == pendingPayments.length;
      } else {
        ok = false;
      }
    }
    final remote = await syncService.pullDebtPayments();
    if (remote != null) await database.upsertRemoteDebtPayments(remote);
    return ok && remote != null;
  }

  Future<void> addProduct({
    required String name,
    required String code,
    required String category,
    required String formName,
    required int priceCents,
    required String baseUnit,
    required int unitsPerForm,
    required int openingStockBase,
    required int lowStockThreshold,
    Uint8List? imageBytes,
  }) async {
    _requireAdministrator();
    await database.addProduct(
      name: name,
      code: code,
      category: category,
      formName: formName,
      priceCents: priceCents,
      baseUnit: baseUnit,
      unitsPerForm: unitsPerForm,
      openingStockBase: openingStockBase,
      lowStockThreshold: lowStockThreshold,
      actorName: currentUser?.displayName ?? 'Administrator',
      imageBytes: imageBytes,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> importProducts(List<ProductImportRow> rows) async {
    _requireAdministrator();
    await database.importProducts(rows);
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> setProductActive(Product product, bool active) async {
    _requireAdministrator();
    await database.setProductActive(product.id, active);
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> addSellingForm(
    Product product,
    String name,
    int priceCents,
    int unitsPerForm,
  ) async {
    _requireAdministrator();
    await database.addSellingForm(
      productId: product.id,
      name: name,
      priceCents: priceCents,
      unitsPerForm: unitsPerForm,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> updateSellingForm(
    SellingForm form,
    String name,
    int priceCents,
    bool active,
    int unitsPerForm,
  ) async {
    _requireAdministrator();
    await database.updateSellingForm(
      id: form.id,
      name: name,
      priceCents: priceCents,
      active: active,
      unitsPerForm: unitsPerForm,
      actorName: currentUser?.displayName ?? 'Administrator',
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> bulkUpdateProducts(
    Set<int> ids, {
    bool? active,
    String? category,
  }) async {
    _requireAdministrator();
    await database.bulkUpdateProducts(ids, active: active, category: category);
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> updateProductDetails({
    required Product product,
    required String name,
    required String category,
    Uint8List? imageBytes,
    bool removeImage = false,
  }) async {
    _requireAdministrator();
    await database.updateProductDetails(
      id: product.id,
      name: name,
      category: category,
      imageBytes: imageBytes,
      removeImage: removeImage,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> addStockMovement({
    required Product product,
    required String type,
    required int quantityBase,
    String? note,
  }) async {
    _requireAdministrator();
    await database.addStockMovement(
      productId: product.id,
      type: type,
      quantityBase: quantityBase,
      actorName: currentUser?.displayName ?? 'Administrator',
      note: note,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> updateInventoryConfiguration({
    required Product product,
    required String baseUnit,
    required int lowStockThreshold,
  }) async {
    _requireAdministrator();
    await database.updateInventoryConfiguration(
      productId: product.id,
      baseUnit: baseUnit,
      lowStockThreshold: lowStockThreshold,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> saveInventoryPreferences(InventoryPreferences value) async {
    if (currentUser?.role != UserRole.admin &&
        (value.staffCanReceiveStock !=
                inventoryPreferences.staffCanReceiveStock ||
            value.collectCustomerDetails !=
                inventoryPreferences.collectCustomerDetails)) {
      throw StateError('Only an administrator can change company permissions.');
    }
    final old = inventoryPreferences.toSharedJson();
    inventoryPreferences = value.copyWith(
      theme: value.theme == AppThemePreference.dark
          ? AppThemePreference.dark
          : AppThemePreference.light,
    );
    final next = inventoryPreferences.toSharedJson();
    final changed = {
      for (final key in next.keys)
        if (old[key] != next[key] &&
            (currentUser?.role == UserRole.admin ||
                (key != 'staff_can_receive_stock' &&
                    key != 'collect_customer_details')))
          key: next[key],
    };
    notifyListeners();
    final scope = _preferenceScope;
    final saved = inventoryPreferences;
    _preferenceWrites = _preferenceWrites.then((_) async {
      await database.saveInventoryPreferences(saved);
      await database.writeWorkflowMeta('$scope.snapshot', jsonEncode(next));
      final pending = (jsonDecode(
        await database.readWorkflowMeta('$scope.outbox') ?? '{}',
      ) as Map).cast<String, dynamic>();
      await database.writeWorkflowMeta(
        '$scope.outbox',
        jsonEncode({...pending, ...changed}),
      );
    });
    await _preferenceWrites;
    if (!signingOut) unawaited(syncPending());
  }

  Future<void> saveProductViewPreferences(Map<String, dynamic> view) async {
    final userId = currentUser?.id;
    if (userId == null || signingOut) return;
    final scope = _preferenceScope;
    _preferenceWrites = _preferenceWrites.then((_) async {
      await database.writeWorkflowMeta(
        'product.view.$userId',
        jsonEncode(view),
      );
      final pending = (jsonDecode(
        await database.readWorkflowMeta('$scope.outbox') ?? '{}',
      ) as Map).cast<String, dynamic>();
      await database.writeWorkflowMeta(
        '$scope.outbox',
        jsonEncode({...pending, 'product_view': view}),
      );
    });
    await _preferenceWrites;
    if (!signingOut) unawaited(syncPending());
  }

  Future<Map<String, dynamic>> loadProductPriceHistory(Product product) async {
    final generation = _sessionGeneration;
    final key = 'price.server.${product.code}';
    final response = await syncService.workflowRequest(
      '/price-history?product_code=${Uri.encodeQueryComponent(product.code)}',
    );
    if (generation != _sessionGeneration || signingOut) {
      throw StateError('Account changed while loading history.');
    }
    if (response != null) {
      await database.writeWorkflowMeta(key, jsonEncode(response));
      return {
        ...response,
        'source': 'Latest 200 server-recorded changes since this feature was enabled. Unsynced edits appear after upload.',
      };
    }
    final cached = await database.readWorkflowMeta(key);
    if (cached != null) {
      return {
        ...(jsonDecode(cached) as Map).cast<String, dynamic>(),
        'source': 'Offline or server unavailable: showing the last downloaded history.',
      };
    }
    return {
      'entries': await database.productPriceHistory(product.id),
      'source': 'Server history unavailable. Showing changes recorded on this device only.',
    };
  }

  Future<void> _applySharedPreferences(Map<String, dynamic> response) async {
    await _preferenceWrites;
    final pending = (jsonDecode(
      await database.readWorkflowMeta('$_preferenceScope.outbox') ?? '{}',
    ) as Map).cast<String, dynamic>();
    final values = {
      ...(response['values'] as Map).cast<String, dynamic>(),
      ...pending,
    };
    if (values['product_view'] is Map && currentUser != null) {
      await database.writeWorkflowMeta(
        'product.view.${currentUser!.id}',
        jsonEncode(values['product_view']),
      );
    }
    inventoryPreferences = inventoryPreferences.applySharedJson(values);
    await database.saveInventoryPreferences(inventoryPreferences);
    await database.writeWorkflowMeta(
      '$_preferenceScope.snapshot',
      jsonEncode(inventoryPreferences.toSharedJson()),
    );
  }

  Future<bool> _syncSharedPreferences() async {
    if (_preferencesBusy || signingOut) return false;
    _preferencesBusy = true;
    try {
      await _preferenceWrites;
      final scope = _preferenceScope;
      final generation = _sessionGeneration;
      final pending = (jsonDecode(
        await database.readWorkflowMeta('$scope.outbox') ?? '{}',
      ) as Map).cast<String, dynamic>();
      final result = await syncService.workflowRequest(
        '/preferences',
        body: pending.isEmpty ? null : {'values': pending},
        put: true,
      );
      if (result == null || generation != _sessionGeneration || signingOut) {
        return false;
      }
      await _preferenceWrites;
      final remaining = (jsonDecode(
        await database.readWorkflowMeta('$scope.outbox') ?? '{}',
      ) as Map).cast<String, dynamic>();
      for (final key in pending.keys) {
        if (jsonEncode(remaining[key]) == jsonEncode(pending[key])) {
          remaining.remove(key);
        }
      }
      await database.writeWorkflowMeta('$scope.outbox', jsonEncode(remaining));
      await _applySharedPreferences(result);
      return true;
    } finally {
      _preferencesBusy = false;
    }
  }

  Future<bool> setExternalNotifications(bool enabled) async {
    if (enabled && !await deviceNotifications.requestPermission()) {
      return false;
    }
    await saveInventoryPreferences(
      inventoryPreferences.copyWith(showExternalNotifications: enabled),
    );
    return true;
  }

  Future<void> markNotificationRead(AppNotificationRecord item) async {
    if (!item.isRead) await database.markNotificationRead(item.id);
    notifications = await database.getNotifications();
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await database.markAllNotificationsRead();
    notifications = await database.getNotifications();
    notifyListeners();
  }

  Future<void> deleteNotification(AppNotificationRecord item) async {
    await database.deleteNotification(item.id);
    notifications = await database.getNotifications();
    notifyListeners();
  }

  Future<void> restoreNotification(AppNotificationRecord item) async {
    await database.restoreNotification(item);
    notifications = await database.getNotifications();
    notifyListeners();
  }

  Future<void> clearNotifications() async {
    await database.clearNotifications();
    notifications = const [];
    notifyListeners();
  }

  Future<void> addReceptionist({
    required String username,
    required String displayName,
    required String password,
    required String jobTitle,
  }) async {
    _requireAdministrator();
    if (currentCompany != null) {
      final created = await authService.createStaff(
        username: username,
        displayName: displayName,
        pin: password,
        jobTitle: jobTitle,
      );
      await database.upsertAuthenticatedUser(
        username: created.username,
        displayName: created.displayName,
        role: UserRole.receptionist,
        jobTitle: created.jobTitle,
      );
      await loadStaff(notify: false);
    } else {
      throw const AuthException(
        'Sign in to your company before creating staff.',
      );
    }
    await _reloadAll();
    notifyListeners();
  }

  Future<void> loadStaff({bool notify = true}) async {
    if (currentUser?.role != UserRole.admin || currentCompany == null) return;
    final generation = _sessionGeneration;
    final identity = currentUser;
    try {
      final downloaded = await authService.getStaff();
      if (generation != _sessionGeneration ||
          !identical(identity, currentUser) ||
          signingOut) {
        return;
      }
      staff = downloaded;
      staffMessage = null;
    } on AuthException catch (error) {
      if (generation != _sessionGeneration ||
          !identical(identity, currentUser) ||
          signingOut) {
        return;
      }
      staffMessage = error.message;
    }
    if (notify) notifyListeners();
  }

  Future<void> setStaffActive(StaffMember member, bool active) async {
    _requireAdministrator();
    await authService.updateStaff(
      StaffMember(
        id: member.id,
        username: member.username,
        displayName: member.displayName,
        active: active,
        archivedAt: member.archivedAt,
        recoverUntil: member.recoverUntil,
        jobTitle: member.jobTitle,
      ),
    );
    await loadStaff(notify: false);
    notifyListeners();
  }

  Future<void> updateStaffPhoto(StaffMember member, Uint8List? bytes) async {
    _requireAdministrator();
    if (currentCompany == null) {
      throw const AuthException(
        'Sign into your company to save staff photos to the server.',
      );
    }
    await authService.updateStaff(member, photoBytes: bytes, updatePhoto: true);
    await loadStaff(notify: false);
    notifyListeners();
  }

  Future<void> updateStaffDetails(
    StaffMember member, {
    required String username,
    required String displayName,
    required String jobTitle,
  }) async {
    _requireAdministrator();
    if (currentCompany != null) {
      await authService.updateStaff(
        StaffMember(
          id: member.id,
          username: username,
          displayName: displayName,
          active: member.active,
          archivedAt: member.archivedAt,
          recoverUntil: member.recoverUntil,
          jobTitle: jobTitle,
        ),
      );
      await loadStaff(notify: false);
    } else {
      await database.updateStaffDetails(
        id: member.id,
        username: username,
        displayName: displayName,
        jobTitle: jobTitle,
      );
      await _reloadAll();
    }
    notifyListeners();
  }

  Future<void> archiveStaff(StaffMember member) async {
    _requireAdministrator();
    if (member.active) {
      throw const AuthException(
        'Deactivate this staff member before moving them to the archive.',
      );
    }
    if (currentCompany != null) {
      await authService.archiveStaff(member.id);
      await loadStaff(notify: false);
    } else {
      await database.archiveUser(member.id);
      await _reloadAll();
    }
    staffMessage = '${member.displayName} moved to the 90-day archive.';
    notifyListeners();
  }

  Future<void> restoreStaff(StaffMember member) async {
    _requireAdministrator();
    if (!member.canRecover) {
      throw const AuthException('The 90-day recovery period has ended.');
    }
    if (currentCompany != null) {
      await authService.restoreStaff(member.id);
      await loadStaff(notify: false);
    } else {
      await database.restoreUser(member.id);
      await _reloadAll();
    }
    staffMessage = '${member.displayName} restored as inactive.';
    notifyListeners();
  }

  Future<void> inviteReceptionist(
    String email, {
    required String jobTitle,
  }) async {
    _requireAdministrator();
    await authService.inviteStaff(email, jobTitle: jobTitle);
    staffMessage = 'Invitation sent to ${email.trim()}.';
    notifyListeners();
  }

  Future<void> resetStaffPin(StaffMember member, String pin) async {
    _requireAdministrator();
    await authService.resetStaffPin(member.id, pin);
    staffMessage = 'PIN updated for ${member.displayName}.';
    notifyListeners();
  }

  Future<void> setUserActive(AppUser user, bool active) async {
    _requireAdministrator();
    await database.setUserActive(user.id, active);
    await _reloadAll();
    notifyListeners();
  }

  Future<void> updateCustomer(
    CustomerRecord customer, {
    required String name,
    required String phone,
    required String companyName,
    required String address,
  }) async {
    _requireAdministrator();
    await database.updateCustomer(
      customer,
      name: name,
      phone: phone,
      companyName: companyName,
      address: address,
    );
    customers = await database.getCustomers();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> deleteCustomer(CustomerRecord customer) async {
    _requireAdministrator();
    final generation = _sessionGeneration;
    final accepted = await syncService.deleteCustomer(customer.phone);
    if (!accepted || generation != _sessionGeneration || signingOut) {
      throw StateError(
        'Customer was not deleted. Server confirmation is required; retry when connected.',
      );
    }
    await database.deleteCustomer(customer.id);
    customers = await database.getCustomers();
    notifyListeners();
  }

  Future<List<DebtLedgerEntry>> debtLedger(DebtorSummary debtor) =>
      database.getDebtLedger(debtor);

  Future<DebtLedgerEntry> recordDebtPayment({
    required DebtorSummary debtor,
    required int amountCents,
    required int cashCents,
    required int mobileMoneyCents,
    required String payerName,
    required String payerPhone,
    String? note,
  }) async {
    final user = currentUser;
    if (user == null || user.role != UserRole.admin) {
      throw StateError('Administrator required');
    }
    final payment = await database.recordDebtPayment(
      debtor: debtor,
      amountCents: amountCents,
      cashCents: cashCents,
      mobileMoneyCents: mobileMoneyCents,
      receivedBy: user.displayName,
      payerName: payerName,
      payerPhone: payerPhone,
      note: note,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
    return payment;
  }

  Future<void> resolveStockDiscrepancy(
    StockDiscrepancy discrepancy,
    String reason,
  ) async {
    _requireAdministrator();
    await database.resolveStockDiscrepancy(
      id: discrepancy.id,
      resolvedBy: currentUser?.displayName ?? 'Administrator',
      reason: reason,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> receiveStock({
    required List<StockReceiptDraftItem> items,
    String? supplierName,
    String? invoiceNumber,
    bool confirm = true,
  }) async {
    if (currentUser?.active != true ||
        currentCompany == null ||
        signingOut ||
        (currentUser?.role != UserRole.admin &&
            !inventoryPreferences.staffCanReceiveStock)) {
      throw StateError(
        'Stock receiving is not authorized for this company account.',
      );
    }
    final id = await database.createStockReceipt(
      items: items,
      createdBy: currentUser?.displayName ?? 'Administrator',
      supplierName: supplierName,
      invoiceNumber: invoiceNumber,
      confirm: false,
    );
    await _reloadAll();
    final receipt = stockReceipts.firstWhere((r) => r.id == id);
    if (confirm) await submitStockForApproval(receipt);
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> confirmStockReceipt(StockReceipt receipt) async {
    throw StateError(
      'Use Approvals to review and approve this delivery on the server.',
    );
  }

  Future<void> submitStockForApproval(StockReceipt receipt) async {
    final details = receipt.toSyncJson();
    details['items'] = [
      for (final item in receipt.items)
        {
          ...item.toSyncJson(),
          'product_code': products
              .firstWhere((p) => p.id == item.productId)
              .code,
        },
    ];
    await _queueWorkflow({
      'uuid': receipt.receiptUuid,
      'kind': 'stock',
      'revision': 0,
      'reason': 'Received stock awaiting verification',
      'details': details,
    });
  }

  Future<void> reverseStockReceipt(StockReceipt receipt, String reason) async {
    _requireAdministrator();
    await database.reverseStockReceipt(
      receipt.id,
      reason,
      actorName: currentUser?.displayName ?? 'Administrator',
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> setPhysicalStock(
    Product product,
    int quantity,
    String note,
  ) async {
    _requireAdministrator();
    await database.setPhysicalStock(
      productId: product.id,
      countedQuantity: quantity,
      actorName: currentUser?.displayName ?? 'Administrator',
      note: note,
    );
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> voidSale(Sale sale, String reason) async {
    if (currentUser?.role != UserRole.admin) {
      throw StateError(
        'Use the correction workflow; administrator approval is required.',
      );
    }
    await database.voidSale(sale.id, reason);
    await _reloadAll();
    notifyListeners();
    unawaited(syncPending());
  }

  Future<void> refresh() async {
    await _reloadAll();
    notifyListeners();
  }

  void _requireAdministrator() {
    if (signingOut ||
        currentCompany == null ||
        currentUser?.active != true ||
        currentUser?.role != UserRole.admin) {
      throw StateError('An active company administrator is required.');
    }
  }

  Future<void> _reloadAll({bool alertNew = true}) async {
    savedCategories = (jsonDecode(
      await database.readWorkflowMeta('product.categories') ?? '[]',
    ) as List).cast<String>();
    products = await database.getProducts(includeInactive: true);
    users = await database.getUsers();
    final user = currentUser;
    sales = await database.getSales(
      receptionistUsername: user?.role == UserRole.receptionist
          ? user?.username
          : null,
    );
    summary = await database.getDashboardSummary();
    stockMovements = await database.getStockMovements();
    customers = await database.getCustomers();
    debtors = await database.getDebtorSummaries();
    creditPayments = await database.getCreditPayments();
    stockDiscrepancies = await database.getStockDiscrepancies();
    stockReceipts = await database.getStockReceipts();
    final savedPrints = await database.readWorkflowMeta('print.states');
    printStates = savedPrints == null
        ? {}
        : (jsonDecode(savedPrints) as Map).map(
            (key, value) => MapEntry(
              key.toString(),
              value == 'sending' ? 'check print result' : value.toString(),
            ),
          );
    final savedWorkflows = await database.readWorkflowMeta('workflow.cache');
    if (savedWorkflows != null && !_workflowBusy) {
      workflows = (jsonDecode(savedWorkflows) as List)
          .map((v) => (v as Map).cast<String, dynamic>())
          .toList();
    }
    await _preferenceWrites;
    inventoryPreferences = await database.getInventoryPreferences();
    // app_meta contains legacy company-wide defaults. Restore the signed-in
    // user's snapshot so a colleague's appearance cannot bleed into this session.
    if (currentUser != null) {
      final personal = await database.readWorkflowMeta(
        '$_preferenceScope.snapshot',
      );
      if (personal != null) {
        inventoryPreferences = inventoryPreferences.applySharedJson(
          (jsonDecode(personal) as Map).cast<String, dynamic>(),
        );
      }
    }
    final loadedNotifications = await database.getNotifications();
    if (alertNew &&
        _notificationSnapshotReady &&
        inventoryPreferences.showExternalNotifications) {
      for (final item in loadedNotifications.reversed) {
        if (!_seenNotificationIds.contains(item.id)) {
          unawaited(deviceNotifications.show(item));
        }
      }
    }
    notifications = loadedNotifications;
    _seenNotificationIds.addAll(loadedNotifications.map((item) => item.id));
    _notificationSnapshotReady = true;
    receiptTemplateSettings =
        await database.getSavedReceiptTemplateSettings(
          _receiptTemplateScope,
          companyName: currentCompany?.name ?? 'Saleo Shop',
        ) ??
        receiptTemplateSettings;
  }

  String get _receiptTemplateScope =>
      currentCompany?.companyId ?? 'local-company';

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _stopForegroundUpdates();
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    printer.dispose();
    super.dispose();
  }
}
