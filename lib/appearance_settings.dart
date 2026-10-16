import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appearance and navigation')),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<AppThemePreference>(
            segments: const [
              ButtonSegment(
                value: AppThemePreference.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light mode'),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark mode'),
              ),
            ],
            selected: {
              controller.inventoryPreferences.theme == AppThemePreference.dark
                  ? AppThemePreference.dark
                  : AppThemePreference.light,
            },
            onSelectionChanged: (value) => controller.saveInventoryPreferences(
              controller.inventoryPreferences.copyWith(
                theme: value.first,
                accent: AppAccentPreference.blue,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.view_sidebar_outlined),
            title: Text('Navigation'),
            subtitle: Text(
              'Tablets always use side navigation. Phones use bottom tabs.',
            ),
          ),
          const Text(
            'Appearance is saved for your account and synchronized across devices.',
          ),
        ],
      ),
    ),
  );
}
