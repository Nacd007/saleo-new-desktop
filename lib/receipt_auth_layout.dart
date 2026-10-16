import 'package:flutter/material.dart';

/// Shared, offline-bundled artwork for the approved Receipt Reveal direction.
/// Text and controls stay native: the picture never contains interactive UI.
class ReceiptRevealArt extends StatelessWidget {
  const ReceiptRevealArt({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Image.asset(
      'assets/branding/receipt-reveal.png',
      fit: BoxFit.contain,
      cacheWidth: 960,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => Icon(
        Icons.receipt_long_rounded,
        size: 96,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class ReceiptWordmark extends StatelessWidget {
  const ReceiptWordmark({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Saleo',
    excludeSemantics: true,
    child: Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'sale'),
          TextSpan(
            text: 'o',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -2,
        height: 1.15,
      ),
    ),
  );
}

class ReceiptAuthLayout extends StatelessWidget {
  const ReceiptAuthLayout({
    super.key,
    required this.child,
    required this.section,
    this.onBack,
    this.busy = false,
  });

  final Widget child;
  final String section;
  final VoidCallback? onBack;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: outline,
          enabledBorder: outline,
          focusedBorder: outline.copyWith(
            borderSide: BorderSide(color: colors.primary, width: 1.5),
          ),
          errorMaxLines: 3,
          helperMaxLines: 4,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 940;
          final card = Container(
            key: const ValueKey('receipt-auth-card'),
            padding: EdgeInsets.all(wide ? 32 : 24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (onBack != null) ...[
                      IconButton(
                        tooltip: 'Back',
                        onPressed: busy ? null : onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 19),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        section,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Disable duplicate navigation/requests while preserving focus.
                AbsorbPointer(absorbing: busy, child: child),
              ],
            ),
          );
          return SingleChildScrollView(
            key: const ValueKey('receipt-auth-scroll'),
            padding: EdgeInsets.all(wide ? 40 : 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - (wide ? 80 : 32)).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    height: 350,
                                    child: ReceiptRevealArt(),
                                  ),
                                  const SizedBox(height: 10),
                                  const ReceiptWordmark(size: 46),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Simple Sales, Smarter Business',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Your business. Beautifully organised.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 56),
                            Expanded(child: card),
                          ],
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ReceiptWordmark(size: 32),
                              const SizedBox(height: 20),
                              card,
                            ],
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReceiptSplashScreen extends StatelessWidget {
  const ReceiptSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          final brand = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              ReceiptWordmark(size: wide ? 76 : 44),
              const SizedBox(height: 16),
              Text(
                'Simple Sales, Smarter Business',
                textAlign: wide ? TextAlign.left : TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: MediaQuery.disableAnimationsOf(context)
                        ? const Icon(Icons.hourglass_empty_rounded, size: 18)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  const Text('Starting Saleo…'),
                ],
              ),
            ],
          );
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: wide
                    ? Row(
                        children: [
                          const Expanded(
                            flex: 6,
                            child: SizedBox(
                              height: 440,
                              child: ReceiptRevealArt(),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(flex: 5, child: brand),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            height: 240,
                            child: ReceiptRevealArt(),
                          ),
                          const SizedBox(height: 24),
                          brand,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
