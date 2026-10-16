# Saleo New Desktop

Separate Windows redesign based on `C:/Users/wim/Desktop/saleo_app`.
The original source, installed app and company caches are not replaced.

## Run

The current release candidate is `App/Saleo_New_Desktop.exe`, or use
`Launch Saleo New Desktop.lnk`. Keep the entire package directory together:
its DLLs, data and native assets are required. The previous package is retained
as a rollback copy during this update; source code and company caches are preserved.

Sign in to your existing company. This app has a separate local session and an
encrypted per-company cache under `%LOCALAPPDATA%/Saleo_New_Desktop/databases`.
It downloads data through the source app's existing server connection, not by
copying another installed app's database. Sync any unsynced records in that older
app first. This project does not deploy or alter the server.

## Implemented

- Compact Windows workspace with role-specific sidebar and aligned footer.
- Receptionist navigation: Sell, Products, Receive Stock, Sales, Customers,
  Debtors, Settings. Admin navigation also includes Dashboard, Inventory, Staff,
  Reports and Profit. Settings is last.
- One Muse-inspired grey theme, with Light and Dark modes, readable coordinated
  sidebars, rounded cards/dialogs and a compact Appearance mode switch.
- Searchable Windows-inspired settings and admin-only company controls.
- Independent saved sale-draft tabs. Completing a sale deletes its draft in
  the same database transaction; other drafts remain.
- Product-grid catalogue and compact cart on wide screens, retaining existing payment checks,
  customer/receiver details, approval rules, printing and synchronization.
- Real-data dashboard, selectable periods and complete long-range revenue buckets.
- Existing products/categories, inventory, customers, debtors, payment receipts,
  staff, reporting and profit workflows from the supplied source.
- Pending-print badge, approval count and visible synchronization status.
- Two-step sign-out and the source app's unsynced-data warning.
- Saleo executable icon and encrypted Windows SQLite3MC storage.
- Pencil actions rename drafts and persist their names with the saved carts.
- Inline searchable company/customer list expands vertically, retains the
  payment content width and uses a #DCDCDD background with dark readable text.
- Matching-width product/payment reviews with aligned totals and credit balances.
- Receipt preview has a stable workspace host. Desktop checkout no longer pops
  the main route when closing the embedded cart, avoiding the blank-screen bug.
- Controller-level administrator checks for catalog, stock, staff and company changes.
- Stock receiving and checkout require an active authorized company account.
- Authentication and synchronization must use the same HTTPS server endpoint.
- Customer deletion keeps the local record until the server confirms success.
- Account changes discard late staff responses; pending settings/workflows must
  finish before synchronization can report complete.
- Catalog and stock changes request synchronization immediately after local saving.

The checkout regression simulates printing (no paper is issued) and verifies
the workspace remains visible after receipt close, including a replaced draft
screen. Physical printer verification still requires the connected device.

## Remaining work / limits

- Creditors is explicitly unconnected. A supplier balance/payment ledger requires
  server support before it can show dependable financial amounts.
- Company reset remains unavailable until server-side backup, confirmation and
  six-month retention/deletion rules are implemented.
- External Windows push notifications are not configured. In-app alerts reuse
  the existing source implementation.
- Carts are local; customer/payment dialog entries are not yet saved per draft.
  Abrupt termination during a pending write can lose the latest edit. Drafts are
  not synchronized across devices.
- Detailed business screens still reuse some existing layouts; this is not yet
  a pixel-for-pixel recreation of every earlier design preview.
- Build/test success does not establish production financial safety. Verify
  company access, permissions, cross-device sync, offline recovery, debtor payments,
  backups and a physical receipt printer before live use.

## Production release gates (not yet signed off)

Grey-theme update 1.0.2+11 (13 October 2026): Windows release build succeeded,
78 automated tests passed, and the packaged app's 20 files were checksum-verified
against the release output. Launch `App/Saleo_New_Desktop.exe` or the existing shortcut.
The previous 1.0.1+10 package is retained in `App-previous-1.0.1-before-grey`.
The Android project and local company databases were not changed by this update.
The executable remains unsigned; physical printer/live-use verification is still required.

Release candidate 1.0.1+10 (12 October 2026): Windows release build succeeded,
77 automated tests passed, and static analysis reported no issues.
The executable is unsigned. These checks are not live-server or physical-printer tests.

This is a hardened release candidate, not a certified production release.
The backend was inspected as source only; its deployed version and security
configuration have not been verified or changed by this desktop update.

- Run authenticated cross-company access tests and direct API role-bypass tests
  against a dedicated staging server with two test companies.
- Verify deployed PostgreSQL RLS, a non-superuser API database role without
  BYPASSRLS, and required migrations. A migration file alone does not prove enforcement.
- Verify session expiry/revocation, inactive staff, reset-password flows,
  rate limits, HTTPS and server-side action/audit records.
- Demonstrate encrypted backups, restoration and financial reconciliation.
- Reconcile actual offline sales, approvals and debt payments across devices.
- Complete end-to-end printer and receipt-queue recovery checks.
- Supply a publisher certificate and sign the Windows distribution before client rollout.
- Resolve the features listed above that do not yet have server support.

Sales, catalog and account preferences use the existing server synchronization;
sale drafts, notification read state and printer connections are still device-local.
Customer deletion now needs connectivity rather than silently dropping an unsent change.
No claim is made that every possible action is synchronized across devices.

Authorization checks must also be enforced on every server request, not just
in desktop UI/controller code: see the [OWASP authorization guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html).

## Development

```powershell
cd C:\Users\wim\Desktop\Saleo_New_Desktop
flutter pub get
flutter analyze
flutter test
dart run tool/build_windows_icon.dart
flutter build windows --release
```

The Dart package name remains `saleo_app` for import compatibility; the Windows
binary/product name is `Saleo_New_Desktop`.
Encryption follows the [sqlite3 package's Windows encryption guidance](https://github.com/simolus3/sqlite3.dart/blob/main/UPGRADING_TO_V3.md).
