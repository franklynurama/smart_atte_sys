import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final ButtonStyle? style;
  final IconData? icon;
  final bool enabled;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.style,
    this.icon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled && !isLoading ? onPressed : null,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.arrow_forward),
      label: Text(label),
      style: style,
    );
  }
}

