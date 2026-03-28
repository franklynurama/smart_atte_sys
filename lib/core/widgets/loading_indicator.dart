import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final String? text;
  const LoadingIndicator({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (text != null) ...[
            const SizedBox(height: 12),
            Text(text!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

