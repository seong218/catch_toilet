import 'package:flutter/material.dart';

class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.onRetry,
  });
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('다시 시도'),
            ),
          ],
        ],
      ),
    ),
  );
}
