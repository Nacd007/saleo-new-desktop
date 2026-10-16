import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FourDigitPinField extends StatelessWidget {
  const FourDigitPinField({
    super.key,
    required this.controller,
    required this.label,
    this.confirmingController,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final TextEditingController? confirmingController;
  final String label;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    textInputAction: textInputAction,
    maxLength: 4,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 16),
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(4),
    ],
    decoration: InputDecoration(
      labelText: label,
      counterText: '',
      prefixIcon: const Icon(Icons.pin_outlined),
      helperText: 'Enter your 4-digit PIN.',
    ),
    onFieldSubmitted: (_) => onSubmitted?.call(),
    validator: (value) {
      final pin = value ?? '';
      if (!RegExp(r'^\d{4}$').hasMatch(pin)) return 'Enter 4 digits';
      final other = confirmingController;
      if (other != null && other.text != pin) return 'The PINs do not match';
      return null;
    },
  );
}
