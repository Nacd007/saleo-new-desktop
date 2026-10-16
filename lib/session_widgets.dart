import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'receipt_auth_layout.dart';

// All logout entry points use the same confirmation and data-preservation flow.
Future<void> confirmSignOut(
  BuildContext context,
  AppController controller,
) async {
  if (controller.signingOut ||
      controller.signOutPromptOpen ||
      controller.busy) {
    return;
  }
  controller.signOutPromptOpen = true;
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign out of Saleo?'),
        content: const Text(
          'Your saved company records will stay on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final pending = await controller.unsyncedRecordCount();
    if (!context.mounted) return;
    if (pending > 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('$pending unsynced record${pending == 1 ? '' : 's'}'),
          content: const Text(
            'These records are not yet saved on the server. '
            'If you sign out without syncing, they remain on this device. '
            'Sign back into the same company to upload them. Do not uninstall or clear app data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'keep'),
              child: const Text('Sign out without syncing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'sync'),
              child: const Text('Sync and sign out'),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == 'sync') {
        await controller.syncPending();
        if (await controller.unsyncedRecordCount() > 0) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Some records could not sync. You are still signed in; retry or choose sign out without syncing.',
                ),
              ),
            );
          }
          return;
        }
      }
    }
    if (!context.mounted) return;
    final finalConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Confirm sign out'),
        content: const Text(
          'Sign out now? Saved drafts and records remain on this computer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (finalConfirmation != true) return;
    await controller.logout();
    if (context.mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sign out could not finish securely. You are still signed in. Check your connection and retry; your saved records have not been deleted.',
          ),
        ),
      );
    }
  } finally {
    controller.signOutPromptOpen = false;
  }
}

class CompanyDataLoadingScreen extends StatelessWidget {
  const CompanyDataLoadingScreen({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ReceiptAuthLayout(
      section: 'OPENING YOUR WORKSPACE',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.loadingCompanyData)
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              controller.currentCompany?.name ?? 'Saleo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              controller.checkoutLoadError ?? 'Downloading products, stock, customers and checkout settings…',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (!controller.loadingCompanyData)
              FilledButton.icon(
                onPressed: controller.loadCheckoutData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry download'),
              ),
            TextButton(
              onPressed: controller.signingOut
                  ? null
                  : () => confirmSignOut(context, controller),
              child: Text(controller.signingOut ? 'Signing out…' : 'Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
